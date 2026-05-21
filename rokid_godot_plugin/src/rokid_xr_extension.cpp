#include "rokid_xr_extension.h"
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/open_xrapi_extension.hpp>

namespace godot {

#define ROKID_LOG(...) UtilityFunctions::print("[RokidC++] [", __LINE__, "] ", __VA_ARGS__)
#define ROKID_ERR(...) UtilityFunctions::printerr("[RokidC++] [ERROR] [", __LINE__, "] ", __VA_ARGS__)

// ============================================================
// Lifecycle
// ============================================================

RokidXRExtension::RokidXRExtension() {
    s_instance = this;
    ROKID_LOG("Constructor called");
    rokid_ready = false;
}

RokidXRExtension::~RokidXRExtension() {
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
    ROKID_LOG("OpenXRAPIExtension obtained successfully");

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
// Per-frame callback (no JNI — touch handled by GDScript via file)
// ============================================================

void RokidXRExtension::_on_process() {
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
    XrResult res = pfn_get_head_pose(position, orientation, &timestamp);
    if (res == XR_SUCCESS) {
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
    XrResult res = pfn_get_camera_pose(&timestamp, position, orientation);
    if (res == XR_SUCCESS) {
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
    XrResult res = pfn_get_phone_pose(position, orientation);
    if (res == XR_SUCCESS) {
        result["position"] = Vector3(position[0], position[1], position[2]);
        result["orientation"] = Quaternion(orientation[0], orientation[1], orientation[2], orientation[3]);
    }
    return result;
}

Dictionary RokidXRExtension::get_slam_quality() {
    Dictionary result;
    if (!pfn_get_slam_quality) return result;
    uint32_t tracking = 0, image = 0, kinetic = 0;
    XrResult res = pfn_get_slam_quality(&tracking, &image, &kinetic);
    if (res == XR_SUCCESS) {
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

} // namespace godot
