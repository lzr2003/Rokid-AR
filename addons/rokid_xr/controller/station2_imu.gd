extends Node
## Station 2 控制器 IMU 姿态读取（Autoload）
## 双路径：
##   主路径: XRServer.get_tracker("head") — OpenXR 头部追踪（Station 2 即 head）
##   备路径: Input.get_gyroscope() + Input.get_gravity() — Android 原生传感器

const FILTER_ALPHA: float = 0.02

signal orientation_changed(quat: Quaternion)
signal imu_recentered()

var orientation: Quaternion = Quaternion.IDENTITY

var _calibrated: bool = false
var _gyro_bias: Vector3 = Vector3.ZERO
var _sample_count: int = 0
var _samples: Array = []
var _log_timer: float = 0.0
var _use_xr: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_calibration()


func _start_calibration() -> void:
	_calibrated = false
	_sample_count = 0
	_samples.clear()
	print("[Station2IMU] Calibrating...")


func _process(delta: float) -> void:
	# 主路径：尝试从 OpenXR 获取头部姿态
	var xr_orientation := _get_xr_head_orientation()
	if xr_orientation != null:
		if not _use_xr:
			_use_xr = true
			print("[Station2IMU] Using XR head tracker")
		orientation = xr_orientation
		orientation_changed.emit(orientation)
		_log_xr(delta)
		return

	# 备路径：Android 原生传感器
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
			_log_sensors(gyro)
		return

	gyro -= _gyro_bias
	_update_orientation(gyro, delta)
	_log_sensors(gyro)


func _get_xr_head_orientation() -> Variant:
	var tracker: XRPositionalTracker = XRServer.get_tracker("head")
	if tracker == null:
		return null
	var pose: Transform3D = tracker.get_pose()
	if pose == Transform3D.IDENTITY or pose == Transform3D():
		return null
	return pose.basis.get_rotation_quaternion()


func _update_orientation(gyro: Vector3, delta: float) -> void:
	var angle := gyro.length() * delta
	var axis: Vector3
	if angle > 0.0001:
		axis = gyro.normalized()
	else:
		axis = Vector3.FORWARD
	var delta_q := Quaternion(axis, angle)
	var gyro_orientation := orientation * delta_q

	var gravity: Vector3 = Input.get_gravity()
	if gravity.length_squared() > 0.1:
		gravity = gravity.normalized()
		var gyro_down: Vector3 = gyro_orientation * Vector3.DOWN
		var correction_q := _shortest_arc(gyro_down, gravity)
		orientation = gyro_orientation.slerp(correction_q * gyro_orientation, FILTER_ALPHA)
	else:
		orientation = gyro_orientation

	orientation = orientation.normalized()
	orientation_changed.emit(orientation)


func _log_xr(delta: float) -> void:
	_log_timer += delta
	if _log_timer > 2.0:
		_log_timer = 0.0
		var euler := orientation.get_euler()
		print("[Station2IMU] XR head euler=(%.1f,%.1f,%.1f)" % [
			rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)
		])


func _log_sensors(gyro: Vector3) -> void:
	_log_timer += 1.0 / 60.0  # rough
	if _log_timer > 2.0:
		_log_timer = 0.0
		var grav := Input.get_gravity()
		print("[Station2IMU] raw gyro=(%.3f,%.3f,%.3f) grav=(%.2f,%.2f,%.2f) orient=%s" % [
			gyro.x, gyro.y, gyro.z,
			grav.x, grav.y, grav.z,
			orientation.get_euler()
		])


func recenter() -> void:
	orientation = Quaternion.IDENTITY
	_start_calibration()
	imu_recentered.emit()


func is_calibrated() -> bool:
	return _calibrated or _use_xr


func _shortest_arc(from: Vector3, to: Vector3) -> Quaternion:
	var cross := from.cross(to)
	var dot := from.dot(to)
	var sq_len := cross.length_squared()

	if sq_len < 0.00001:
		if dot > 0:
			return Quaternion.IDENTITY
		else:
			var perp: Vector3
			if abs(from.x) < 0.999:
				perp = Vector3.RIGHT
			else:
				perp = Vector3.UP
			perp = (perp - from * from.dot(perp)).normalized()
			return Quaternion(perp, PI)
	else:
		var angle := atan2(sqrt(sq_len), dot)
		return Quaternion(cross.normalized(), angle)
