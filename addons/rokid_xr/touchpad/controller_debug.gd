extends XRController3D
## 调试脚本：直接挂在 RightHandController 上，打印所有输入

var _log_timer: float = 0.0
var _action_names := ["primary", "primary_click", "primary_touch",
	"trigger", "trigger_click", "grip", "grip_click",
	"menu_button", "select_button", "ax_button", "by_button"]

func _ready():
	print("[ControllerDebug] READY: tracker=%s controller=%s" % [tracker, get_controller_name()])

	button_pressed.connect(func(action: String):
		print("[ControllerDebug] SIGNAL button_pressed: '%s'" % action))
	button_released.connect(func(action: String):
		print("[ControllerDebug] SIGNAL button_released: '%s'" % action))
	input_vector2_changed.connect(func(action: String, val: Vector2):
		if val.length() > 0.01:
			print("[ControllerDebug] SIGNAL input_vector2_changed: '%s' = %s" % [action, val]))
	input_float_changed.connect(func(action: String, val: float):
		print("[ControllerDebug] SIGNAL input_float_changed: '%s' = %.4f" % [action, val]))

func _process(_delta):
	_log_timer += _delta
	if _log_timer < 3.0:
		return
	_log_timer = 0.0

	var parts: Array[String] = ["controller=%s tracker=%s" % [get_controller_name(), tracker]]

	for name in _action_names:
		var v2: Vector2 = get_vector2(name)
		if v2.length() > 0.01:
			parts.append("%s=V2(%s)" % [name, v2])

	for name in _action_names:
		if is_button_pressed(name):
			parts.append("%s=BTN" % name)

	for name in _action_names:
		var f: float = get_float(name)
		if absf(f) > 0.01:
			parts.append("%s=F%.4f" % [name, f])

	print("[ControllerDebug] ", " ".join(parts))
