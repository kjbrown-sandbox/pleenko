class_name Bucket
extends Node3D

@export var value: int = 0:
	set(v):
		value = v
		if is_node_ready():
			$BucketValue.text = str(value)

var currency_type: Enums.CurrencyType

func _ready() -> void:
	$BucketValue.text = str(value)

func setup(bucket_color: Enums.CurrencyType, _position: Vector3, _value: int) -> void:
	currency_type = bucket_color
	position = _position
	value = _value

	var mesh_color: Color
	match currency_type:
		Enums.CurrencyType.GOLD_COIN:
			mesh_color = Color(1, 0.941176, 0)
		Enums.CurrencyType.RAW_ORANGE, Enums.CurrencyType.ORANGE_COIN:
			mesh_color = Color(1, 0.5, 0)
		Enums.CurrencyType.RAW_RED, Enums.CurrencyType.RED_COIN:
			mesh_color = Color(1, 0.15, 0.15)

	var mesh_instance := get_node_or_null("MeshInstance3D")
	if not mesh_instance:
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_color = mesh_color
	mesh_instance.material_override = mat
