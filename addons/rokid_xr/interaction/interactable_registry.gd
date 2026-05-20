extends Node
## 全局可交互对象注册表（Autoload）
## 匹配 Unity SDK 的 InteractableRegistry<TInteractor, TInteractable>

var _registry: Array = []  # Array[RayInteractable]


func register(interactable) -> void:
	if interactable not in _registry:
		_registry.append(interactable)


func unregister(interactable) -> void:
	var idx := _registry.find(interactable)
	if idx >= 0:
		_registry.remove_at(idx)


func get_all() -> Array:
	return _registry.duplicate()


func list(interactor) -> Array:
	## 返回该交互器可用的候选列表
	var result: Array = []
	for ia in _registry:
		if not is_instance_valid(ia):
			continue
		if not ia.is_enabled():
			continue
		if not interactor.can_interact_with(ia):
			continue
		if not ia.can_be_selected_by(interactor):
			continue
		result.append(ia)
	return result


func list_for_raycast(interactor, ray_origin: Vector3, ray_direction: Vector3, max_dist: float) -> Array:
	## 返回按距离排序的命中列表 [{interactable: RayInteractable, point: Vector3, normal: Vector3, distance: float}]
	var hits: Array = []
	for ia in _registry:
		if not is_instance_valid(ia):
			continue
		if not ia.is_enabled():
			continue
		if not interactor.can_interact_with(ia):
			continue
		if not ia.can_be_selected_by(interactor):
			continue
		var hit_info: Dictionary = ia.raycast(ray_origin, ray_direction, max_dist)
		if hit_info.hit:
			hit_info["interactable"] = ia
			hits.append(hit_info)

	hits.sort_custom(_sort_by_distance)
	return hits


func _sort_by_distance(a: Dictionary, b: Dictionary) -> bool:
	return a.distance < b.distance


func clear() -> void:
	_registry.clear()
