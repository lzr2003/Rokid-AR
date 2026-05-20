extends Node3D
## 主场景初始化 — 激活触控板输入模块 + 调试 HUD (Label3D)

var _debug_label_3d: Label3D
var _touchpad_ray_pose: TouchPadRayPose
var _ray_interactor: RayInteractor
var _xr_camera: XRCamera3D

# 触控板追踪
var _tpad_touching: bool = false
var _tpad_latest_delta: Vector2 = Vector2.ZERO
var _tpad_move_count: int = 0
var _tpad_press_count: int = 0
var _tpad_release_count: int = 0

var _log_counter: int = 0


func _ready() -> void:
	var is_android := OS.get_name() == "Android"
	var use_mouse_mode := not is_android

	if TouchpadInput:
		TouchpadInput.touchpad_moved.connect(_on_tpad_moved)
		TouchpadInput.touchpad_pressed.connect(_on_tpad_pressed)
		TouchpadInput.touchpad_released.connect(_on_tpad_released)
		TouchpadInput.activate_module(use_mouse_mode)
		print_rich("[color=cyan]TouchpadInput activated (mouse_mode=%s)[/color]" % use_mouse_mode)

	_initialize_xr()
	_find_references()
	_setup_debug_label_3d()


func _initialize_xr() -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print_rich("[color=cyan]OpenXR initialized successfully[/color]")
		var vp := get_viewport()
		vp.use_xr = true


func _find_references() -> void:
	var xr_rig := find_child("XRRig", true, false)
	if xr_rig:
		_touchpad_ray_pose = xr_rig.find_child("TouchPadRayPose", true, false)
		_ray_interactor = xr_rig.find_child("RayInteractor", true, false)
		_xr_camera = xr_rig.find_child("XRCamera3D", true, false)


func _setup_debug_label_3d() -> void:
	if _xr_camera == null:
		return

	_debug_label_3d = Label3D.new()
	_debug_label_3d.name = "DebugLabel3D"
	_debug_label_3d.position = Vector3(0, 0.5, -1.5)
	_debug_label_3d.modulate = Color(0, 1, 0, 0.95)
	_debug_label_3d.font_size = 72
	_debug_label_3d.pixel_size = 0.0005
	_debug_label_3d.text = "Loading..."
	_xr_camera.add_child(_debug_label_3d)


# --- 触控板信号 ---

func _on_tpad_moved(delta: Vector2) -> void:
	_tpad_latest_delta = delta
	_tpad_move_count += 1


func _on_tpad_pressed() -> void:
	_tpad_touching = true
	_tpad_press_count += 1


func _on_tpad_released() -> void:
	_tpad_touching = false
	_tpad_release_count += 1


# --- 每帧更新 ---

func _process(_delta: float) -> void:
	_log_counter += 1

	var print_to_console := _log_counter % 60 == 0

	var text := "=== Rokid XR Debug ===\n"

	# --- 输入状态 ---
	text += "[Input] %s  mode:%s\n" % [
		"ACTIVE" if TouchpadInput.is_active() else "INACTIVE",
		"Mouse" if not OS.get_name() == "Android" else "Touch"
	]
	text += "  touching:%s  press:%d  rel:%d\n" % [_tpad_touching, _tpad_press_count, _tpad_release_count]
	text += "  delta:(%+.2f, %+.2f)  moves:%d\n" % [_tpad_latest_delta.x, _tpad_latest_delta.y, _tpad_move_count]

	# --- 旋转状态 ---
	if _touchpad_ray_pose:
		var tpr := _touchpad_ray_pose
		var fwd: Vector3 = -tpr.global_transform.basis.z
		text += "\n[Rotation]\n"
		text += "  yaw:%.2f  pitch:%.2f\n" % [tpr.yaw, tpr.pitch]
		text += "  fwd:(%.3f, %.3f, %.3f)\n" % [fwd.x, fwd.y, fwd.z]

		if print_to_console:
			print("[TPR] yaw=%.1f pitch=%.1f fwd=(%.2f,%.2f,%.2f)" % [tpr.yaw, tpr.pitch, fwd.x, fwd.y, fwd.z])

	# --- 射线交互器 ---
	if _ray_interactor:
		var ri := _ray_interactor
		var state_names: Array[String] = ["NORMAL", "HOVER", "SELECT", "DISABLED"]
		var state_name: String = state_names[ri.state]
		var dist: float = ri.ray_end.distance_to(ri.ray_origin)
		var cinfo: Dictionary = ri.collision_info
		var is_hit: bool = cinfo.get("hit", false)
		var hit_pt: Vector3 = cinfo.get("point", Vector3.ZERO)
		text += "\n[Ray]\n"
		text += "  state:%s  len:%.1fm\n" % [state_name, dist]
		text += "  origin:(%.2f,%.2f,%.2f)\n" % [ri.ray_origin.x, ri.ray_origin.y, ri.ray_origin.z]
		text += "  end:   (%.2f,%.2f,%.2f)\n" % [ri.ray_end.x, ri.ray_end.y, ri.ray_end.z]
		if is_hit:
			text += "  HIT @ (%.2f,%.2f,%.2f)" % [hit_pt.x, hit_pt.y, hit_pt.z]
		else:
			text += "  no hit"

		if print_to_console:
			print("[RI] state=%s origin=(%.1f,%.1f,%.1f) end=(%.1f,%.1f,%.1f) hit=%s" % [
				state_name,
				ri.ray_origin.x, ri.ray_origin.y, ri.ray_origin.z,
				ri.ray_end.x, ri.ray_end.y, ri.ray_end.z,
				str(is_hit)
			])

	if _debug_label_3d:
		_debug_label_3d.text = text


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_SPACE and key_event.pressed and not key_event.echo:
			if TouchpadInput.is_active():
				TouchpadInput.release_module()
				_tpad_touching = false
				print("TouchpadInput DEACTIVATED")
			else:
				TouchpadInput.activate_module(true)
				print("TouchpadInput ACTIVATED")
