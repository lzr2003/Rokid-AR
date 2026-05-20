extends Resource
## 指针事件数据结构，匹配 Unity SDK 的 PointerEvent
class_name PointerEvent

var identifier: int = 0
var type: int = 0  # PointerEventType
var position: Vector3 = Vector3.ZERO
var rotation: Quaternion = Quaternion.IDENTITY
var data: Variant = null


func _init(p_id: int = 0, p_type: int = 0, p_pos: Vector3 = Vector3.ZERO, p_rot: Quaternion = Quaternion.IDENTITY, p_data: Variant = null) -> void:
	identifier = p_id
	type = p_type
	position = p_pos
	rotation = p_rot
	data = p_data
