extends Node3D
## 测试用可交互对象 —— 响应射线悬停和选择事件
class_name TestInteractable

var _interactable: RayInteractable
var _mesh_instance: MeshInstance3D
var _original_color := Color.WHITE
var _hover_color := Color(0.3, 1.0, 0.3, 1.0)
var _select_color := Color(1.0, 0.3, 0.3, 1.0)
var _material: StandardMaterial3D


func _ready() -> void:
	# 添加 RayInteractable 组件
	_interactable = RayInteractable.new()
	_interactable.surface = PlaneSurface.new(Vector3(0, 0, -1), 0.0)
	_interactable.name = "RayInteractable"
	add_child(_interactable)

	# 连接信号
	_interactable.hover_entered.connect(_on_hover_entered)
	_interactable.hover_exited.connect(_on_hover_exited)
	_interactable.selected.connect(_on_selected)
	_interactable.unselected.connect(_on_unselected)

	# 缓存网格材质引用
	_mesh_instance = _find_mesh_instance()
	if _mesh_instance and _mesh_instance.mesh:
		_material = StandardMaterial3D.new()
		_material.albedo_color = _original_color
		_mesh_instance.material_override = _material


func _find_mesh_instance() -> MeshInstance3D:
	for child in get_children():
		if child is MeshInstance3D:
			return child
	return null


func _on_hover_entered(_interactor) -> void:
	if _material:
		_material.albedo_color = _hover_color


func _on_hover_exited(_interactor) -> void:
	if _material:
		_material.albedo_color = _original_color


func _on_selected(_interactor) -> void:
	if _material:
		_material.albedo_color = _select_color


func _on_unselected(_interactor) -> void:
	if _material:
		# 如果仍在悬停，回到悬停色；否则回原色
		if _interactable.hover_interactors.size() > 0:
			_material.albedo_color = _hover_color
		else:
			_material.albedo_color = _original_color
