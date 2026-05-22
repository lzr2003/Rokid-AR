#include "rokid_xr_extension.h"
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/open_xrapi_extension.hpp>

#ifdef ANDROID_ENABLED
#include <jni.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#include <android/log.h>

// Linux evdev event 结构（24 字节，64-bit）
struct input_event {
    uint64_t tv_sec;
    uint64_t tv_usec;
    uint16_t type;
    uint16_t code;
    int32_t  value;
};

#define EV_SYN             0x00
#define EV_ABS             0x03
#define ABS_MT_SLOT        0x2f
#define ABS_MT_POSITION_X  0x35
#define ABS_MT_POSITION_Y  0x36
#define ABS_MT_TRACKING_ID 0x39
#define SYN_REPORT         0

#define ROKID_LOG_EV(...) __android_log_print(ANDROID_LOG_INFO, "RokidEvdev", __VA_ARGS__)
#define ROKID_ERR_EV(...) __android_log_print(ANDROID_LOG_ERROR, "RokidEvdev", __VA_ARGS__)

// ============================================================
// 直接读取 /dev/input/event4 evdev 触控板数据
// ============================================================
static int  g_evdev_fd = -1;
static bool g_evdev_ready = false;

static float g_evdev_last_x = 0.0f;
static float g_evdev_last_y = 0.0f;
static float g_evdev_cur_x  = 0.0f;
static float g_evdev_cur_y  = 0.0f;
static float g_evdev_dx     = 0.0f;
static float g_evdev_dy     = 0.0f;
static int   g_evdev_state  = 0;      // 0=up, 1=down(click), 2=move, 3=scroll
static bool  g_evdev_click_pending = false;
static bool  g_evdev_finger_down    = false;
static int   g_evdev_slot  = 0;

static void _evdev_open() {
    if (g_evdev_fd >= 0) return;
    g_evdev_fd = open("/dev/input/event4", O_RDONLY | O_NONBLOCK);
    if (g_evdev_fd < 0) {
        int e = errno;
        ROKID_ERR_EV("[Evdev] open /dev/input/event4 failed, errno=%d", e);
        return;
    }
    ROKID_LOG_EV("[Evdev] /dev/input/event4 opened, fd=", g_evdev_fd);
    g_evdev_ready = true;
}

static void _evdev_read() {
    if (!g_evdev_ready) return;

    bool any_event = false;
    while (true) {
        struct input_event ev;
        ssize_t n = read(g_evdev_fd, &ev, sizeof(ev));
        if (n <= 0) break;  // no more events (EAGAIN in non-blocking)
        any_event = true;

        if (ev.type == EV_ABS) {
            switch (ev.code) {
                case ABS_MT_SLOT:
                    g_evdev_slot = ev.value;
                    break;
                case ABS_MT_TRACKING_ID:
                    if (ev.value == -1) {
                        // 手指抬起
                        g_evdev_finger_down = false;
                        g_evdev_state = 0;
                        g_evdev_dx = 0.0f;
                        g_evdev_dy = 0.0f;
                    } else {
                        // 手指按下
                        if (!g_evdev_finger_down) {
                            g_evdev_finger_down = true;
                            g_evdev_state = 1;
                            g_evdev_click_pending = true;
                            g_evdev_dx = 0.0f;
                            g_evdev_dy = 0.0f;
                        }
                    }
                    break;
                case ABS_MT_POSITION_X:
                    g_evdev_cur_x = (float)ev.value;
                    break;
                case ABS_MT_POSITION_Y:
                    g_evdev_cur_y = (float)ev.value;
                    break;
            }
        } else if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
            // 一帧触控数据结束，计算 delta
            if (g_evdev_finger_down && g_evdev_state == 1) {
                // initial down, record baseline
                g_evdev_last_x = g_evdev_cur_x;
                g_evdev_last_y = g_evdev_cur_y;
                g_evdev_state = 2;  // move mode after first SYN_REPORT
            } else if (g_evdev_finger_down) {
                g_evdev_dx = g_evdev_cur_x - g_evdev_last_x;
                g_evdev_dy = g_evdev_cur_y - g_evdev_last_y;
                g_evdev_last_x = g_evdev_cur_x;
                g_evdev_last_y = g_evdev_cur_y;
                if (fabsf(g_evdev_dx) > 0.1f || fabsf(g_evdev_dy) > 0.1f) {
                    g_evdev_state = 2;  // moving
                }
            }
        }
    }

    static int log_count = 0;
    if (any_event && ++log_count % 30 == 0) {
        ROKID_LOG_EV("[Evdev] state=", g_evdev_state,
            " finger=", (int)g_evdev_finger_down,
            " x=", g_evdev_cur_x, " y=", g_evdev_cur_y,
            " dx=", g_evdev_dx, " dy=", g_evdev_dy);
    }
}

