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

# XRController3D 节点引用（从场景中查找，tracker = "right_hand"）
var _xr_controller: XRController3D = null
var _controller_scanned: bool = false
var _actions_log_timer: float = 0.0


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
	# 更全面的 tracker 路径扫描
	var tracker_paths: Array[String] = [
		"/user/hand/right", "/user/hand/right/input",
		"/user/hand/left", "/user/hand/left/input",
		"/user/head", "/user/head/input",
		"/interaction_profiles/htc_vive_controller",
		"/interaction_profiles/oculus_touch_controller",
	]
	for tp in tracker_paths:
		var tracker: XRPositionalTracker = XRServer.get_tracker(tp)
		if tracker == null:
			print("[XRScan] tracker '%s' = null" % tp)
			continue
		print("[XRScan] tracker '%s' FOUND: name='%s' type=%d hand=%d" % [tp, tracker.get_tracker_name(), tracker.get_tracker_type(), tracker.get_tracker_hand()])

	# 枚举所有已知输入名，包括模拟轴
	var input_names: Array[String] = [
		"trigger", "trigger_click", "trigger_touch", "trigger_value",
		"grip", "grip_click", "grip_force", "grip_value",
		"primary", "primary_click", "primary_touch",
		"secondary", "secondary_click", "secondary_touch",
		"menu_button", "select_button",
		"ax_button", "by_button",
		"trackpad", "trackpad_click", "trackpad_touch", "trackpad_x", "trackpad_y",
		"thumbstick", "thumbstick_click", "thumbstick_touch", "thumbstick_x", "thumbstick_y",
		"thumbrest", "thumbrest_touch",
		"squeeze", "squeeze_click", "squeeze_force",
	]
	for tp in ["/user/hand/right", "/user/hand/left"]:
		var tracker: XRPositionalTracker = XRServer.get_tracker(tp)
		if tracker == null:
			continue
		var found_inputs: String = ""
		for pn in input_names:
			var v = tracker.get_input(pn)
			if v != null and v != 0.0 and v != false:
				found_inputs += "%s=%.4f " % [pn, float(v) if typeof(v) in [TYPE_FLOAT, TYPE_INT] else (1.0 if v else 0.0)]
		if found_inputs != "":
			print("[XRScan] '%s' INPUTS: %s" % [tp, found_inputs])
		else:
			print("[XRScan] '%s' no inputs with non-zero value" % tp)


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
			_poll_openxr_actions(delta)
			_poll_rokid_touch()
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


func _poll_rokid_touch() -> void:
	var sok = _has_rokid_xr()
	if not sok:
		return
	var delta: Vector2 = Engine.get_singleton("RokidXR").get_touch_delta()
	if delta.length() > 0.5:
		_emit_moved(delta * 0.14)
	var state: int = Engine.get_singleton("RokidXR").get_touch_state()
	if state == 1 and not _is_touching:
		_is_touching = true
		touchpad_pressed.emit()
	elif state == 0 and _is_touching:
		_is_touching = false
		touchpad_released.emit()
	var click: bool = Engine.get_singleton("RokidXR").consume_touch_click()
	if click:
		if not _is_touching:
			_is_touching = true
			touchpad_pressed.emit()


func _has_rokid_xr() -> bool:
	return Engine.has_singleton("RokidXR") and Engine.get_singleton("RokidXR").is_ready()



