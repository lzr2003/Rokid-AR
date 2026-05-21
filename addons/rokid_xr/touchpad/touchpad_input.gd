extends Node
## 全局触控板/控制器输入捕获（Autoload）
## 双重兼容 + Station 2 XR tracker 扫描

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

var _dpad_hold_time: float = 0.0
var _dpad_vec: Vector2 = Vector2.ZERO
var _event_count: int = 0
var _last_event_type: String = "none"

var _joy_log_timer: float = 0.0
var _xr_log_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_detect_device()


func _detect_device() -> void:
	var model := OS.get_model_name()
	_is_station2 = "RG-station" in model
	print("[TouchpadInput] model=%s station2=%s" % [model, _is_station2])

	var joypads := Input.get_connected_joypads()
	print("[TouchpadInput] joypads: %s" % str(joypads))
	for jp in joypads:
		print("[TouchpadInput] joypad[%d] name=%s" % [jp, Input.get_joy_name(jp)])

	_scan_xr_trackers()


func _scan_xr_trackers() -> void:
	var tracker_names: Array[String] = ["head", "left", "right",
		"/user/hand/left", "/user/hand/right", "/user/head"]
	for name in tracker_names:
		var tracker: XRPositionalTracker = XRServer.get_tracker(name)
		if tracker == null:
			continue
		var found: String = ""
		# 尝试已知的 XR 控制器输入名
		for pn in ["trigger", "trigger_click", "trigger_touch",
			"grip", "grip_click", "grip_force",
			"primary", "primary_click", "primary_touch",
			"menu_button", "select_button",
			"ax_button", "by_button",
			"trackpad", "trackpad_click", "trackpad_touch",
			"thumbstick", "thumbstick_click"]:
			var v = tracker.get_input(pn)
			if v != null and v != 0.0 and v != false:
				found += pn + " "
		print("[TouchpadInput] XR '%s': %s" % [name, found if found != "" else "no inputs"])


func _input(event: InputEvent) -> void:
	if not _is_active:
		return

	_event_count += 1
	if _event_count <= 20 or _event_count % 30 == 0:
		print("[TouchpadInput] evt#%d type=%s" % [_event_count, event.as_text().substr(0, 80)])

	if _handle_touch(event):
		return
	if _handle_mouse(event):
		return
	if _handle_key(event):
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
	if event is InputEventMouseMotion and not _is_station2:
		var me := event as InputEventMouseMotion
		_emit_moved(me.relative)
		return true
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
		KEY_UP, KEY_W:   dpad = Vector2(0, 1)
		KEY_DOWN, KEY_S: dpad = Vector2(0, -1)
		KEY_LEFT, KEY_A:  dpad = Vector2(-1, 0)
		KEY_RIGHT, KEY_D: dpad = Vector2(1, 0)
		KEY_ENTER, KEY_SPACE, KEY_MENU, KEY_BACK, KEY_HOME:
			_is_touching = true
			touchpad_pressed.emit()
			print("[TouchpadInput] KEY press keycode=%d" % ke.keycode)
			return true
		_: return false
	if dpad != Vector2.ZERO:
		_dpad_vec = dpad
		_is_touching = true
		touchpad_pressed.emit()
		return true
	return false


func _handle_gamepad(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
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
			else:
				_is_touching = false
				touchpad_released.emit()


func _process(delta: float) -> void:
	if _is_station2:
		if OS.get_name() == "Android":
			_poll_touch_file()
		_poll_xr_tracker(delta)
		_poll_joypad(delta)
	if _is_touching and _dpad_vec != Vector2.ZERO:
		_dpad_hold_time += delta
		var speed := DPAD_SPEED
		if _dpad_hold_time > 1.1:
			speed *= 3.0
		_emit_moved(_dpad_vec * speed)
	elif not _is_touching:
		_dpad_hold_time = 0.0
		_dpad_vec = Vector2.ZERO


func _poll_touch_file() -> void:
	if not FileAccess.file_exists("/data/local/tmp/rokid_touch_state.txt"):
		return
	var f := FileAccess.open("/data/local/tmp/rokid_touch_state.txt", FileAccess.READ)
	if not f:
		return
	var line := f.get_as_text().strip_edges()
	f.close()
	if line.is_empty():
		return
	var parts := line.split(" ")
	if parts.size() < 4:
		return
	var dx: float = float(parts[0])
	var dy: float = float(parts[1])
	var state: int = int(parts[2])
	var click: int = int(parts[3])

	var delta := Vector2(dx, dy)
	if abs(delta.x) > 0.5 or abs(delta.y) > 0.5:
		_emit_moved(delta * 0.14)

	if state == 1 and not _is_touching:
		_is_touching = true
		touchpad_pressed.emit()
	elif state == 0 and _is_touching:
		_is_touching = false
		touchpad_released.emit()

	if click == 1:
		if not _is_touching:
			_is_touching = true
			touchpad_pressed.emit()


func _poll_xr_tracker(delta: float) -> void:
	_xr_log_timer += delta
	for name in ["right", "/user/hand/right", "left", "/user/hand/left"]:
		var tracker: XRPositionalTracker = XRServer.get_tracker(name)
		if tracker == null:
			continue
		for pn in ["trigger_click", "primary_click", "trackpad_click",
			"ax_button", "menu_button", "grip_click"]:
			var val = tracker.get_input(pn)
			if val:
				if _xr_log_timer > 2.0:
					print("[TouchpadInput] XR btn %s/%s" % [name, pn])
				if not _is_touching:
					_is_touching = true
					touchpad_pressed.emit()
				return
		if _is_touching:
			_is_touching = false
			touchpad_released.emit()


func _poll_joypad(delta: float) -> void:
	_joy_log_timer += delta
	var joypads := Input.get_connected_joypads()
	if joypads.is_empty():
		return
	var dev := joypads[0]
	for btn in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y,
			JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
			0, 1, 2, 3]:
		if Input.is_joy_button_pressed(dev, btn):
			if not _is_touching:
				_is_touching = true
				touchpad_pressed.emit()
			if _joy_log_timer > 2.0:
				print("[TouchpadInput] JOY btn %d" % btn)
			return


func _emit_moved(raw_delta: Vector2) -> void:
	touchpad_moved.emit(Vector2(raw_delta.x * X_MOVE_SCALE, raw_delta.y * -Y_MOVE_SCALE))


func activate_module(use_mouse: bool = false) -> void:
	_use_mouse_mode = use_mouse or _is_station2
	_is_active = true
	_is_touching = false
	_event_count = 0
	_dpad_hold_time = 0.0
	_dpad_vec = Vector2.ZERO
	touchpad_module_activated.emit()
	print("[TouchpadInput] ACTIVATED mode=%s station2=%s" % ["mouse" if _use_mouse_mode else "touch", _is_station2])


func release_module() -> void:
	_is_active = false
	_is_touching = false
	touchpad_module_released.emit()
	print("[TouchpadInput] DEACTIVATED")


func is_active() -> bool:
	return _is_active
