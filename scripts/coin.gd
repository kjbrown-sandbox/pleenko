extends Node3D

signal landed(bucket_value: int)


func animate(target_x: float, bucket_value: int) -> void:
	var peg_y := 1.2
	var bucket_y := -0.85

	var tween := create_tween()
	# Fall straight down to just above the peg
	tween.tween_property(self, "position", Vector3(0.0, peg_y, 0.0), 0.3) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# Veer left or right into the bucket
	tween.tween_property(self, "position", Vector3(target_x, bucket_y, 0.0), 0.4) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_on_landed.bind(bucket_value))


func _on_landed(bucket_value: int) -> void:
	landed.emit(bucket_value)
	queue_free()
