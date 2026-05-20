extends SurfaceBase
## 无限平面射线交点计算
class_name PlaneSurface

var plane_normal := Vector3.UP
var plane_offset := 0.0

## 可选：限制平面范围（0 表示不限制）
var bounds_min := Vector2.ZERO
var bounds_max := Vector2.ZERO
var use_bounds := false

# 本地坐标系的基向量（用于边界检查）
var _tangent := Vector3.RIGHT
var _bitangent := Vector3.BACK


func _init(p_normal: Vector3 = Vector3.UP, p_offset: float = 0.0) -> void:
	plane_normal = p_normal.normalized()
	plane_offset = p_offset
	_calc_tangents()


func _calc_tangents() -> void:
	if abs(plane_normal.dot(Vector3.UP)) > 0.999:
		_tangent = Vector3.RIGHT
	else:
		_tangent = plane_normal.cross(Vector3.UP).normalized()
	_bitangent = plane_normal.cross(_tangent).normalized()


func intersect_ray(ray_origin: Vector3, ray_direction: Vector3, max_distance: float) -> Dictionary:
	var result := {"hit": false, "point": Vector3.ZERO, "normal": plane_normal, "distance": 0.0}

	var denom := plane_normal.dot(ray_direction)
	if abs(denom) < 0.000001:
		return result

	var plane_point := plane_normal * plane_offset
	var t := plane_normal.dot(plane_point - ray_origin) / denom

	if t <= 0.0 or t > max_distance:
		return result

	var hit_point := ray_origin + ray_direction * t

	if use_bounds:
		var local_hit := Vector2(
			(hit_point - plane_point).dot(_tangent),
			(hit_point - plane_point).dot(_bitangent)
		)
		if local_hit.x < bounds_min.x or local_hit.x > bounds_max.x:
			return result
		if local_hit.y < bounds_min.y or local_hit.y > bounds_max.y:
			return result

	result.hit = true
	result.point = hit_point
	result.distance = t
	return result
