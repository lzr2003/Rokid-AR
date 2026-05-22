#pragma once
#include <godot_cpp/classes/open_xr_extension_wrapper_extension.hpp>
#include <godot_cpp/classes/open_xrapi_extension.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <atomic>

namespace godot {

typedef uint64_t XrInstance;
typedef uint64_t XrSession;
typedef int64_t XrResult;
#define XR_SUCCESS 0

typedef XrResult (*PFN_xrGetHeadPoseRHS)(float*, float*, int64_t*);
typedef XrResult (*PFN_xrGetCameraPhysicsPose)(uint64_t*, float*, float*);
typedef XrResult (*PFN_xrGetPhonePose)(float*, float*);
typedef XrResult (*PFN_xrGetSLAMQuality)(uint32_t*, uint32_t*, uint32_t*);
typedef XrResult (*PFN_xrGetSlamState)(uint32_t*);
typedef XrResult (*PFN_xrGetCameraYPR)(float*);
typedef XrResult (*PFN_xrGetGlassName)(char*, int32_t);
typedef XrResult (*PFN_xrIsUsbConnect)(uint32_t*);
typedef XrResult (*PFN_xrGetGlassFirmwareVersion)(char*, int32_t);

class RokidXRExtension : public OpenXRExtensionWrapperExtension {
    GDCLASS(RokidXRExtension, OpenXRExtensionWrapperExtension)
private:
    static inline RokidXRExtension* s_instance = nullptr;
    bool rokid_ready = false;

    PFN_xrGetHeadPoseRHS        pfn_get_head_pose        = nullptr;
    PFN_xrGetCameraPhysicsPose  pfn_get_camera_pose      = nullptr;
    PFN_xrGetPhonePose          pfn_get_phone_pose       = nullptr;
    PFN_xrGetSLAMQuality        pfn_get_slam_quality     = nullptr;
    PFN_xrGetSlamState          pfn_get_slam_state       = nullptr;
    PFN_xrGetCameraYPR          pfn_get_camera_ypr       = nullptr;
    PFN_xrGetGlassName          pfn_get_glass_name       = nullptr;
    PFN_xrIsUsbConnect          pfn_is_usb_connect       = nullptr;
    PFN_xrGetGlassFirmwareVersion pfn_get_glass_fw       = nullptr;

    // 触控数据
    std::atomic<float> _touch_delta_x{0.0f};
    std::atomic<float> _touch_delta_y{0.0f};
    std::atomic<int>   _touch_state{0};
    std::atomic<bool>  _touch_click_pending{false};

    void _ensure_jni();
    void _poll_touch_data(float& out_dx, float& out_dy, int& out_state, bool& out_click);

protected:
    static void _bind_methods();
public:
    static RokidXRExtension* singleton() { return s_instance; }

    RokidXRExtension();
    ~RokidXRExtension();

    virtual Dictionary _get_requested_extensions() override;
    virtual void _on_instance_created(uint64_t p_instance) override;
    virtual void _on_session_created(uint64_t p_session) override;
    virtual void _on_session_destroyed() override;
    virtual void _on_instance_destroyed() override;
    virtual void _on_process() override;

    bool is_ready() const { return rokid_ready; }
    Dictionary get_head_pose_rhs();
    Dictionary get_camera_physics_pose();
    Dictionary get_phone_pose();
    Dictionary get_slam_quality();
    int get_slam_state();
    Vector3 get_camera_ypr();
    String get_glass_name();
    bool check_usb_connected();
    String get_glass_firmware_version();

    Vector2 get_touch_delta();
    int get_touch_state();
    bool consume_touch_click();
};

} // namespace godot
