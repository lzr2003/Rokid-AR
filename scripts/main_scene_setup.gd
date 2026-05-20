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
	_is_station2 = "RG-stationPro" in model or "RG-stationXR2" in model
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

	# ThreeDof 节点
	_three_dof_ray_pose = xr_rig.find_child("ThreeDofRayPose", true, false)

	# TouchPad 节点
	_touchpad_ray_pose = xr_rig.find_child("TouchPadRayPose", true, false)

	# RayInteractor — 需要通过节点名精确匹配
	var three_dof_interactor := xr_rig.find_child("ThreeDofInteractor", true, false)
	if three_dof_interactor:
		_ray_interactor_3d = _find_ray_interactor_in(three_dof_interactor)

	var tp_interactor := xr_rig.find_child("TouchPadInteractor", true, false)
	if tp_interactor:
		_ray_interactor_tp = _find_ray_interactor_in(tp_interactor)


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
		# Station 2: ThreeDofInteractor 激活，TouchPadInteractor 隐藏
		_active_ray_interactor = _ray_interactor_3d
		var td := _find_node("ThreeDofInteractor")
		if td: td.visible = true
		var tp := _find_node("TouchPadInteractor")
		if tp: tp.visible = false
		print("[MainScene] Mode: ThreeDof (Station 2 IMU)")
	else:
		# 桌面 / 普通触摸板
		_active_ray_interactor = _ray_interactor_tp
		var td := _find_node("ThreeDofInteractor")
		if td: td.visible = false
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

func _process(_delta: float) -> void:
	_log_counter += 1
	var print_to_console := _log_counter % 60 == 0

	var text: String = ""
	text += "%s on %s\n" % [
		"3DOF" if _use_three_dof else "TPAD",
		OS.get_model_name()
	]

	# --- 输入 ---
	text += "touch:%s d(%+.1f,%+.1f) m:%d p:%d/%d\n" % [
		_tpad_touching, _tpad_latest_delta.x, _tpad_latest_delta.y,
		_tpad_move_count, _tpad_press_count, _tpad_release_count
	]

	# --- Station 2 IMU ---
	if _use_three_dof and _three_dof_ray_pose:
		var td := _three_dof_ray_pose
		var fwd: Vector3 = -td.global_transform.basis.z
		text += "IMU: cal=%s fwd(%.2f,%.2f,%.2f)\n" % [
			Station2IMU.is_calibrated(), fwd.x, fwd.y, fwd.z
		]
		if print_to_console:
			print("[3DOF] cal=%s fwd=(%.2f,%.2f,%.2f) quat=%s" % [
				Station2IMU.is_calibrated(), fwd.x, fwd.y, fwd.z, td.quaternion
			])

	# --- TouchPad 旋转 ---
	if not _use_three_dof and _touchpad_ray_pose:
		var tp := _touchpad_ray_pose
		var fwd: Vector3 = -tp.global_transform.basis.z
		text += "TP:y%.0f p%.0f fwd(%.2f,%.2f,%.2f)\n" % [tp.yaw, tp.pitch, fwd.x, fwd.y, fwd.z]
		if print_to_console:
			print("[TP] yaw=%.1f pitch=%.1f fwd=(%.2f,%.2f,%.2f)" % [tp.yaw, tp.pitch, fwd.x, fwd.y, fwd.z])

	# --- 活跃射线 ---
	if _active_ray_interactor:
		var ri := _active_ray_interactor
		var state_names: Array[String] = ["N", "H", "S", "D"]
		var dist: float = ri.ray_end.distance_to(ri.ray_origin)
		var cinfo: Dictionary = ri.collision_info
		var is_hit: bool = cinfo.get("hit", false)
		text += "Ray:%s %.1fm " % [state_names[ri.state], dist]
		if is_hit:
			var hit_pt: Vector3 = cinfo.get("point", Vector3.ZERO)
			text += "HIT(%.1f,%.1f,%.1f)" % [hit_pt.x, hit_pt.y, hit_pt.z]
		else:
			text += "no hit"

		if print_to_console:
			print("[Ray] state=%s dist=%.1f hit=%s" % [state_names[ri.state], dist, str(is_hit)])

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
