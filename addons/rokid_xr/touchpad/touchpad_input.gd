extends Node
## 全局触控板输入捕获（Autoload）
## 双重兼容：InputEventScreenTouch/Drag（触控板→触摸事件）+ InputEventMouse（鼠标模式/桌面编辑器）

# 缩放系数与 Unity SDK 保持一致
const X_MOVE_SCALE := 0.14
const Y_MOVE_SCALE := 0.7

# 信号
signal touchpad_moved(delta: Vector2)
signal touchpad_pressed()
signal touchpad_released()
signal touchpad_module_activated()
signal touchpad_module_released()

# 内部状态
var _is_touching := false
var _last_touch_position := Vector2.ZERO
var _is_active := false
var _use_mouse_mode := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if not _is_active:
		return

	if _use_mouse_mode:
		_handle_mouse_input(event)
	else:
		_handle_touch_input(event)


func _handle_touch_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_is_touching = true
			_last_touch_position = touch_event.position
			touchpad_pressed.emit()
		else:
			_is_touching = false
			touchpad_released.emit()

	elif event is InputEventScreenDrag and _is_touching:
		var drag_event := event as InputEventScreenDrag
		var raw_delta := drag_event.relative
		var scaled_delta := Vector2(
			raw_delta.x * X_MOVE_SCALE,
			raw_delta.y * -Y_MOVE_SCALE
		)
		touchpad_moved.emit(scaled_delta)


func _handle_mouse_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				touchpad_pressed.emit()
			else:
				touchpad_released.emit()

	elif event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var raw_delta := motion_event.relative
			var scaled_delta := Vector2(
				raw_delta.x * X_MOVE_SCALE,
				raw_delta.y * -Y_MOVE_SCALE
			)
			touchpad_moved.emit(scaled_delta)


func activate_module(use_mouse: bool = false) -> void:
	_use_mouse_mode = use_mouse
	_is_active = true
	_is_touching = false
	touchpad_module_activated.emit()


func release_module() -> void:
	_is_active = false
	_is_touching = false
	touchpad_module_released.emit()


func is_active() -> bool:
	return _is_active