static void _evdev_poll(float& out_dx, float& out_dy, int& out_state, bool& out_click) {
    _evdev_open();
    if (!g_evdev_ready) return;
    _evdev_read();
    out_dx    = g_evdev_dx;
    out_dy    = g_evdev_dy;
    out_state = g_evdev_state;
    out_click = g_evdev_click_pending;
    // 消费一次性值
    g_evdev_dx = 0.0f;
    g_evdev_dy = 0.0f;
    g_evdev_click_pending = false;
}
#endif

namespace godot {

#define ROKID_LOG(...) UtilityFunctions::print("[RokidC++] [", __LINE__, "] ", __VA_ARGS__)
#define ROKID_ERR(...) UtilityFunctions::printerr("[RokidC++] [ERROR] [", __LINE__, "] ", __VA_ARGS__)

// ============================================================
// Safe JNI bridge — JavaVM obtained from librokid_jni.so (JNI_OnLoad on main thread)
// ============================================================

#ifdef ANDROID_ENABLED
static JavaVM* g_jvm = nullptr;
static jclass g_touch_class = nullptr;
static jmethodID g_get_delta_x = nullptr;
static jmethodID g_get_delta_y = nullptr;
static jmethodID g_get_touch_state = nullptr;
static jmethodID g_consume_click = nullptr;
static bool g_jni_ready = false;

// 尝试从 librokid_jni.so 获取安全的 JavaVM
static void _try_load_jvm() {
    if (g_jvm) return;
    ROKID_LOG("[Step 3/5] dlopen(\"librokid_jni.so\") ...");
    void* handle = dlopen("librokid_jni.so", RTLD_NOW);
    if (!handle) {
        ROKID_ERR("[Step 3/5] FAILED — librokid_jni.so not loaded yet: ", dlerror());
        return;
    }
    typedef JavaVM* (*PFN_rokid_get_jvm)();
    auto fn = (PFN_rokid_get_jvm)dlsym(handle, "rokid_get_jvm");
    if (fn) {
        g_jvm = fn();
        ROKID_LOG("[Step 3/5] OK — JavaVM obtained: ", g_jvm);
    } else {
        ROKID_ERR("[Step 3/5] FAILED — dlsym(\"rokid_get_jvm\") returned null");
    }
}
#endif

void RokidXRExtension::_ensure_jni() {
#ifdef ANDROID_ENABLED
    if (g_jni_ready) return;
    _try_load_jvm();
    if (!g_jvm) {
        ROKID_ERR("[Step 4/5] SKIP — g_jvm is null, JNI bridge not ready");
        return;
    }

    JNIEnv* env = nullptr;
    jint getEnvRes = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
    ROKID_LOG("[Step 4/5] GetEnv result: ", getEnvRes == JNI_OK ? "JNI_OK" : "JNI_EDETACHED");
    if (getEnvRes != JNI_OK) {
        jint attachRes = g_jvm->AttachCurrentThread(&env, nullptr);
        ROKID_LOG("[Step 4/5] AttachCurrentThread result: ", attachRes == JNI_OK ? "JNI_OK" : "FAILED");
    }
    jclass cls = env->FindClass("com/rokid/godot/RokidTouchBridge");
    if (!cls) {
        ROKID_ERR("[Step 4/5] FAILED — RokidTouchBridge class not found (will retry)");
        env->ExceptionClear();
        return;
    }
    g_touch_class = (jclass)env->NewGlobalRef(cls);
    g_get_delta_x = env->GetStaticMethodID(g_touch_class, "getDeltaX", "()F");
    g_get_delta_y = env->GetStaticMethodID(g_touch_class, "getDeltaY", "()F");
    g_get_touch_state = env->GetStaticMethodID(g_touch_class, "getTouchState", "()I");
    g_consume_click = env->GetStaticMethodID(g_touch_class, "consumeClick", "()Z");
    if (g_get_delta_x && g_get_delta_y && g_get_touch_state && g_consume_click) {
        g_jni_ready = true;
        ROKID_LOG("[Step 4/5] OK — RokidTouchBridge JNI ready");
    } else {
        ROKID_ERR("[Step 4/5] FAILED — GetStaticMethodID returned null");
    }
#endif
}

void RokidXRExtension::_poll_touch_data(float& out_dx, float& out_dy, int& out_state, bool& out_click) {
#ifdef ANDROID_ENABLED
    if (!g_jni_ready) {
        _ensure_jni();
        if (!g_jni_ready) return;
    }
    JNIEnv* env;
    if (g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) {
        g_jvm->AttachCurrentThread(&env, nullptr);
    }
    out_dx = env->CallStaticFloatMethod(g_touch_class, g_get_delta_x);
    out_dy = env->CallStaticFloatMethod(g_touch_class, g_get_delta_y);
    out_state = env->CallStaticIntMethod(g_touch_class, g_get_touch_state);
    out_click = env->CallStaticBooleanMethod(g_touch_class, g_consume_click);
    static bool s_logged_first_poll = false;
    if (!s_logged_first_poll) {
        s_logged_first_poll = true;
        ROKID_LOG("[Step 5/5] OK — First JNI poll succeeded: dx=", out_dx, " dy=", out_dy, " state=", out_state);
    }
#endif
}

// ============================================================
// Lifecycle
// ============================================================

RokidXRExtension::RokidXRExtension() {
    s_instance = this;
    ROKID_LOG("Constructor called");
    rokid_ready = false;
}

RokidXRExtension::~RokidXRExtension() {
#ifdef ANDROID_ENABLED
    if (g_touch_class && g_jvm) {
        JNIEnv* env;
        if (g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6) == JNI_OK) {
            env->DeleteGlobalRef(g_touch_class);
        }
    }
#endif
    s_instance = nullptr;
    ROKID_LOG("Destructor called");
}

