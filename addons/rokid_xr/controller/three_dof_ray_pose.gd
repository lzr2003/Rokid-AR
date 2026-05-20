extends Node3D
## Station 2 三自由度射线姿态
## 每帧从 Station2IMU 读取控制器的绝对朝向，应用到射线
## 参考 Unity SDK ThreeDofRayPose + FollowCamera
class_name ThreeDofRayPose

var render_camera: Camera3D


func _ready() -> void:
	Station2IMU.orientation_changed.connect(_on_orientation_changed)
	Station2IMU.imu_recentered.connect(_on_recentered)
	call_deferred("_find_camera")


func _find_camera() -> void:
	render_camera = _find_xr_camera() if _find_xr_camera() else get_viewport().get_camera_3d()
	if render_camera == null:
		for child in get_tree().root.get_children():
			if child is Camera3D:
				render_camera = child
				break


func _find_xr_camera() -> Camera3D:
	for child in get_tree().root.get_children():
		if child is XROrigin3D:
			for c in child.get_children():
				if c is XRCamera3D:
					return c
	return null


func _process(_delta: float) -> void:
	# 位置跟随相机（参考 Unity FollowCamera）
	if render_camera:
		global_position = render_camera.global_position


func _on_orientation_changed(quat: Quaternion) -> void:
	# Station 2 IMU → 射线朝向
	# 默认射线方向 = -Z（Godot 前向），IMU 四元数旋转它
	quaternion = quat


func _on_recentered() -> void:
	quaternion = Quaternion.IDENTITY
