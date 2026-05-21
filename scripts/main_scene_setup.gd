extends Node3D
## 主场景初始化 — 输入模式切换 + 调试 HUD

var _debug_label_3d: Label3D
var _xr_camera: XRCamera3D

# 触控板旋转（桌面/触摸板模式）
var _touchpad_ray_pose: TouchPadRayPose
var _ray_interactor_tp: RayInteractor

# Station 2 IMU 旋转
var _three_dof_ray_pose: ThreeDofRayPose
var _ray_interactor_3d: RayInteractor

# 当前活跃的射线交互器
var _active_ray_interactor: RayInteractor

# 触控板/控制器按钮输入追踪
var _tpad_touching: bool = false
var _tpad_latest_delta: Vector2 = Vector2.ZERO
var _tpad_move_count: int = 0
var _tpad_press_count: int = 0
var _tpad_release_count: int = 0

var _is_station2: bool = false
var _use_three_dof: bool = false
var _log_counter: int = 0


func _ready() -> void:
	_detect_platform()
	_initialize_xr()
	_find_references()
	_activate_input_mode()
	_setup_debug_label_3d()


func _detect_platform() -> void:
	var model := OS.get_model_name()
	_is_station2 = "RG-station" in model  # RG-stationPro / RG-stationXR2 / RG-station2
	_use_three_dof = _is_station2  # Station 2 → ThreeDof；其他 → TouchPad

	if TouchpadInput:
		TouchpadInput.touchpad_moved.connect(_on_tpad_moved)
		TouchpadInput.touchpad_pressed.connect(_on_tpad_pressed)
		TouchpadInput.touchpad_released.connect(_on_tpad_released)

	print("[MainScene] platform: model=%s station2=%s three_dof=%s" % [model, _is_station2, _use_three_dof])


func _initialize_xr() -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("[MainScene] OpenXR initialized")
		var vp := get_viewport()
		vp.use_xr = true


func _find_references() -> void:
	var xr_rig := find_child("XRRig", true, false)
	if xr_rig == null:
		return

	_xr_camera = xr_rig.find_child("XRCamera3D", true, false)

	# ThreeDof — 挂在 XRCamera3D 下
	if _xr_camera:
		_three_dof_ray_pose = _xr_camera.find_child("ThreeDofRayPose", true, false)
		_ray_interactor_3d = _xr_camera.find_child("RayInteractor3D", true, false)

	# TouchPad — 挂在 TouchPadInteractor 下
	_touchpad_ray_pose = xr_rig.find_child("TouchPadRayPose", true, false)
	_ray_interactor_tp = xr_rig.find_child("RayInteractorTP", true, false)


func _find_ray_interactor_in(node: Node) -> RayInteractor:
	if node is RayInteractor:
		return node
	for child in node.get_children():
		var found := _find_ray_interactor_in(child)
		if found:
			return found
	return null


func _activate_input_mode() -> void:
	var is_android := OS.get_name() == "Android"
	var use_mouse := not is_android

	if TouchpadInput:
		TouchpadInput.activate_module(use_mouse)
		print("[MainScene] TouchpadInput activated mouse_mode=%s" % use_mouse)

	if _use_three_dof:
		_active_ray_interactor = _ray_interactor_3d
		var tp := _find_node("TouchPadInteractor")
		if tp: tp.visible = false
		print("[MainScene] Mode: ThreeDof (Station 2 IMU)")
	else:
		_active_ray_interactor = _ray_interactor_tp
		var tp := _find_node("TouchPadInteractor")
		if tp: tp.visible = true
		print("[MainScene] Mode: TouchPad")


func _find_node(name: String) -> Node:
	var xr_rig := find_child("XRRig", true, false)
	if xr_rig:
		return xr_rig.find_child(name, true, false)
	return null


func _setup_debug_label_3d() -> void:
	if _xr_camera == null:
		return

	_debug_label_3d = Label3D.new()
	_debug_label_3d.name = "DebugLabel3D"
	_debug_label_3d.position = Vector3(0.0, 0.0, -1.0)
	_debug_label_3d.modulate = Color(0, 1, 0, 0.95)
	_debug_label_3d.font_size = 128
	_debug_label_3d.pixel_size = 0.0002
	_debug_label_3d.width = 2000.0
	_debug_label_3d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_label_3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_debug_label_3d.text = "Loading..."
	_xr_camera.add_child(_debug_label_3d)


# --- 触控板/控制器信号 ---

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

var _diag_joypads: String = ""
var _diag_xr_trackers: String = ""
var _diag_events_received: String = ""
var _diag_last_event: String = "none"

func _has_rokid_xr() -> bool:
	return Engine.has_singleton("RokidXR") and Engine.get_singleton("RokidXR").is_ready()
var _diag_scanned: bool = false


func _scan_diagnostics() -> void:
	if _diag_scanned:
		return
	_diag_scanned = true

	# 手柄
	var jps := Input.get_connected_joypads()
	if jps.is_empty():
		_diag_joypads = "none"
	else:
		_diag_joypads = ""
		for j in jps:
			_diag_joypads += "%d:%s " % [j, Input.get_joy_name(j)]

	# XR 追踪器 — 尝试已知输入名
	_diag_xr_trackers = ""
	for name in ["head", "left", "right", "/user/hand/left", "/user/hand/right"]:
		var tr := XRServer.get_tracker(name)
		if tr:
			var found: String = ""
			for pn in ["trigger", "trigger_click", "grip", "grip_click",
				"primary", "primary_click", "menu_button",
				"ax_button", "by_button", "trackpad", "thumbstick"]:
				var v = tr.get_input(pn)
				if v != null and v != 0.0 and v != false:
					found += pn + " "
			_diag_xr_trackers += "%s[%s]" % [name, found if found != "" else "-"]


func _process(_delta: float) -> void:
	_log_counter += 1
	_scan_diagnostics()

	var text: String = "LastEvt:%s Move:%d Press:%d\n" % [_diag_last_event, _tpad_move_count, _tpad_press_count]
	text += "Touch:%s d(%.0f,%.0f)\n" % [_tpad_touching, _tpad_latest_delta.x, _tpad_latest_delta.y]

	if _three_dof_ray_pose:
		var fwd: Vector3 = -_three_dof_ray_pose.global_transform.basis.z
		text += "IMU[%.2f,%.2f,%.2f]\n" % [fwd.x, fwd.y, fwd.z]

	if _active_ray_interactor:
		var ri := _active_ray_interactor
		var names: Array[String] = ["N", "H", "S", "D"]
		var d: float = ri.ray_end.distance_to(ri.ray_origin)
		var is_hit: bool = ri.collision_info.get("hit", false)
		text += "Ray:%s %.1fm %s" % [names[ri.state], d, "HIT" if is_hit else "---"]

	if _debug_label_3d:
		_debug_label_3d.text = text


func _input(event: InputEvent) -> void:
	# 记录所有事件类型到 HUD
	_diag_last_event = event.as_text().substr(0, 30)
	_diag_events_received = _diag_last_event

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_SPACE and key_event.pressed and not key_event.echo:
			if TouchpadInput.is_active():
				TouchpadInput.release_module()
				_tpad_touching = false
			else:
				TouchpadInput.activate_module(true)