void RokidXRExtension::_bind_methods() {
    ClassDB::bind_static_method("RokidXRExtension", D_METHOD("singleton"), &RokidXRExtension::singleton);
    ClassDB::bind_method(D_METHOD("is_ready"), &RokidXRExtension::is_ready);
    ClassDB::bind_method(D_METHOD("get_head_pose_rhs"), &RokidXRExtension::get_head_pose_rhs);
    ClassDB::bind_method(D_METHOD("get_camera_physics_pose"), &RokidXRExtension::get_camera_physics_pose);
    ClassDB::bind_method(D_METHOD("get_phone_pose"), &RokidXRExtension::get_phone_pose);
    ClassDB::bind_method(D_METHOD("get_slam_quality"), &RokidXRExtension::get_slam_quality);
    ClassDB::bind_method(D_METHOD("get_slam_state"), &RokidXRExtension::get_slam_state);
    ClassDB::bind_method(D_METHOD("get_camera_ypr"), &RokidXRExtension::get_camera_ypr);
    ClassDB::bind_method(D_METHOD("get_glass_name"), &RokidXRExtension::get_glass_name);
    ClassDB::bind_method(D_METHOD("check_usb_connected"), &RokidXRExtension::check_usb_connected);
    ClassDB::bind_method(D_METHOD("get_glass_firmware_version"), &RokidXRExtension::get_glass_firmware_version);
    ClassDB::bind_method(D_METHOD("get_touch_delta"), &RokidXRExtension::get_touch_delta);
    ClassDB::bind_method(D_METHOD("get_touch_state"), &RokidXRExtension::get_touch_state);
    ClassDB::bind_method(D_METHOD("consume_touch_click"), &RokidXRExtension::consume_touch_click);
}

// ============================================================
// Request OpenXR extensions
// ============================================================

Dictionary RokidXRExtension::_get_requested_extensions() {
    Dictionary exts;
    ROKID_LOG("_get_requested_extensions called");
    return exts;
}

// ============================================================
// After XrInstance created
// ============================================================

