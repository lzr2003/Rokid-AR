# 部署到 Station 2 指南

## 环境准备

- Godot 4.5 编辑器
- Android Debug Bridge (ADB)
- USB 数据线连接 Station 2

### 安装 ADB

```bash
# Windows (winget)
winget install Google.PlatformTools

# 或手动下载
# https://developer.android.com/tools/releases/platform-tools
```

---

## Godot Android 导出配置

### 1. 安装 Android 导出模板

```
Editor → Manage Export Templates → Download and Install
```

### 2. 配置 Android SDK

Godot 4.5 会自动下载 SDK：

```
Editor → Editor Settings → Export → Android
  → 勾选 "Auto Install Android SDK"
```

### 3. 创建导出预设

```
Project → Export → 添加 → Android

配置项:
  Package/Unique Name:  com.rokid.xr.godot
  Package/Name:         Rokid XR Godot
  XR Features Mode:     2 (AR)
  Signature:            点 "Debug Keystore" 自动生成
  Graphics/Use OpenXR:  勾选
```

---

## 一键部署

```bash
# 1. 连接 Station 2 (USB)
adb devices
# 应显示: RG-stationXR2  device

# 2. Godot 菜单
# Project → Export → 点击 Android 预设旁的 "One-Click Deploy"

# 或命令行导出 APK 后手动安装:
# godot --headless --export-debug Android
# adb install -r rokid_xr_godot.apk
```

---

## 调试

### 查看实时日志

```bash
# 清除旧日志
adb logcat -c

# 只看 Godot 输出
adb logcat -s godot

# 只看项目标签
adb logcat | grep -E "TouchpadInput|3DOF|MainScene|Station|RI|TPR"

# 保存日志到文件
adb logcat -s godot > debug.log
```

### 关键日志检查点

| 日志 TAG | 含义 |
|----------|------|
| `[TouchpadInput] model=...` | 设备型号识别 |
| `[TouchpadInput] ACTIVATED mode=...` | 输入模式激活 |
| `[TouchpadInput] evt#1 type=...` | ★ 前 20 个事件类型，诊断输入来源 |
| `[MainScene] Mode: ThreeDof` | Station 2 IMU 模式 |
| `[3DOF] fwd=...` | IMU 射线方向 |
| `[Station2IMU] Calibrated` | 陀螺仪校准完成 |

### 前 20 个事件会无条件打印类型

看到后告诉我类型，我针对性修复。常见类型：

- `InputEventKey` → D-pad 方向键
- `InputEventJoypadMotion` → 摇杆轴
- `InputEventScreenTouch` → 触摸屏
- `InputEventMouseButton/Motion` → 虚拟鼠标

---

## 常见问题

| 问题 | 解决 |
|------|------|
| `adb devices` 不显示设备 | 检查 USB 线、开启开发者模式+USB 调试 |
| Godot 报 "no Android SDK" | Editor Settings → 确认 SDK 路径 |
| APK 安装失败 | `adb install -r` 覆盖安装 |
| 日志无输出 | 确认应用已运行，`adb logcat -c` 清缓存重试 |
