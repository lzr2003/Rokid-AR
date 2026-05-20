extends Node3D
## 射线交互器 —— 核心状态机 + 射线检测
## 匹配 Unity SDK 的 RayInteractor + Interactor + PointerInteractor
class_name RayInteractor

const InteractionEnums = preload("res://addons/rokid_xr/interaction/interactor_state.gd")
const PointerEvent = preload("res://addons/rokid_xr/interaction/pointer_event.gd")

# --- 导出配置 ---
@export var max_ray_length: float = 5.0
@export var drag_threshold: float = 0.01
@export var click_time: float = 0.5
@export var raycast_mask: int = 0xFFFFFFFF
@export var no_hover_cursor_distance: float = 5.0
@export var max_iterations_per_frame: int = 3
@export var equal_distance_threshold: float = 0.001

# --- 运行时状态 ---
var state: int = InteractionEnums.InteractorState.NORMAL
var candidate: RayInteractable = null
var hovered: RayInteractable = null
var selected: RayInteractable = null

# 射线几何
var ray_origin: Vector3:
	get: return global_position
var ray_forward: Vector3:
	get: return -global_transform.basis.z
var ray_end: Vector3 = Vector3.ZERO
var ray: Dictionary:
	get: return {"origin": ray_origin, "direction": ray_forward}
var collision_info: Dictionary = {}

# 交互器唯一标识
var identifier: int = 0

# 选择队列
var _selector_queue: Array = []

# 拖拽状态
var _is_dragging: bool = false
var _press_time: float = 0.0
var _ori_hit_point: Vector3 = Vector3.ZERO
var _ori_hit_distance: float = 0.0

# 射线检测结果
var _physics_query: PhysicsRayQueryParameters3D
var _space_state: PhysicsDirectSpaceState3D

# 标识符生成
static var _next_id: int = 1000

# 信号
signal state_changed(old_state: int, new_state: int)
signal pointer_event(event: PointerEvent)
signal when_postprocessed()


func _init() -> void:
	identifier = _next_id
	_next_id += 1


func _ready() -> void:
	_physics_query = PhysicsRayQueryParameters3D.new()
	_physics_query.collision_mask = raycast_mask
	_physics_query.exclude = [self]
	_physics_query.hit_from_inside = false


func _process(delta: float) -> void:
	drive(delta)


func drive(delta: float) -> void:
	if state == InteractionEnums.InteractorState.DISABLED:
		return

	sample_ray()

	var iterations: int = 0

	while iterations < max_iterations_per_frame:
		iterations += 1

		match state:
			InteractionEnums.InteractorState.NORMAL:
				compute_candidate()
				var should_hover: bool = candidate != null or compute_should_select()
				if should_hover:
					do_hover()
					continue

			InteractionEnums.InteractorState.HOVER:
				if hovered == null:
					state = InteractionEnums.InteractorState.NORMAL
					continue

				compute_candidate()
				if compute_should_select() and candidate == hovered:
					do_select()
					continue

				if compute_should_unhover():
					do_unhover()
					continue

				if not _is_dragging and queued_select():
					if _press_time < click_time:
						_press_time += delta

			InteractionEnums.InteractorState.SELECT:
				if selected == null:
					do_unselect()
					continue

				if compute_should_unselect():
					do_unselect()
					continue

				do_select_update()
		break

	do_postprocess()


func sample_ray() -> void:
	_space_state = get_world_3d().direct_space_state


func compute_candidate() -> void:
	var hits: Array = InteractableRegistry.list_for_raycast(self, ray_origin, ray_forward, max_ray_length)

	if hits.is_empty():
		candidate = null
		collision_info = {"hit": false, "point": Vector3.ZERO, "normal": Vector3.ZERO, "distance": 0.0}
		_compute_no_hover_endpoint()
		return

	var best_hit: Dictionary = hits[0]
	for hit: Dictionary in hits:
		if hit.distance < best_hit.distance - equal_distance_threshold:
			best_hit = hit

	candidate = best_hit.interactable
	collision_info = {
		"hit": best_hit.hit,
		"point": best_hit.point,
		"normal": best_hit.normal,
		"distance": best_hit.distance,
	}
	ray_end = best_hit.point


func _compute_no_hover_endpoint() -> void:
	ray_end = ray_origin + ray_forward * no_hover_cursor_distance


