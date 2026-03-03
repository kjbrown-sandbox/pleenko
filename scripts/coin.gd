extends Node3D

signal landed(bucket_value: int)

const TIME_PER_SEGMENT := 0.15


func animate(waypoints: Array[Vector3], bucket_value: int) -> void:
	var tween := create_tween()

	for waypoint in waypoints:
		tween.tween_property(self, "position", waypoint, TIME_PER_SEGMENT) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	tween.tween_callback(_on_landed.bind(bucket_value))


func _on_landed(bucket_value: int) -> void:
	landed.emit(bucket_value)
	queue_free()
