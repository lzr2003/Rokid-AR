# Rokid XR Godot

Godot 4.5 OpenXR AR 应用，目标设备：Rokid Max 2 眼镜 + Station 2 Android 控制器。

## 项目结构

```
├── project.godot                    # 主项目配置，Autoload: Station2IMU, TouchpadInput, InteractableRegistry
├── scenes/
│   ├── main.tscn                    # 入口场景，MainSceneSetup 脚本
│   └── xr_rig.tscn                  # XR 场景结构（XRCamera3D, RayInteractor, TouchPadInteractor）
├── scripts/
│   └── main_scene_setup.gd          # 平台检测 + 输入模式切换（ThreeDof vs TouchPad）
├── addons/rokid_xr/
│   ├── controller/
│   │   ├── station2_imu.gd          # Autoload, 读取 RokidXR.get_phone_pose() 获取控制器 IMU
│   │   └── three_dof_ray_pose.gd   # 射线姿态，挂 XRCamera3D 下，跟随控制器旋转
│   ├── touchpad/
│   │   ├── touchpad_input.gd        # Autoload, 触控/手柄/键盘输入捕获
│   │   └── touchpad_ray_pose.gd    # 触控板模式射线姿态（非 Station2）
│   ├── interaction/                 # 射线交互系统（RayInteractor, RayInteractable, PlaneSurface 等）
│   └── visuals/ray_visual.gd       # ImmediateMesh 射线渲染
├── rokid_godot_plugin/             # C++ GDExtension
│   ├── src/
│   │   ├── rokid_xr_extension.h/cpp # OpenXR 扩展包装器，解析 Rokid 私有 XR 函数，JNI 触控轮询
│   │   ├── jni_bridge.cpp           # 独立 JNI 桥接 .so（JNI_OnLoad 在主线程安全获取 JavaVM）
│   │   └── register_types.cpp       # 注册 "RokidXR" 引擎单例
│   ├── bin/
│   │   ├── libgdextension_rokid.*.so     # GDExtension 主库
│   │   ├── librokid_jni.*.so            # JNI 桥接库
│   │   └── rokid_xr.gdextension    # GDExtension 配置文件
│   ├── thirdparty/openxr/           # OpenXR 头文件
│   ├── libs/arm64-v8a/libopenxr_loader.so  # Rokid OpenXR Runtime 原生库引用
│   └── SConstruct                   # 构建脚本
├── android/
│   ├── plugins/
│   │   ├── android_plugin.gdap      # 注册 openxr_loader.aar
│   │   └── openxr_loader.aar       # Rokid OpenXR Runtime（含 UnityCallBridge, BridgeMgr）
│   ├── build/
│   │   ├── src/main/java/com/rokid/godot/
│   │   │   ├── TouchInitProvider.java   # ContentProvider 自动初始化，加载 librokid_jni.so
│   │   │   ├── RokidTouchBridge.java    # VirtualController 注册 + 触控状态存储
│   │   │   └── TouchReceiver.java       # BridgeMgr 反射回调目标（onTouch/onScroll）
│   │   ├── src/main/AndroidManifest.xml # Manifest chunk（ContentProvider 注册）
│   │   └── build.gradle            # Godot 生成的 Gradle 构建
│   └── build/AndroidManifest.xml    # 生成的完整 Manifest
```

## 关键数据流

### IMU（控制器陀螺仪）— 工作
```
Station 2 Controller → libopenxr_loader.so → xrGetPhonePose (OpenXR 私有函数)
  → C++ GDExtension get_phone_pose() → Dictionary{position, orientation}
  → station2_imu.gd: orientation_changed 信号
  → three_dof_ray_pose.gd: 设置射线四元数
```

### 触控板输入 — 待解决
```
Station 2 Touchpad → OpenXR InputFlinger 拦截
  → VirtualController (native) → BridgeMgr (Java)
  → 期望回调: TouchReceiver.onTouch(json) → RokidTouchBridge 静态变量
  → C++ _on_process(): JNI getDeltaX/Y/getTouchState/consumeClick
  → GDScript _poll_rokid_touch(): RokidXR.get_touch_delta/state/click
```

## JNI VMware 安全获取方案

**问题：** GDExtension .so 由 Godot 通过 `dlopen` 加载，不触发 `JNI_OnLoad`；`JNI_GetCreatedJavaVMs` 从 VkThread 调用会崩溃（ART TLS 未初始化）。

**方案：**
1. `jni_bridge.cpp` → 编译为独立 `librokid_jni.so`
2. `TouchInitProvider`（ContentProvider）→ `System.loadLibrary("rokid_jni")` → 在主线程触发 `JNI_OnLoad(JavaVM*)`
3. GDExtension → `dlopen("librokid_jni.so")` + `dlsym("rokid_get_jvm")` → 安全获取 JavaVM
4. 之后任意线程通过 `AttachCurrentThread` 安全使用 JNI

## 已知问题

1. **触控板输入未打通：** BridgeMgr 的 `selectInvoke` 只调度已注册的 `IUnityService` 服务，TouchReceiver 不在 `clazzInstanceMap` 中。Unity SDK 能工作是因为 UnityPlayer=nitySendMessage 提供了独立的分发路径。
2. **Overlay 方案：** 需要 `SYSTEM_ALERT_WINDOW` 权限（`adb shell appops` 可永久授权），但用户暂不接受。
3. **Stereo 渲染偏差：** 射线在左右眼间存在视觉偏差。

## 构建与部署

```bash
# 编译 GDExtension（需要 Android NDK）
cd rokid_godot_plugin
scons platform=android target=template_debug arch=arm64
# 产出: bin/libgdextension_rokid.android.template_debug.arm64.so
#       bin/librokid_jni.android.template_debug.arm64.so

# Godot Editor 导出 Android APK
# 或手动构建 APK：
cd android/build
./gradlew clean assembleDebug
```

## 调试

```bash
adb logcat -c && adb logcat | grep -E "RokidC\+\+|RokidTouchBridge|RokidJNI|TouchReceiver|godot"
```

关键日志标记：
- `[Step 1/5]` TouchInitProvider onCreate
- `[Step 2/5]` JNI_OnLoad / JavaVM 缓存
- `[Step 3/5]` GDExtension dlopen librokid_jni
- `[Step 4/5]` JNI FindClass / GetStaticMethodID
- `[Step 5/5]` 首次 JNI poll 成功
- `CLASS LOADED` TouchReceiver 被 BridgeMgr 加载（目前不出现）