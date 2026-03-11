class_name Bucket
extends Node3D

@export var value: int = 0:
	set(v):
		value = v
		if is_node_ready():
			$BucketValue.text = str(value)

func _ready() -> void:
	$BucketValue.text = str(value)
