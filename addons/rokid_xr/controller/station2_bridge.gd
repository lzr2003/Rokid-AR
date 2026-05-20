extends Node
## Station 2 原生传感器桥接（GDScript 侧）
## 直接调用 Android 原生 SensorManager，绕过 OpenXR

var _plugin: Object = null
var _available: bool = false
var _last_log: float = 0.0

# 暴露的数据
var quaternion: Quaternion = Quaternion.IDENTITY
var key_state: int = 0
var key_down: int = 0
var key_up: int = 0


func _ready() -> void:
	_init_plugin()


func _init_plugin() -> void:
	if OS.get_name() != "Android":
		print("[Station2Bridge] Not Android, plugin disabled")
		return

	_plugin = Engine.get_singleton("Station2Bridge")
	if _plugin == null:
		print("[Station2Bridge] Plugin singleton not found!")
		return

	_available = true
	print("[Station2Bridge] Plugin loaded successfully")


func _process(delta: float) -> void:
	if not _available:
		return

	# 读取传感器四元数
	var q := _plugin.call("getQuaternion")
	if q != null and q is Array and q.size() >= 4:
		# Android TYPE_ROTATION_VECTOR: [x, y, z, w]
		# Unity SDK: data[2] = -data[2]
		quaternion = Quaternion(q[0], q[1], -q[2], q[3])

	# 读取按键状态
	key_state = _plugin.call("getKeyState")
	key_down = _plugin.call("consumeKeyDown")
	key_up = _plugin.call("consumeKeyUp")

	# 日志
	_last_log += delta
	if _last_log > 2.0:
		_last_log = 0.0
		print("[Station2Bridge] quat=(%.2f,%.2f,%.2f,%.2f) keys=%d dn=%d up=%d" % [
			quaternion.x, quaternion.y, quaternion.z, quaternion.w,
			key_state, key_down, key_up
		])


func is_available() -> bool:
	return _available


func has_sensor_data() -> bool:
	if not _available:
		return false
	return _plugin.call("hasSensorData")
