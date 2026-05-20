extends Node
## Station 2 控制器 IMU 姿态读取（Autoload）
## 参考 Unity SDK ThreeDofEventInput:
##   - getPhonePose() 读取 TYPE_ROTATION_VECTOR 四元数
##   - data[2] = -data[2] 坐标系转换
## Godot 中用陀螺仪角速度 + 重力向量做互补滤波

# 互补滤波系数（越小越平滑，越大响应越快但噪声多）
const FILTER_ALPHA: float = 0.02

# 信号
signal orientation_changed(quat: Quaternion)
signal imu_recentered()

# 当前姿态（四元数）
var orientation: Quaternion = Quaternion.IDENTITY

# 内部状态
var _initial_yaw: float = 0.0
var _gyro_bias: Vector3 = Vector3.ZERO
var _calibrated: bool = false
var _sample_count: int = 0
var _samples: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 陀螺仪需要校准零点
	_start_calibration()


func _start_calibration() -> void:
	_calibrated = false
	_sample_count = 0
	_samples.clear()
	print("[Station2IMU] Calibrating gyroscope...")


func _process(delta: float) -> void:
	var gyro: Vector3 = Input.get_gyroscope()

	# 校准：采集前 60 帧的陀螺仪数据取均值作为零偏
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

	# 去除零偏
	gyro -= _gyro_bias

	# 如果有数值，进行姿态更新
	if gyro.length_squared() > 0.0001 or true:
		_update_orientation(gyro, delta)


func _update_orientation(gyro: Vector3, delta: float) -> void:
	# 1. 陀螺仪积分：角速度 → 增量四元数
	var angle := gyro.length() * delta
	var axis: Vector3
	if angle > 0.0001:
		axis = gyro.normalized()
	else:
		axis = Vector3.FORWARD
	var delta_q := Quaternion(axis, angle)
	var gyro_orientation := orientation * delta_q

	# 2. 重力向量校正 pitch/roll（绝对参考）
	var gravity: Vector3 = Input.get_gravity()
	if gravity.length_squared() > 0.1:
		gravity = gravity.normalized()

		# 用重力计算 pitch/roll 对应的参考方向
		var gyro_down: Vector3 = gyro_orientation * Vector3.DOWN
		var correction_q: Quaternion = _shortest_arc(gyro_down, gravity)

		# 互补滤波：陀螺仪积分 + 重力校正
		orientation = gyro_orientation.slerp(correction_q * gyro_orientation, FILTER_ALPHA)
	else:
		# 重力数据不可用，纯陀螺仪积分
		orientation = gyro_orientation

	orientation = orientation.normalized()
	orientation_changed.emit(orientation)


func recenter() -> void:
	## 重置 yaw（参考 Unity ResetImuAxisY）
	orientation = Quaternion.IDENTITY
	_start_calibration()
	imu_recentered.emit()
	print("[Station2IMU] Recentered")


func is_calibrated() -> bool:
	return _calibrated


# 最短弧旋转（两个方向之间的最小旋转四元数）
func _shortest_arc(from: Vector3, to: Vector3) -> Quaternion:
	var cross := from.cross(to)
	var dot := from.dot(to)
	var sq_len := cross.length_squared()

	if sq_len < 0.00001:
		if dot > 0:
			return Quaternion.IDENTITY
		else:
			# 180度旋转
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
