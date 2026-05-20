extends Node3D
## 主场景初始化 — 激活触控板输入模块


func _ready() -> void:
	# 根据平台选择输入模式
	var is_android := OS.get_name() == "Android"
	var use_mouse_mode := not is_android

	# 激活触控板输入
	if TouchpadInput:
		TouchpadInput.activate_module(use_mouse_mode)
		print_rich("[color=cyan]TouchpadInput activated (mouse_mode=%s)[/color]" % use_mouse_mode)

	# 初始化 OpenXR（如果在 XR 模式下运行）
	_initialize_xr()


func _initialize_xr() -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print_rich("[color=cyan]OpenXR initialized successfully[/color]")
		var vp := get_viewport()
		vp.use_xr = true


func _input(event: InputEvent) -> void:
	# 按空格键切换触控板激活状态（用于桌面调试）
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_SPACE and key_event.pressed and not key_event.echo:
			if TouchpadInput.is_active():
				TouchpadInput.release_module()
				print_rich("[color=yellow]TouchpadInput deactivated[/color]")
			else:
				TouchpadInput.activate_module(true)
				print_rich("[color=cyan]TouchpadInput activated[/color]")
