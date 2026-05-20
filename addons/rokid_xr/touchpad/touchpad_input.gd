extends Node
## 全局触控板/控制器输入捕获（Autoload）
## 参考 Unity SDK: Station 2 走 Mouse 模式，D-pad 用 KEY 事件

const X_MOVE_SCALE: float = 0.14
const Y_MOVE_SCALE: float = 0.7
const DPAD_SPEED: float = 3.0

signal touchpad_moved(delta: Vector2)
signal touchpad_pressed()
signal touchpad_released()
signal touchpad_module_activated()
signal touchpad_module_released()

var _is_touching: bool = false
var _is_active: bool = false
var _use_mouse_mode: bool = false
var _is_station2: bool = false

# D-pad 状态
var _dpad_hold_time: float = 0.0
var _dpad_vec: Vector2 = Vector2.ZERO

# 调试
var _event_count: int = 0
var _last_event_type: String = "none"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_detect_device()


func _detect_device() -> void:
	var model := OS.get_model_name()
	_is_station2 = "RG-stationPro" in model or "RG-stationXR2" in model
	print("[TouchpadInput] model=%s station2=%s" % [model, _is_station2])


func _input(event: InputEvent) -> void:
	if not _is_active:
		return

	_event_count += 1

	# ★ 每 10 个事件打印类型，诊断输入来源
	if _event_count <= 20 or _event_count % 30 == 0:
		print("[TouchpadInput] evt#%d type=%s" % [_event_count, event.as_text().substr(0, 80)])

	# 1. 触摸事件
	if _handle_touch(event):
		return
	# 2. 鼠标事件
	if _handle_mouse(event):
		return
	# 3. 按键事件（Station 2 D-pad → KEY）
	if _handle_key(event):
		return
	# 4. 游戏手柄
	if _is_station2:
		_handle_gamepad(event)


func _handle_touch(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			_is_touching = true
			touchpad_pressed.emit()
			print("[TouchpadInput] TOUCH DN")
		else:
			_is_touching = false
			touchpad_released.emit()
			print("[TouchpadInput] TOUCH UP")
		return true

	if event is InputEventScreenDrag and _is_touching:
		var de := event as InputEventScreenDrag
		_emit_moved(de.relative)
		return true

	return false


func _handle_mouse(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var me := event as InputEventMouseButton
		if me.button_index == MOUSE_BUTTON_LEFT:
			if me.pressed:
				_is_touching = true
				touchpad_pressed.emit()
				print("[TouchpadInput] MOUSE DN")
			else:
				_is_touching = false
				touchpad_released.emit()
				print("[TouchpadInput] MOUSE UP")
			return true

	# 桌面模式：鼠标移动即可旋转（不要求按下）
	if event is InputEventMouseMotion and not _is_station2:
		var me := event as InputEventMouseMotion
		_emit_moved(me.relative)
		return true

	# Station 2 鼠标移动只在 _is_touching 时生效
	if event is InputEventMouseMotion and _is_touching:
		var me := event as InputEventMouseMotion
		_emit_moved(me.relative)
		return true

	return false


func _handle_key(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false

	var ke := event as InputEventKey
	if not ke.pressed or ke.echo:
		return false

	var dpad: Vector2 = Vector2.ZERO
	match ke.keycode:
		KEY_UP, KEY_W:
			dpad = Vector2(0, 1)
		KEY_DOWN, KEY_S:
			dpad = Vector2(0, -1)
		KEY_LEFT, KEY_A:
			dpad = Vector2(-1, 0)
		KEY_RIGHT, KEY_D:
			dpad = Vector2(1, 0)
		KEY_ENTER, KEY_SPACE:
			_is_touching = true
			touchpad_pressed.emit()
			print("[TouchpadInput] KEY OK")
			return true
		_:
			return false

	if dpad != Vector2.ZERO:
		_dpad_vec = dpad
		_is_touching = true
		touchpad_pressed.emit()
		print("[TouchpadInput] KEY D-pad %s" % dpad)
		return true

	return false


func _handle_gamepad(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		var old := _dpad_vec
		match jm.axis:
			JOY_AXIS_LEFT_X: _dpad_vec.x = jm.axis_value
			JOY_AXIS_LEFT_Y: _dpad_vec.y = -jm.axis_value
			JOY_AXIS_RIGHT_X: _dpad_vec.x = jm.axis_value
			JOY_AXIS_RIGHT_Y: _dpad_vec.y = -jm.axis_value


	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.button_index == JOY_BUTTON_A or jb.button_index == 0:
			if jb.pressed:
				_is_touching = true
				touchpad_pressed.emit()
				print("[TouchpadInput] JOYPAD A")
			else:
				_is_touching = false
				touchpad_released.emit()
				print("[TouchpadInput] JOYPAD A UP")


func _process(delta: float) -> void:
	# 对所有模式：有 _dpad_vec 且 _is_touching 时持续移动
	if _is_touching and _dpad_vec != Vector2.ZERO:
		_dpad_hold_time += delta
		var speed := DPAD_SPEED
		if _dpad_hold_time > 1.1:
			speed *= 3.0
		_emit_moved(_dpad_vec * speed)
	elif not _is_touching:
		_dpad_hold_time = 0.0
		_dpad_vec = Vector2.ZERO


func _emit_moved(raw_delta: Vector2) -> void:
	var scaled_delta := Vector2(
		raw_delta.x * X_MOVE_SCALE,
		raw_delta.y * -Y_MOVE_SCALE
	)
	touchpad_moved.emit(scaled_delta)


func activate_module(use_mouse: bool = false) -> void:
	_use_mouse_mode = use_mouse or _is_station2
	_is_active = true
	_is_touching = false
	_event_count = 0
	_dpad_hold_time = 0.0
	_dpad_vec = Vector2.ZERO
	touchpad_module_activated.emit()
	print("[TouchpadInput] ACTIVATED mode=%s station2=%s" % [
		"mouse" if _use_mouse_mode else "touch", _is_station2
	])


func release_module() -> void:
	_is_active = false
	_is_touching = false
	touchpad_module_released.emit()
	print("[TouchpadInput] DEACTIVATED")


func is_active() -> bool:
	return _is_active
