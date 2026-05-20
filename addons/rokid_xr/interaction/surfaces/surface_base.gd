extends Resource
## 表面射线检测抽象基类
class_name SurfaceBase

## 返回 {hit: bool, point: Vector3, normal: Vector3, distance: float}
func intersect_ray(_ray_origin: Vector3, _ray_direction: Vector3, _max_distance: float) -> Dictionary:
	return {"hit": false, "point": Vector3.ZERO, "normal": Vector3.ZERO, "distance": 0.0}
