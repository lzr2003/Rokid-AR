extends Node3D
## Station 2 三自由度射线姿态
## 挂在 XRCamera3D 下，位置跟随头部 + 手部偏移，旋转来自 Station2IMU
## 参考 Unity SDK ThreeDofRayPose
class_name ThreeDofRayPose

# 手部偏移（相对头部）：右下前方，模拟手持控制器的位置
@export var hand_offset: Vector3 = Vector3(0.2, -0.3, -0.3)


func _ready() -> void:
	position = hand_offset
	Station2IMU.orientation_changed.connect(_on_orientation_changed)


func _on_orientation_changed(quat: Quaternion) -> void:
	quaternion = quat
