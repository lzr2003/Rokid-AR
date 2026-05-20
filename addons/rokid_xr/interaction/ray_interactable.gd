extends Node3D
## 可被射线交互的目标节点
## 匹配 Unity SDK 的 RayInteractable
class_name RayInteractable

const InteractionEnums = preload("res://addons/rokid_xr/interaction/interactor_state.gd")

# 命中检测表面
@export var surface: PlaneSurface:
	set(val):
		surface = val
		update_configuration_warnings()

# 选中时使用的表面（可选，默认使用 surface）
@export var select_surface: PlaneSurface:
	set(val):
		select_surface = val
		update_configuration_warnings()

# 容量限制（-1 = 无限）
@export var max_interactors: int = -1
@export var max_selecting_interactors: int = -1

# 距离相同时的优先级
@export var tiebreaker_score: int = 0

# 是否启用
@export var enabled: bool = true

# 交互器集合
var hover_interactors: Array = []
var select_interactors: Array = []

# 信号
signal hover_entered(interactor: RayInteractor)
signal hover_exited(interactor: RayInteractor)
signal selected(interactor: RayInteractor)
signal unselected(interactor: RayInteractor)
signal state_changed(old_state: int, new_state: int)

var _previous_state: int = 0


func _ready() -> void:
	if surface == null:
		surface = PlaneSurface.new()
	if select_surface == null:
		select_surface = surface
	_previous_state = current_state


func _enter_tree() -> void:
	InteractableRegistry.register(self)


func _exit_tree() -> void:
	InteractableRegistry.unregister(self)
	for ia in hover_interactors.duplicate():
		ia.interactable_changes_update(self)
	for ia in select_interactors.duplicate():
		ia.interactable_changes_update(self)


func _process(_delta: float) -> void:
	var new_state: int = current_state
	if new_state != _previous_state:
		state_changed.emit(_previous_state, new_state)
		_previous_state = new_state


var current_state: int:
	get:
		if not enabled:
			return InteractionEnums.InteractableState.DISABLED
		if select_interactors.size() > 0:
			return InteractionEnums.InteractableState.SELECT
		if hover_interactors.size() > 0:
			return InteractionEnums.InteractableState.HOVER
		return InteractionEnums.InteractableState.NORMAL


func raycast(ray_origin: Vector3, ray_direction: Vector3, max_dist: float, use_select_surface: bool = false) -> Dictionary:
	var srf: PlaneSurface = select_surface if use_select_surface else surface
	if srf == null:
		return {"hit": false, "point": Vector3.ZERO, "normal": Vector3.ZERO, "distance": 0.0}

	var local_origin: Vector3 = global_transform.affine_inverse() * ray_origin
	var local_direction: Vector3 = global_transform.affine_inverse().basis * ray_direction

	var hit: Dictionary = srf.intersect_ray(local_origin, local_direction, max_dist)
	if hit.hit:
		hit.point = global_transform * hit.point
		hit.normal = global_transform.basis * hit.normal
	return hit


func can_be_selected_by(interactor: RayInteractor) -> bool:
	if not enabled:
		return false
	if max_selecting_interactors >= 0 and select_interactors.size() >= max_selecting_interactors:
		if interactor not in select_interactors:
			return false
	if max_interactors >= 0 and hover_interactors.size() >= max_interactors:
		if interactor not in hover_interactors:
			return false
	return true


func is_enabled() -> bool:
	return enabled


# --- 内部方法，由 RayInteractor 调用 ---

func add_hover_interactor(interactor: RayInteractor) -> void:
	if interactor not in hover_interactors:
		hover_interactors.append(interactor)
		hover_entered.emit(interactor)


func remove_hover_interactor(interactor: RayInteractor) -> void:
	var idx: int = hover_interactors.find(interactor)
	if idx >= 0:
		hover_interactors.remove_at(idx)
		hover_exited.emit(interactor)


func add_select_interactor(interactor: RayInteractor) -> void:
	if interactor not in select_interactors:
		select_interactors.append(interactor)
		selected.emit(interactor)


func remove_select_interactor(interactor: RayInteractor) -> void:
	var idx: int = select_interactors.find(interactor)
	if idx >= 0:
		select_interactors.remove_at(idx)
		unselected.emit(interactor)


func remove_interactor_by_identifier(identifier: int) -> void:
	for ia in select_interactors.duplicate():
		if ia.get_identifier() == identifier:
			remove_select_interactor(ia)
			ia.interactable_changes_update(self)
	for ia in hover_interactors.duplicate():
		if ia.get_identifier() == identifier:
			remove_hover_interactor(ia)
			ia.interactable_changes_update(self)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = PackedStringArray()
	if surface == null:
		warnings.append("Surface is not set. Please assign a PlaneSurface resource.")
	return warnings
