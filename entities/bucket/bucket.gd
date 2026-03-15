class_name Bucket
extends Node3D

@export var value: int = 0:
	set(v):
		value = v
		if is_node_ready():
			$BucketValue.text = str(value)

var color: Enums.BoardType

func _ready() -> void:
	$BucketValue.text = str(value)

func setup(bucket_color: Enums.BoardType, _position: Vector3, _value: int) -> void:
	color = bucket_color
	position = _position
	value = _value

	var mesh_color: Color
	if color == Enums.BoardType.GOLD:
		mesh_color = Color(1, 0.941176, 0)
	elif color == Enums.BoardType.ORANGE:
		mesh_color = Color(1, 0.5, 0)
	elif color == Enums.BoardType.RED:
		mesh_color = Color(1, 0.15, 0.15)
	
	var mesh_instance := get_node_or_null("MeshInstance3D")
	if not mesh_instance:
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_color = mesh_color
	mesh_instance.material_override = mat