func do_hover() -> void:
	var prev_state: int = state
	state = InteractionEnums.InteractorState.HOVER

	if candidate != null:
		hovered = candidate
		hovered.add_hover_interactor(self)
		_publish_pointer_event(InteractionEnums.PointerEventType.HOVER)

	state_changed.emit(prev_state, state)


func do_unhover() -> void:
	var prev_state: int = state
	if hovered != null:
		var prev_hovered: RayInteractable = hovered
		hovered = null
		prev_hovered.remove_hover_interactor(self)
		_publish_pointer_event(InteractionEnums.PointerEventType.UNHOVER)

	state = InteractionEnums.InteractorState.NORMAL
	candidate = null
	state_changed.emit(prev_state, state)


func do_select() -> void:
	var prev_state: int = state
	_clear_selector_queue()

	if hovered != null:
		selected = hovered
		selected.add_select_interactor(self)
		_publish_pointer_event(InteractionEnums.PointerEventType.SELECT)
		_ori_hit_point = collision_info["point"] if collision_info["hit"] else ray_end
		_ori_hit_distance = collision_info["distance"] if collision_info["hit"] else no_hover_cursor_distance

	state = InteractionEnums.InteractorState.SELECT
	_is_dragging = false
	_press_time = 0.0
	state_changed.emit(prev_state, state)


func do_unselect() -> void:
	var prev_state: int = state
	_clear_selector_queue()

	if selected != null:
		_publish_pointer_event(InteractionEnums.PointerEventType.UNSELECT)
		selected.remove_select_interactor(self)

	var was_selected: RayInteractable = selected
	selected = null
	_is_dragging = false

	if hovered != null:
		state = InteractionEnums.InteractorState.HOVER
	else:
		state = InteractionEnums.InteractorState.NORMAL

	state_changed.emit(prev_state, state)


func do_select_update() -> void:
	if selected != null:
		var select_surface: PlaneSurface = selected.select_surface if selected.select_surface else selected.surface
		if select_surface:
			var local_origin: Vector3 = selected.global_transform.affine_inverse() * ray_origin
			var local_direction: Vector3 = selected.global_transform.affine_inverse().basis * ray_forward
			var hit: Dictionary = select_surface.intersect_ray(local_origin, local_direction, max_ray_length)
			if hit.hit:
				hit.point = selected.global_transform * hit.point
				collision_info = hit
				ray_end = hit.point
			else:
				_compute_no_hover_endpoint()
		else:
			_compute_no_hover_endpoint()

		var current_hit_point: Vector3 = collision_info["point"] if collision_info["hit"] else ray_end
		var drag_delta: Vector3 = current_hit_point - _ori_hit_point
		if drag_delta.length_squared() > drag_threshold * drag_threshold:
			if not _is_dragging:
				_is_dragging = true
			_ori_hit_point = current_hit_point

	_publish_pointer_event(InteractionEnums.PointerEventType.MOVE)


func do_postprocess() -> void:
	if state == InteractionEnums.InteractorState.HOVER or state == InteractionEnums.InteractorState.SELECT:
		_publish_pointer_event(InteractionEnums.PointerEventType.MOVE)
	when_postprocessed.emit()


# --- 选择队列 ---

func handle_selected() -> void:
	_selector_queue.append(true)


func handle_unselected() -> void:
	_selector_queue.append(false)


func queued_select() -> bool:
	return _selector_queue.size() > 0 and _selector_queue[0] == true


func queued_unselect() -> bool:
	return _selector_queue.size() > 0 and _selector_queue[0] == false


func compute_should_select() -> bool:
	if not queued_select():
		return false
	return candidate == hovered and hovered != null


func compute_should_unselect() -> bool:
	return queued_unselect()


func compute_should_unhover() -> bool:
	return hovered != null and candidate != hovered


func _clear_selector_queue() -> void:
	if _selector_queue.size() > 0:
		_selector_queue.pop_front()


# --- 指针事件 ---

func _publish_pointer_event(event_type: int) -> void:
	var evt: PointerEvent = PointerEvent.new(
		identifier,
		event_type,
		ray_end if collision_info["hit"] else ray_origin + ray_forward * no_hover_cursor_distance,
		global_transform.basis.get_rotation_quaternion(),
		null
	)
	pointer_event.emit(evt)


# --- 公共接口 ---

func can_interact_with(interactable: RayInteractable) -> bool:
	return true


func get_identifier() -> int:
	return identifier


func interactable_changes_update(interactable: RayInteractable) -> void:
	if selected == interactable:
		do_unselect()
	if hovered == interactable:
		do_unhover()
