@tool
extends EditorPlugin
## Rokid XR Interaction 插件入口
## 在编辑器启动时激活触控板输入模块

const TOUCHPAD_INPUT_PATH := "res://addons/rokid_xr/touchpad/touchpad_input.gd"
const REGISTRY_PATH := "res://addons/rokid_xr/interaction/interactable_registry.gd"


func _enter_tree() -> void:
	_add_autoload("TouchpadInput", TOUCHPAD_INPUT_PATH)
	_add_autoload("InteractableRegistry", REGISTRY_PATH)
	print_rich("[color=green]Rokid XR Interaction plugin loaded.[/color]")


func _exit_tree() -> void:
	_remove_autoload("TouchpadInput")
	_remove_autoload("InteractableRegistry")
	print_rich("[color=yellow]Rokid XR Interaction plugin unloaded.[/color]")


func _add_autoload(name: String, path: String) -> void:
	if not ProjectSettings.has_setting("autoload/" + name):
		add_autoload_singleton(name, path)
	else:
		var existing := ProjectSettings.get_setting("autoload/" + name)
		if existing != "*" + path:
			remove_autoload_singleton(name)
			add_autoload_singleton(name, path)


func _remove_autoload(name: String) -> void:
	if ProjectSettings.has_setting("autoload/" + name):
		remove_autoload_singleton(name)


func _has_main_screen() -> bool:
	return false