func _poll_xr_tracker(delta: float) -> void:
	_xr_log_timer += delta
	var trackers_to_check: Array[String] = ["/user/hand/right", "/user/hand/left"]
	for tp in trackers_to_check:
		var tracker: XRPositionalTracker = XRServer.get_tracker(tp)
		if tracker == null:
			continue

		# 周期性打印所有非零输入（每 3 秒）
		if _xr_log_timer > 3.0:
			_xr_log_timer = 0.0
			var all_inputs: String = ""
			for pn in ["trigger", "trigger_click", "trigger_value",
				"grip", "grip_click",
				"primary", "primary_click",
				"trackpad", "trackpad_click", "trackpad_touch", "trackpad_x", "trackpad_y",
				"thumbstick", "thumbstick_click", "thumbstick_x", "thumbstick_y",
				"menu_button", "select_button", "ax_button", "by_button"]:
				var v = tracker.get_input(pn)
				if v != null and v != false:
					var fv: float = float(v) if typeof(v) in [TYPE_FLOAT, TYPE_INT] else (1.0 if v else 0.0)
					if absf(fv) > 0.01:
						all_inputs += "%s=%.4f " % [pn, fv]
			print("[TouchpadInput] XR '%s' [periodic]: %s" % [tp, all_inputs if all_inputs != "" else "ALL ZERO"])

		# 1. 检测 trackpad 滑动（模拟轴）
		var tpad_x: float = 0.0
		var tpad_y: float = 0.0
		var tx = tracker.get_input("trackpad_x")
		var ty = tracker.get_input("trackpad_y")
		if tx != null: tpad_x = float(tx)
		if ty != null: tpad_y = float(ty)
		if absf(tpad_x) > 0.01 or absf(tpad_y) > 0.01:
			_emit_moved(Vector2(tpad_x, tpad_y))

		# 2. 检测 thumbstick 滑动
		var ts_x: float = 0.0
		var ts_y: float = 0.0
		var sx = tracker.get_input("thumbstick_x")
		var sy = tracker.get_input("thumbstick_y")
		if sx != null: ts_x = float(sx)
		if sy != null: ts_y = float(sy)
		if absf(ts_x) > 0.01 or absf(ts_y) > 0.01:
			_emit_moved(Vector2(ts_x, ts_y))

		# 3. 检测按钮按下/释放
		var any_pressed: bool = false
		for pn in ["trigger_click", "primary_click", "trackpad_click",
			"thumbstick_click", "ax_button", "menu_button", "grip_click"]:
			if tracker.get_input(pn):
				any_pressed = true
				break
		if any_pressed:
			if not _is_touching:
				_is_touching = true
				print("[TouchpadInput] XR '%s' PRESSED" % tp)
				touchpad_pressed.emit()
		else:
			if _is_touching:
				_is_touching = false
				print("[TouchpadInput] XR '%s' RELEASED" % tp)
				touchpad_released.emit()


func _poll_openxr_actions(delta: float) -> void:
	_actions_log_timer += delta

	# 懒加载：从场景树中查找 XRController3D (tracker = "right_hand")
	if not _controller_scanned:
		_find_controller_node()

	if _xr_controller == null:
		return

	# 周期性日志（每 3 秒）
	if _actions_log_timer > 3.0:
		_actions_log_timer = 0.0
		var pos: Vector2 = _xr_controller.get_vector2("primary")
		var clicked: bool = _xr_controller.is_button_pressed("primary_click")
		var touched: bool = _xr_controller.is_button_pressed("primary_touch")
		print("[TouchpadInput] OpenXR Action: pos=%s click=%s touch=%s" % [pos, clicked, touched])

	# 读取 trackpad 位置
	var pos: Vector2 = _xr_controller.get_vector2("primary")
	if pos.length() > 0.01:
		_emit_moved(pos)

	# 读取按下/释放
	var clicked: bool = _xr_controller.is_button_pressed("primary_click")
	if clicked and not _is_touching:
		_is_touching = true
		print("[TouchpadInput] OpenXR Action PRESSED (primary_click)")
		touchpad_pressed.emit()
	elif not clicked and _is_touching:
		_is_touching = false
		print("[TouchpadInput] OpenXR Action RELEASED (primary_click)")
		touchpad_released.emit()

	# touch 检测（手指接触）
	var touched: bool = _xr_controller.is_button_pressed("primary_touch")
	if touched and not _is_touching:
		_is_touching = true
		print("[TouchpadInput] OpenXR Action TOUCH (primary_touch)")
		touchpad_pressed.emit()
	elif not touched and _is_touching:
		_is_touching = false
		print("[TouchpadInput] OpenXR Action UNTOUCH (primary_touch)")
		touchpad_released.emit()


func _find_controller_node() -> void:
	_controller_scanned = true
	var root := get_tree().root if get_tree() else null
	if root == null:
		return

	# 搜索场景树中 tracker == "right_hand" 的 XRController3D
	var to_visit: Array[Node] = [root]
	while not to_visit.is_empty():
		var node := to_visit.pop_back()
		if node is XRController3D:
			var ctrl: XRController3D = node as XRController3D
			if ctrl.tracker == "right_hand":
				_xr_controller = ctrl
				print("[TouchpadInput] XRController3D (right_hand) FOUND — '%s'" % ctrl.name)
				return
		for child in node.get_children():
			to_visit.push_back(child)

	print("[TouchpadInput] XRController3D (right_hand) NOT FOUND in scene tree")


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
