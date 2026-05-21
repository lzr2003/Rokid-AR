extends Node
## Station 2 控制器 IMU 姿态读取（Autoload）
## 通过 RokidXR.get_phone_pose() 读取控制器姿态

signal orientation_changed(quat: Quaternion)

var orientation: Quaternion = Quaternion.IDENTITY

var _log_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _has_rokid_xr() -> bool:
	return Engine.has_singleton("RokidXR") and Engine.get_singleton("RokidXR").is_ready()


func _process(delta: float) -> void:
	if _has_rokid_xr():
		var pose: Dictionary = Engine.get_singleton("RokidXR").get_phone_pose()
		if not pose.is_empty() and pose.has("orientation"):
			var q: Quaternion = pose["orientation"]
			orientation = Quaternion(q.x, q.y, -q.z, q.w)
			orientation_changed.emit(orientation)
			_log_rokid(delta)
	else:
		print("without rokid xr")



func _log_rokid(delta: float) -> void:
	_log_timer += delta
	if _log_timer > 2.0:
		_log_timer = 0.0
		print("[Station2IMU] phone_pose orient=(%.2f,%.2f,%.2f,%.2f)" % [
			orientation.x, orientation.y, orientation.z, orientation.w
		])