void RokidXRExtension::_on_instance_created(uint64_t p_instance) {
    ROKID_LOG("_on_instance_created triggered, XrInstance = ", p_instance);

    Ref<OpenXRAPIExtension> api = get_openxr_api();
    if (api.is_null()) {
        ROKID_ERR("Failed to get OpenXRAPIExtension");
        return;
    }
    uint64_t addr;

    addr = api->get_instance_proc_addr("xrGetHeadPoseRHS");
    pfn_get_head_pose = reinterpret_cast<PFN_xrGetHeadPoseRHS>(addr);
    ROKID_LOG("xrGetHeadPoseRHS: ", pfn_get_head_pose ? "OK" : "FAIL");

    addr = api->get_instance_proc_addr("xrGetCameraPhysicsPose");
    pfn_get_camera_pose = reinterpret_cast<PFN_xrGetCameraPhysicsPose>(addr);
    ROKID_LOG("xrGetCameraPhysicsPose: ", pfn_get_camera_pose ? "OK" : "FAIL");

    addr = api->get_instance_proc_addr("xrGetPhonePose");
    pfn_get_phone_pose = reinterpret_cast<PFN_xrGetPhonePose>(addr);
    ROKID_LOG("xrGetPhonePose: ", pfn_get_phone_pose ? "OK" : "FAIL");

    addr = api->get_instance_proc_addr("xrGetSLAMQuality");
    pfn_get_slam_quality = reinterpret_cast<PFN_xrGetSLAMQuality>(addr);
    ROKID_LOG("xrGetSLAMQuality: ", pfn_get_slam_quality ? "OK" : "FAIL");

    addr = api->get_instance_proc_addr("xrGetHeadTrackingStatus");
    pfn_get_slam_state = reinterpret_cast<PFN_xrGetSlamState>(addr);
    ROKID_LOG("xrGetHeadTrackingStatus: ", pfn_get_slam_state ? "OK" : "FAIL");

    addr = api->get_instance_proc_addr("xrGetCameraYPR");
    pfn_get_camera_ypr = reinterpret_cast<PFN_xrGetCameraYPR>(addr);
    ROKID_LOG("xrGetCameraYPR: ", pfn_get_camera_ypr ? "OK" : "FAIL");

    addr = api->get_instance_proc_addr("xrGetGlassName");
    pfn_get_glass_name = reinterpret_cast<PFN_xrGetGlassName>(addr);
    ROKID_LOG("xrGetGlassName: ", pfn_get_glass_name ? "OK" : "FAIL");

    addr = api->get_instance_proc_addr("xrIsUsbConnect");
    pfn_is_usb_connect = reinterpret_cast<PFN_xrIsUsbConnect>(addr);
    ROKID_LOG("xrIsUsbConnect: ", pfn_is_usb_connect ? "OK" : "FAIL");

    addr = api->get_instance_proc_addr("xrGetGlassFirmwareVersion");
    pfn_get_glass_fw = reinterpret_cast<PFN_xrGetGlassFirmwareVersion>(addr);
    ROKID_LOG("xrGetGlassFirmwareVersion: ", pfn_get_glass_fw ? "OK" : "FAIL");
}

// ============================================================
// After XrSession created
// ============================================================

void RokidXRExtension::_on_session_created(uint64_t p_session) {
    ROKID_LOG("_on_session_created triggered, XrSession = ", p_session);
    rokid_ready = true;
}

// ============================================================
// Destroy callbacks
// ============================================================

void RokidXRExtension::_on_session_destroyed() {
    ROKID_LOG("_on_session_destroyed triggered");
    rokid_ready = false;
}

void RokidXRExtension::_on_instance_destroyed() {
    ROKID_LOG("_on_instance_destroyed triggered");
    pfn_get_head_pose = nullptr;
    pfn_get_camera_pose = nullptr;
    pfn_get_phone_pose = nullptr;
    pfn_get_slam_quality = nullptr;
    pfn_get_slam_state = nullptr;
    pfn_get_camera_ypr = nullptr;
    pfn_get_glass_name = nullptr;
    pfn_is_usb_connect = nullptr;
    pfn_get_glass_fw = nullptr;
    rokid_ready = false;
}

// ============================================================
// Per-frame callback
// ============================================================

