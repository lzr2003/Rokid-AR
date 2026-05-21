extends Node
## Station 2 控制器 IMU 姿态读取（Autoload）
## 主路径: RokidXR.get_phone_pose()（直接读控制器）
## 备路径: Input.get_gyroscope() + Input.get_gravity()（不接眼镜时）

const FILTER_ALPHA: float = 0.02

signal orientation_changed(quat: Quaternion)
signal imu_recentered()

var orientation: Quaternion = Quaternion.IDENTITY

var _calibrated: bool = false
var _gyro_bias: Vector3 = Vector3.ZERO
var _sample_count: int = 0
var _samples: Array = []
var _log_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_calibration()


func _has_rokid_xr() -> bool:
	if not Engine.has_singleton("RokidXR"):
		print("[Station2IMU] RokidXR singleton NOT exists")
		return false
	var singleton = Engine.get_singleton("RokidXR")
	if not singleton.is_ready():
		print("[Station2IMU] RokidXR singleton exists but NOT ready")
		return false
	print("[Station2IMU] RokidXR singleton ready")
	return true


func _start_calibration() -> void:
	_calibrated = false
	_sample_count = 0
	_samples.clear()
	print("[Station2IMU] Calibrating...")


func _process(delta: float) -> void:
	# 1. 优先：RokidXR get_phone_pose()（Station 2 控制器 IMU）
	if _has_rokid_xr():
		var pose: Dictionary = Engine.get_singleton("RokidXR").get_phone_pose()
		var q: Variant = pose.get("orientation", null)
		if q != null:
			orientation = Quaternion(q.x, q.y, -q.z, q.w)
			orientation_changed.emit(orientation)
			_log_rokid(delta)
		return  # ← 有 RokidXR 就停在这里，不回退

	# 2. 无 RokidXR：Godot Input 传感器（桌面调试 / 不接眼镜）
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
	return _calibrated or _has_rokid_xr()


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
