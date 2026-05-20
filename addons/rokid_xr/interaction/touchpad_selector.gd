extends Node
## 触摸点击 → Select/Unselect 转换器
## 订阅 TouchpadInput 的 pressed/released 信号，驱动 RayInteractor 的选择队列
class_name TouchPadSelector

@export var ray_interactor: RayInteractor


func _ready() -> void:
	if ray_interactor == null:
		ray_interactor = _find_ray_interactor()

	TouchpadInput.touchpad_pressed.connect(_on_pressed)
	TouchpadInput.touchpad_released.connect(_on_released)


func _find_ray_interactor() -> RayInteractor:
	var parent := get_parent()
	while parent:
		var found := _search_ray_interactor(parent)
		if found:
			return found
		parent = parent.get_parent()
	return null


func _search_ray_interactor(node: Node) -> RayInteractor:
	for child in node.get_children():
		if child is RayInteractor:
			return child
		var found := _search_ray_interactor(child)
		if found:
			return found
	return null


func _on_pressed() -> void:
	if ray_interactor:
		ray_interactor.handle_selected()


func _on_released() -> void:
	if ray_interactor:
		ray_interactor.handle_unselected()


func _exit_tree() -> void:
	if TouchpadInput.touchpad_pressed.is_connected(_on_pressed):
		TouchpadInput.touchpad_pressed.disconnect(_on_pressed)
	if TouchpadInput.touchpad_released.is_connected(_on_released):
		TouchpadInput.touchpad_released.disconnect(_on_released)
