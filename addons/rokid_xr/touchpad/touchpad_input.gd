extends Node
## 全局触控板/控制器输入捕获（Autoload）
## 参考 Rokid Unity SDK:
##   - Station 2 (RG-stationPro/stationXR2) 强制 Mouse 模式
##   - NormalInput 覆写: JoystickButton0 → mouse click
##   - D-pad → mouse movement
##   - 触摸屏 → touch/mouse delta

const X_MOVE_SCALE: float = 0.14
const Y_MOVE_SCALE: float = 0.7

# D-pad 移动速度（参考 Unity ButtonMouseEventInput.DefaultSpeedScale）
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
var _debug_counter: int = 0

# D-pad 长按加速
var _dpad_hold_time: float = 0.0
var _dpad_axis: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_detect_device()


func _detect_device() -> void:
	var model := OS.get_model_name()
	# Station 2 检测（参考 Unity RKVirtualController.Change）
	_is_station2 = "RG-stationPro" in model or "RG-stationXR2" in model
	print("[TouchpadInput] Device model=%s station2=%s" % [model, _is_station2])


func _input(event: InputEvent) -> void:
	if not _is_active:
		return

	_debug_counter += 1
	if _debug_counter % 120 == 0:
		print("[TouchpadInput] alive events=%d touching=%s station2=%s" % [
			_debug_counter, _is_touching, _is_station2
		])

	# 同时处理所有输入源，不互斥
	if _handle_touch(event):
		return
	if _handle_mouse(event):
		return
	if _is_station2:
		_handle_gamepad(event)


func _handle_touch(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			_is_touching = true
			touchpad_pressed.emit()
		else:
			_is_touching = false
			touchpad_released.emit()
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
			else:
				_is_touching = false
				touchpad_released.emit()
			return true

	if event is InputEventMouseMotion and _is_touching:
		var me := event as InputEventMouseMotion
		_emit_moved(me.relative)
		return true

	return false


func _handle_gamepad(event: InputEvent) -> void:
	# Station 2 D-pad → mouse movement（参考 ButtonMouseEventInput）
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		var old_axis := _dpad_axis
		match jm.axis:
			JOY_AXIS_LEFT_X: _dpad_axis.x = jm.axis_value
			JOY_AXIS_LEFT_Y: _dpad_axis.y = jm.axis_value
			JOY_AXIS_RIGHT_X: _dpad_axis.x = jm.axis_value
			JOY_AXIS_RIGHT_Y: _dpad_axis.y = jm.axis_value

		# 从 0 开始移动时触发按下
		if old_axis == Vector2.ZERO and _dpad_axis != Vector2.ZERO:
			_is_touching = true
			touchpad_pressed.emit()
		elif old_axis != Vector2.ZERO and _dpad_axis == Vector2.ZERO:
			_is_touching = false
			touchpad_released.emit()

	# Station 2 按钮 → click（参考 NormalInput: JoystickButton0 → mouse）
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		# JoystickButton0 = OK 按钮
		if jb.button_index == JOY_BUTTON_A or jb.button_index == 0:
			if jb.pressed:
				touchpad_pressed.emit()
			else:
				touchpad_released.emit()


func _process(delta: float) -> void:
	# D-pad 持续移动（参考 Unity ButtonMouseEventInput 的长按加速）
	if _is_station2 and _is_touching and _dpad_axis != Vector2.ZERO:
		_dpad_hold_time += delta
		var speed := DPAD_SPEED
		if _dpad_hold_time > 1.1:  # 长按加速
			speed *= 3.0
		var dpad_delta := _dpad_axis * speed
		_emit_moved(dpad_delta)
	elif not _is_touching:
		_dpad_hold_time = 0.0


func _emit_moved(raw_delta: Vector2) -> void:
	var scaled_delta := Vector2(
		raw_delta.x * X_MOVE_SCALE,
		raw_delta.y * -Y_MOVE_SCALE
	)
	touchpad_moved.emit(scaled_delta)


func activate_module(use_mouse: bool = false) -> void:
	# Station 2 强制 Mouse 模式（参考 Unity RKVirtualController.Change）
	_use_mouse_mode = use_mouse or _is_station2
	_is_active = true
	_is_touching = false
	_debug_counter = 0
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
