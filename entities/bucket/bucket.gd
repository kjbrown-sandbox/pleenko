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

	var t: VisualTheme = ThemeProvider.theme
	var mesh_instance := get_node_or_null("MeshInstance3D")
	if mesh_instance:
		mesh_instance.mesh = t.make_bucket_mesh()
		mesh_instance.material_override = t.make_bucket_material(currency_type)

	var label := get_node_or_null("BucketValue") as Label3D
	if label:
		label.font_size = t.bucket_label_font_size
		label.outline_size = t.label_outline_size
		label.position = Vector3(0, t.bucket_label_offset, 0.05)
		label.modulate = t.get_bucket_color(currency_type)
		if t.label_font:
			label.font = t.label_font