void RokidXRExtension::_on_process() {
#ifdef ANDROID_ENABLED
    float dx = 0, dy = 0;
    int state = 0;
    bool click = false;
    // 优先使用 evdev 直接读取，失败则回退 JNI
    _evdev_poll(dx, dy, state, click);
    if (!g_evdev_ready) {
        _poll_touch_data(dx, dy, state, click);
    }
    _touch_delta_x.store(dx);
    _touch_delta_y.store(dy);
    _touch_state.store(state);
    if (click) _touch_click_pending.store(true);
#endif
}

// ============================================================
// GDScript interface
// ============================================================

Dictionary RokidXRExtension::get_head_pose_rhs() {
    Dictionary result;
    if (!pfn_get_head_pose) return result;
    float position[3] = {0.0f, 0.0f, 0.0f};
    float orientation[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    int64_t timestamp = 0;
    if (pfn_get_head_pose(position, orientation, &timestamp) == XR_SUCCESS) {
        result["position"] = Vector3(position[0], position[1], position[2]);
        result["orientation"] = Quaternion(orientation[0], orientation[1], orientation[2], orientation[3]);
        result["timestamp"] = timestamp;
    }
    return result;
}

Dictionary RokidXRExtension::get_camera_physics_pose() {
    Dictionary result;
    if (!pfn_get_camera_pose) return result;
    uint64_t timestamp = 0;
    float position[3] = {0.0f, 0.0f, 0.0f};
    float orientation[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    if (pfn_get_camera_pose(&timestamp, position, orientation) == XR_SUCCESS) {
        result["position"] = Vector3(position[0], position[1], position[2]);
        result["orientation"] = Quaternion(orientation[0], orientation[1], orientation[2], orientation[3]);
        result["timestamp_us"] = timestamp;
    }
    return result;
}

Dictionary RokidXRExtension::get_phone_pose() {
    Dictionary result;
    if (!pfn_get_phone_pose) return result;
    float position[3] = {0.0f, 0.0f, 0.0f};
    float orientation[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    if (pfn_get_phone_pose(position, orientation) == XR_SUCCESS) {
        result["position"] = Vector3(position[0], position[1], position[2]);
        result["orientation"] = Quaternion(orientation[0], orientation[1], orientation[2], orientation[3]);
    }
    return result;
}

Dictionary RokidXRExtension::get_slam_quality() {
    Dictionary result;
    if (!pfn_get_slam_quality) return result;
    uint32_t tracking = 0, image = 0, kinetic = 0;
    if (pfn_get_slam_quality(&tracking, &image, &kinetic) == XR_SUCCESS) {
        result["tracking"] = tracking;
        result["image"] = image;
        result["kinetic"] = kinetic;
    }
    return result;
}

int RokidXRExtension::get_slam_state() {
    if (!pfn_get_slam_state) return -1;
    uint32_t state = 0;
    pfn_get_slam_state(&state);
    return static_cast<int>(state);
}

Vector3 RokidXRExtension::get_camera_ypr() {
    if (!pfn_get_camera_ypr) return Vector3();
    float ypr[3] = {0};
    pfn_get_camera_ypr(ypr);
    return Vector3(ypr[0], ypr[1], ypr[2]);
}

String RokidXRExtension::get_glass_name() {
    if (!pfn_get_glass_name) return "";
    char buf[256] = {0};
    pfn_get_glass_name(buf, sizeof(buf));
    return String(buf);
}

bool RokidXRExtension::check_usb_connected() {
    if (!pfn_is_usb_connect) return false;
    uint32_t connected = 0;
    pfn_is_usb_connect(&connected);
    return connected != 0;
}

String RokidXRExtension::get_glass_firmware_version() {
    if (!pfn_get_glass_fw) return "";
    char buf[256] = {0};
    pfn_get_glass_fw(buf, sizeof(buf));
    return String(buf);
}

Vector2 RokidXRExtension::get_touch_delta() {
    float dx = _touch_delta_x.exchange(0.0f);
    float dy = _touch_delta_y.exchange(0.0f);
    return Vector2(dx, dy);
}

int RokidXRExtension::get_touch_state() {
    return _touch_state.load();
}

bool RokidXRExtension::consume_touch_click() {
    return _touch_click_pending.exchange(false);
}

} // namespace godot
