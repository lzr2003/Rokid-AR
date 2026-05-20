#include "register_types.h"
#include "rokid_xr_extension.h"
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/classes/engine.hpp>

using namespace godot;

static RokidXRExtension* g_rokid_ext = nullptr;

// 可变参数宏（支持多参数打印）
#define ROKID_LOG(...) UtilityFunctions::print("[RokidC++] [", __LINE__, "] ", __VA_ARGS__)
#define ROKID_ERR(...) UtilityFunctions::printerr("[RokidC++] [ERROR] [", __LINE__, "] ", __VA_ARGS__)

void initialize_rokid_module(ModuleInitializationLevel p_level) {
    // 1. 在最底层的 CORE 阶段：埋伏 OpenXR 拦截器
    if (p_level == MODULE_INITIALIZATION_LEVEL_CORE) {
        ClassDB::register_class<RokidXRExtension>();
        g_rokid_ext = memnew(RokidXRExtension);
        
        // 确保绝对不会错过 _get_requested_extensions 和 _on_instance_created
        g_rokid_ext->register_extension_wrapper();
        ROKID_LOG("Wrapper registered at CORE level");
    }

    // 2. 在上层的 SCENE 阶段：暴露给 GDScript（此时脚本引擎已就绪）
    if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        Engine::get_singleton()->register_singleton("RokidXR", g_rokid_ext);
        ROKID_LOG("Singleton registered at SCENE level");
    }
}

void uninitialize_rokid_module(ModuleInitializationLevel p_level) {
    if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        Engine::get_singleton()->unregister_singleton("RokidXR");
    }

    if (p_level == MODULE_INITIALIZATION_LEVEL_CORE) {
        if (g_rokid_ext) {
            memdelete(g_rokid_ext);
            g_rokid_ext = nullptr;
        }
    }
}

extern "C" {
GDExtensionBool GDE_EXPORT
rokid_xr_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
              GDExtensionClassLibraryPtr p_library,
              GDExtensionInitialization *r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(
        p_get_proc_address, p_library, r_initialization
    );
    init_obj.register_initializer(initialize_rokid_module);
    init_obj.register_terminator(uninitialize_rokid_module);
    
    // ✅ 恢复为 CORE：告诉引擎我们的库从最底层就开始介入
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_CORE);
    return init_obj.init();
}
}