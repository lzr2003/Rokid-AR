extends Node3D
## 触控板 → 射线姿态转换
## 订阅 TouchpadInput.touchpad_moved 信号，累加 yaw/pitch，应用旋转并进行 FOV 裁剪
class_name TouchPadRayPose

# 累加的欧拉角
var yaw: float = 0.0
var pitch: float = 0.0

# 相机引用
var render_camera: Camera3D

# FOV 裁剪边距（匹配 Unity SDK 的 cursorSize）
var cursor_margin: Vector4 = Vector4(0.01, 0.01, 0.01, 0.01)

# 缓存的 FOV 半角正切值
var _half_fov_tan: Vector4 = Vector4()
var _fov_cached: bool = false


func _ready() -> void:
	TouchpadInput.touchpad_moved.connect(_on_touchpad_moved)
	TouchpadInput.touchpad_module_activated.connect(_on_module_activated)
	TouchpadInput.touchpad_module_released.connect(_on_module_released)
	call_deferred("_find_camera")


func _find_camera() -> void:
	render_camera = _find_xr_camera() if _find_xr_camera() else get_viewport().get_camera_3d()
	if render_camera == null:
		for child in get_tree().root.get_children():
			if child is Camera3D:
				render_camera = child
				break
	reset_pose()


func _find_xr_camera() -> Camera3D:
	var xr_origin: Node = _find_xr_origin()
	if xr_origin:
		for child in xr_origin.get_children():
			if child is XRCamera3D:
				return child
	return null


func _find_xr_origin() -> Node:
	for child in get_tree().root.get_children():
		if child is XROrigin3D:
			return child
	return null


func _on_module_activated() -> void:
	reset_pose()


func _on_module_released() -> void:
	pass


func _on_touchpad_moved(delta: Vector2) -> void:
	pitch += delta.y
	yaw += delta.x
	_clamp_angles_to_fov()
	_apply_rotation()


func _apply_rotation() -> void:
	rotation = Vector3(0.0, 0.0, 0.0)
	rotate_y(deg_to_rad(yaw))
	rotate_object_local(Vector3.RIGHT, deg_to_rad(pitch))
	if render_camera:
		global_position = render_camera.global_position


func reset_pose() -> void:
	yaw = 0.0
	pitch = 0.0
	if render_camera:
		global_position = render_camera.global_position
		global_basis = render_camera.global_basis


func _clamp_angles_to_fov() -> void:
	if render_camera == null:
		return

	if not _fov_cached:
		_cache_fov()

	if _half_fov_tan == Vector4():
		return

	# 根据 FOV 半角直接限制 yaw/pitch 范围
	var half_fov_h: float = rad_to_deg(atan(_half_fov_tan.x))
	var half_fov_v: float = rad_to_deg(atan(_half_fov_tan.y))
	var margin: float = 1.0  # 1度边距

	yaw = clampf(yaw, -half_fov_h + margin, half_fov_h - margin)
	pitch = clampf(pitch, -half_fov_v + margin, half_fov_v - margin)


func _cache_fov() -> void:
	if render_camera == null:
		return

	# 方法1：从 CameraAttributesPractical 获取 FOV
	var attributes: CameraAttributes = render_camera.get_camera_attributes()
	if attributes and attributes is CameraAttributesPractical:
		var fov_deg: float = (attributes as CameraAttributesPractical).fov
		var aspect: float = get_viewport().get_visible_rect().size.aspect()
		var vfov_rad: float = deg_to_rad(fov_deg)
		var hfov_rad: float = 2.0 * atan(tan(vfov_rad / 2.0) * aspect)
		_half_fov_tan = Vector4(
			tan(hfov_rad / 2.0),
			tan(vfov_rad / 2.0),
			tan(hfov_rad / 2.0),
			tan(vfov_rad / 2.0)
		)
		_fov_cached = true
		return

	# 方法2：从投影矩阵反推
	var proj: Projection = render_camera.get_camera_projection()
	var vfov_rad: float = 2.0 * atan(1.0 / proj[1][1])
	var hfov_rad: float = 2.0 * atan(1.0 / proj[0][0])
	_half_fov_tan = Vector4(
		tan(hfov_rad / 2.0),
		tan(vfov_rad / 2.0),
		tan(hfov_rad / 2.0),
		tan(vfov_rad / 2.0)
	)
	_fov_cached = true


func _exit_tree() -> void:
	if TouchpadInput.touchpad_moved.is_connected(_on_touchpad_moved):
		TouchpadInput.touchpad_moved.disconnect(_on_touchpad_moved)
	if TouchpadInput.touchpad_module_activated.is_connected(_on_module_activated):
		TouchpadInput.touchpad_module_activated.disconnect(_on_module_activated)
	if TouchpadInput.touchpad_module_released.is_connected(_on_module_released):
		TouchpadInput.touchpad_module_released.disconnect(_on_module_released)
