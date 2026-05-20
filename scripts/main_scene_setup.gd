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
	_debug_label_3d.position = Vector3(0.0, 0.0, -1.5)
	_debug_label_3d.modulate = Color(0, 1, 0, 0.95)
	_debug_label_3d.font_size = 56
	_debug_label_3d.pixel_size = 0.0004
	_debug_label_3d.width = 2000.0
	_debug_label_3d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_label_3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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

	var text: String = ""

	# --- 输入 ---
	text += "t:%s d(%+.1f,%+.1f) m:%d p:%d/%d\n" % [
		_tpad_touching,
		_tpad_latest_delta.x, _tpad_latest_delta.y,
		_tpad_move_count,
		_tpad_press_count, _tpad_release_count
	]

	# --- 旋转 ---
	if _touchpad_ray_pose:
		var tpr := _touchpad_ray_pose
		var fwd: Vector3 = -tpr.global_transform.basis.z
		text += "y:%.0f p:%.0f f:(%.2f,%.2f,%.2f)\n" % [tpr.yaw, tpr.pitch, fwd.x, fwd.y, fwd.z]

		if print_to_console:
			print("[TPR] yaw=%.1f pitch=%.1f fwd=(%.2f,%.2f,%.2f)" % [tpr.yaw, tpr.pitch, fwd.x, fwd.y, fwd.z])

	# --- 射线 ---
	if _ray_interactor:
		var ri := _ray_interactor
		var state_names: Array[String] = ["N", "H", "S", "D"]
		var dist: float = ri.ray_end.distance_to(ri.ray_origin)
		var cinfo: Dictionary = ri.collision_info
		var is_hit: bool = cinfo.get("hit", false)
		text += "R:%s %.1fm " % [state_names[ri.state], dist]
		if is_hit:
			var hit_pt: Vector3 = cinfo.get("point", Vector3.ZERO)
			text += "HIT(%.1f,%.1f,%.1f)" % [hit_pt.x, hit_pt.y, hit_pt.z]
		else:
			text += "no hit"

		if print_to_console:
			print("[RI] state=%s origin=(%.1f,%.1f,%.1f) end=(%.1f,%.1f,%.1f) hit=%s" % [
				state_names[ri.state],
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
