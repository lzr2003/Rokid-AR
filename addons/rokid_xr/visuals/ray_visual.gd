extends MeshInstance3D
## 射线激光束可视化
## 使用 ImmediateMesh 每帧动态绘制（替代 Unity 的 LineRenderer）
class_name RayVisual

const InteractionEnums = preload("res://addons/rokid_xr/interaction/interactor_state.gd")

@export var ray_interactor: RayInteractor
@export var normal_ray_length: float = 5.0
@export var ray_width: float = 0.002
@export var bezier_segments: int = 16
@export var bezier_curve_weight: float = 0.3
@export var default_color: Color = Color(0.2, 0.6, 1.0, 0.8)
@export var hover_color: Color = Color(0.2, 1.0, 0.4, 0.9)
@export var select_color: Color = Color(1.0, 0.3, 0.3, 1.0)

var _mesh: ImmediateMesh
var _material: StandardMaterial3D
var _is_visible: bool = true
var _bezier_drag_target: Vector3 = Vector3.ZERO
var _use_bezier: bool = false


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	mesh = _mesh

	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.disable_receive_shadows = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true

	var material_copy: StandardMaterial3D = _material.duplicate() as StandardMaterial3D
	material_copy.albedo_color = default_color
	material_copy.emission = default_color
	material_copy.emission_energy_multiplier = 2.0
	material_override = material_copy

	if ray_interactor == null:
		ray_interactor = _find_ray_interactor()

	if ray_interactor:
		ray_interactor.when_postprocessed.connect(_update_visual)
		ray_interactor.state_changed.connect(_on_state_changed)


func _find_ray_interactor() -> RayInteractor:
	var parent: Node = get_parent()
	while parent:
		var found: RayInteractor = _search_ray_interactor(parent)
		if found:
			return found
		parent = parent.get_parent()
	return null


func _search_ray_interactor(node: Node) -> RayInteractor:
	for child in node.get_children():
		if child is RayInteractor:
			return child
		var found: RayInteractor = _search_ray_interactor(child)
		if found:
			return found
	return null


func _on_state_changed(_old: int, _new: int) -> void:
	_update_material_color()


func _update_material_color() -> void:
	if ray_interactor == null:
		return

	var color: Color
	match ray_interactor.state:
		InteractionEnums.InteractorState.NORMAL:
			color = default_color
		InteractionEnums.InteractorState.HOVER:
			color = hover_color
		InteractionEnums.InteractorState.SELECT:
			color = select_color
		InteractionEnums.InteractorState.DISABLED:
			color = default_color
			_is_visible = false
			hide()
			return

	if not _is_visible:
		_is_visible = true
		show()

	if material_override:
		(material_override as StandardMaterial3D).albedo_color = color
		(material_override as StandardMaterial3D).emission = color


func _update_visual() -> void:
	if ray_interactor == null:
		return

	if ray_interactor.state == InteractionEnums.InteractorState.DISABLED:
		hide()
		return

	show()
	_update_material_color()
	_mesh.clear_surfaces()

	var origin: Vector3 = ray_interactor.ray_origin
	var forward: Vector3 = ray_interactor.ray_forward
	var interpolated_end: Vector3

	match ray_interactor.state:
		InteractionEnums.InteractorState.NORMAL:
			interpolated_end = origin + forward * normal_ray_length
			_draw_straight_ray(origin, interpolated_end)

		InteractionEnums.InteractorState.HOVER:
			if ray_interactor.collision_info.hit:
				interpolated_end = ray_interactor.ray_end
			else:
				interpolated_end = origin + forward * normal_ray_length
			_draw_straight_ray(origin, interpolated_end)

		InteractionEnums.InteractorState.SELECT:
			if ray_interactor.collision_info.hit:
				interpolated_end = ray_interactor.ray_end
				if _use_bezier and _bezier_drag_target.length_squared() > 0.001:
					_draw_bezier_ray(origin, interpolated_end)
				else:
					_draw_straight_ray(origin, interpolated_end)
			else:
				interpolated_end = origin + forward * normal_ray_length
				_draw_straight_ray(origin, interpolated_end)


func _draw_straight_ray(start: Vector3, end: Vector3) -> void:
	var local_start: Vector3 = to_local(start)
	var local_end: Vector3 = to_local(end)
	var dir: Vector3 = (local_end - local_start).normalized()
	var perp: Vector3 = _get_perpendicular(dir)

	var half_width: float = ray_width / 2.0

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var v0: Vector3 = local_start + perp * half_width
	var v1: Vector3 = local_start - perp * half_width
	var v2: Vector3 = local_end - perp * half_width
	var v3: Vector3 = local_end + perp * half_width

	_mesh.surface_set_normal(Vector3.FORWARD)
	_mesh.surface_set_color(Color.WHITE)
	_mesh.surface_add_vertex(v0)
	_mesh.surface_add_vertex(v1)
	_mesh.surface_add_vertex(v2)

	_mesh.surface_add_vertex(v0)
	_mesh.surface_add_vertex(v2)
	_mesh.surface_add_vertex(v3)

	_mesh.surface_end()


func _draw_bezier_ray(start: Vector3, end: Vector3) -> void:
	var local_start: Vector3 = to_local(start)
	var local_end: Vector3 = to_local(end)
	var mid: Vector3 = (local_start + local_end) / 2.0
	var offset: Vector3 = Vector3(0.0, -(local_start.distance_to(local_end) * bezier_curve_weight), 0.0)

	var p0: Vector3 = local_start
	var p1: Vector3 = lerp(local_start, mid, 0.5) + offset
	var p2: Vector3 = lerp(mid, local_end, 0.5) + offset
	var p3: Vector3 = local_end

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	for i in range(bezier_segments + 1):
		var t: float = float(i) / bezier_segments
		var point: Vector3 = _cubic_bezier(p0, p1, p2, p3, t)

		var tangent: Vector3
		if i < bezier_segments:
			tangent = (_cubic_bezier(p0, p1, p2, p3, t + 0.001) - point).normalized()
		else:
			tangent = (point - _cubic_bezier(p0, p1, p2, p3, t - 0.001)).normalized()

		var perp: Vector3 = _get_perpendicular(tangent)
		var half_width: float = ray_width / 2.0

		_mesh.surface_set_color(Color.WHITE)
		_mesh.surface_set_normal(Vector3.FORWARD)
		_mesh.surface_add_vertex(point + perp * half_width)
		_mesh.surface_add_vertex(point - perp * half_width)

	_mesh.surface_end()


func _cubic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	var tt: float = t * t
	var uu: float = u * u
	var uuu: float = uu * u
	var ttt: float = tt * t
	return uuu * p0 + 3.0 * uu * t * p1 + 3.0 * u * tt * p2 + ttt * p3


func _get_perpendicular(dir: Vector3) -> Vector3:
	var up: Vector3 = Vector3.UP
	if abs(dir.dot(up)) > 0.999:
		return Vector3.RIGHT
	return dir.cross(up).normalized()


func set_bezier_drag_target(target: Vector3) -> void:
	_bezier_drag_target = target
	_use_bezier = true


func clear_bezier_drag() -> void:
	_use_bezier = false
	_bezier_drag_target = Vector3.ZERO


func _exit_tree() -> void:
	if ray_interactor:
		if ray_interactor.when_postprocessed.is_connected(_update_visual):
			ray_interactor.when_postprocessed.disconnect(_update_visual)
		if ray_interactor.state_changed.is_connected(_on_state_changed):
			ray_interactor.state_changed.disconnect(_on_state_changed)
