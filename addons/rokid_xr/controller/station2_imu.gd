extends Node
## Station 2 控制器 IMU 姿态读取（Autoload）
## 主路径: XRServer.get_tracker("head") — OpenXR 头部追踪
## 备路径: Input.get_gyroscope() + Input.get_gravity() — Android 原生传感器

const FILTER_ALPHA: float = 0.02

signal orientation_changed(quat: Quaternion)
signal imu_recentered()
signal gesture_click()

var orientation: Quaternion = Quaternion.IDENTITY

var _calibrated: bool = false
var _gyro_bias: Vector3 = Vector3.ZERO
var _sample_count: int = 0
var _samples: Array = []
var _log_timer: float = 0.0
var _use_xr: bool = false

# 手势检测：快速翻转 → 点击
const SHAKE_THRESHOLD: float = 5.0       # rad/s, 约 286°/s
const GESTURE_COOLDOWN: float = 0.8       # 两次手势间最少间隔
var _gesture_cooldown_timer: float = 0.0
var _was_shaking: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_calibration()


func _start_calibration() -> void:
	_calibrated = false
	_sample_count = 0
	_samples.clear()
	print("[Station2IMU] Calibrating...")


func _process(delta: float) -> void:
	# 1. 优先：RokidXR GDExtension get_phone_pose()（直接读 Station 2 IMU）
	if RokidXR and RokidXR.is_ready():
		var pose: Dictionary = RokidXR.get_phone_pose()
		if not pose.is_empty() and pose.has("orientation"):
			var q: Quaternion = pose["orientation"]
			# Unity SDK: data[2] = -data[2] 坐标转换
			orientation = Quaternion(q.x, q.y, -q.z, q.w)
			orientation_changed.emit(orientation)
			_log_rokid(delta)
			return

	# 2. OpenXR 头部追踪
	var xr_orient: Variant = _get_xr_head_orientation()
	if xr_orient != null:
		if not _use_xr:
			_use_xr = true
			print("[Station2IMU] Using XR head tracker")
		orientation = xr_orient
		orientation_changed.emit(orientation)
		_log_xr(delta)
		return

	# 3. 兜底：Godot Input 传感器
	var gyro: Vector3 = Input.get_gyroscope()

	if not _calibrated:
		_samples.append(gyro)
		_sample_count += 1
		if _sample_count >= 60:
			_gyro_bias = Vector3.ZERO
			for s in _samples:
				_gyro_bias += s
			_gyro_bias /= float(_samples.size())
			_calibrated = true
			print("[Station2IMU] Calibrated bias=(%.4f,%.4f,%.4f)" % [_gyro_bias.x, _gyro_bias.y, _gyro_bias.z])
		return

	gyro -= _gyro_bias
	_update_orientation(gyro, delta)
	_log_sensors(gyro)


func _get_xr_head_orientation() -> Variant:
	var tracker: XRPositionalTracker = XRServer.get_tracker("head")
	if tracker == null:
		return null
	var xr_pose: XRPose = tracker.get_pose("default")
	if xr_pose == null:
		return null
	var t: Transform3D = xr_pose.transform
	if t == Transform3D.IDENTITY or t == Transform3D():
		return null
	return t.basis.get_rotation_quaternion()


func _update_orientation(gyro: Vector3, delta: float) -> void:
	var angle: float = gyro.length() * delta
	var axis: Vector3 = Vector3.FORWARD
	if angle > 0.0001:
		axis = gyro.normalized()
	var delta_q: Quaternion = Quaternion(axis, angle)
	var gyro_orient: Quaternion = orientation * delta_q

	var gravity: Vector3 = Input.get_gravity()
	if gravity.length_squared() > 0.1:
		gravity = gravity.normalized()
		var gyro_down: Vector3 = gyro_orient * Vector3.DOWN
		var correction: Quaternion = _shortest_arc(gyro_down, gravity)
		orientation = gyro_orient.slerp(correction * gyro_orient, FILTER_ALPHA)
	else:
		orientation = gyro_orient

	orientation = orientation.normalized()
	orientation_changed.emit(orientation)


func _log_rokid(delta: float) -> void:
	_log_timer += delta
	if _log_timer > 2.0:
		_log_timer = 0.0
		print("[Station2IMU] RokidXR phone_pose orient=(%.2f,%.2f,%.2f,%.2f)" % [
			orientation.x, orientation.y, orientation.z, orientation.w
		])


func _log_xr(delta: float) -> void:
	_log_timer += delta
	if _log_timer > 2.0:
		_log_timer = 0.0
		var euler: Vector3 = orientation.get_euler()
		print("[Station2IMU] XR head euler=(%.1f,%.1f,%.1f)" % [
			rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)
		])


func _log_sensors(gyro: Vector3) -> void:
	_log_timer += 1.0 / 60.0
	if _log_timer > 2.0:
		_log_timer = 0.0
		var grav: Vector3 = Input.get_gravity()
		print("[Station2IMU] raw gyro=(%.3f,%.3f,%.3f) grav=(%.2f,%.2f,%.2f)" % [
			gyro.x, gyro.y, gyro.z, grav.x, grav.y, grav.z
		])


func recenter() -> void:
	orientation = Quaternion.IDENTITY
	_start_calibration()
	imu_recentered.emit()


func is_calibrated() -> bool:
	return _calibrated or _use_xr


func _shortest_arc(from: Vector3, to: Vector3) -> Quaternion:
	var cross: Vector3 = from.cross(to)
	var dot: float = from.dot(to)
	var sq_len: float = cross.length_squared()

	if sq_len < 0.00001:
		if dot > 0:
			return Quaternion.IDENTITY
		else:
			var perp: Vector3 = Vector3.RIGHT if abs(from.x) < 0.999 else Vector3.UP
			perp = (perp - from * from.dot(perp)).normalized()
			return Quaternion(perp, PI)
	else:
		var angle: float = atan2(sqrt(sq_len), dot)
		return Quaternion(cross.normalized(), angle)
