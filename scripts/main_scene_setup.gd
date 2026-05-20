extends Node3D
## 主场景初始化 — 激活触控板输入模块 + 调试 HUD

var _debug_label: Label
var _touchpad_ray_pose: TouchPadRayPose
var _ray_interactor: RayInteractor


func _ready() -> void:
	# 根据平台选择输入模式
	var is_android := OS.get_name() == "Android"
	var use_mouse_mode := not is_android

	if TouchpadInput:
		TouchpadInput.activate_module(use_mouse_mode)
		print_rich("[color=cyan]TouchpadInput activated (mouse_mode=%s)[/color]" % use_mouse_mode)

	_initialize_xr()
	_setup_debug_hud()
	_find_references()


func _initialize_xr() -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print_rich("[color=cyan]OpenXR initialized successfully[/color]")
		var vp := get_viewport()
		vp.use_xr = true


func _setup_debug_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "DebugCanvas"
	add_child(canvas)

	_debug_label = Label.new()
	_debug_label.name = "DebugLabel"
	_debug_label.position = Vector2(20, 20)
	_debug_label.size = Vector2(500, 300)
	_debug_label.add_theme_color_override("font_color", Color(0, 1, 0, 0.9))
	_debug_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(_debug_label)


func _find_references() -> void:
	var xr_rig := find_child("XRRig", true, false)
	if xr_rig:
		_touchpad_ray_pose = xr_rig.find_child("TouchPadRayPose", true, false)
		_ray_interactor = xr_rig.find_child("RayInteractor", true, false)


func _process(_delta: float) -> void:
	if _debug_label == null:
		return

	var text := "=== Rokid XR Debug HUD ===\n"

	if _touchpad_ray_pose:
		var tpr := _touchpad_ray_pose
		text += "\n[TouchPadRayPose]"
		text += "\n  yaw:  %.2f°" % tpr.yaw
		text += "\n  pitch: %.2f°" % tpr.pitch
		text += "\n  rotation: %s" % tpr.rotation
		text += "\n  global_forward: %s" % (-tpr.global_transform.basis.z)

	if _ray_interactor:
		var ri := _ray_interactor
		text += "\n\n[RayInteractor]"
		text += "\n  state: %d" % ri.state
		text += "\n  ray_origin:  %.2f, %.2f, %.2f" % [ri.ray_origin.x, ri.ray_origin.y, ri.ray_origin.z]
		text += "\n  ray_forward: %.3f, %.3f, %.3f" % [ri.ray_forward.x, ri.ray_forward.y, ri.ray_forward.z]
		text += "\n  ray_end:     %.2f, %.2f, %.2f" % [ri.ray_end.x, ri.ray_end.y, ri.ray_end.z]
		if ri.collision_info.hit:
			text += "\n  hit: true @ %.2f, %.2f, %.2f" % [ri.collision_info.point.x, ri.collision_info.point.y, ri.collision_info.point.z]
		else:
			text += "\n  hit: false"

	text += "\n\n[Input]"
	text += "\n  activated: %s" % TouchpadInput.is_active()
	text += "\n  mode: %s" % ("Mouse" if not OS.get_name() == "Android" else "Touch")

	_debug_label.text = text


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_SPACE and key_event.pressed and not key_event.echo:
			if TouchpadInput.is_active():
				TouchpadInput.release_module()
				print_rich("[color=yellow]TouchpadInput deactivated[/color]")
			else:
				TouchpadInput.activate_module(true)
				print_rich("[color=cyan]TouchpadInput activated[/color]")
