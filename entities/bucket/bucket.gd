class_name Bucket
extends Node3D

@export var value: int = 0:
	set(v):
		value = v
		if is_node_ready():
			$BucketValue.text = str(value)

const SkullTexture := preload("res://assets/icons/skull.png")
const SpriteTintShader := preload("res://entities/bucket/sprite_tint.gdshader")

var currency_type: Enums.CurrencyType
var _base_material: StandardMaterial3D
var _is_hit: bool = false

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
		_base_material = t.make_bucket_material(currency_type)
		mesh_instance.material_override = _base_material

	var label := get_node_or_null("BucketValue") as Label3D
	if label:
		label.font_size = t.bucket_label_font_size
		label.outline_size = t.label_outline_size
		label.position = Vector3(0, t.bucket_label_offset, 0.05)
		label.modulate = t.get_bucket_color(currency_type)
		if t.label_font:
			label.font = t.label_font


func mark_hit() -> void:
	_is_hit = true
	var t: VisualTheme = ThemeProvider.theme
	var hit_color := t.resolve(VisualTheme.Palette.BG_6)
	if _base_material:
		_base_material.albedo_color = hit_color
	var label := get_node_or_null("BucketValue") as Label3D
	if label:
		label.modulate = hit_color


func mark_forbidden() -> void:
	mark_hit()
	var label := get_node_or_null("BucketValue") as Label3D
	if label:
		label.visible = false
	# Add skull icon with spatial tint shader
	var t: VisualTheme = ThemeProvider.theme
	var skull := Sprite3D.new()
	skull.name = "SkullIcon"
	skull.texture = SkullTexture
	skull.pixel_size = 0.0006
	# Label3D also has a -29px offset in the .tscn; approximate in world units
	skull.position = Vector3(0, t.bucket_label_offset, 0.05)
	skull.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	skull.transparent = true
	var mat := ShaderMaterial.new()
	mat.shader = SpriteTintShader
	mat.set_shader_parameter("tint_color", t.resolve(VisualTheme.Palette.BG_6))
	mat.set_shader_parameter("icon_texture", SkullTexture)
	skull.material_override = mat
	add_child(skull)


func pulse() -> void:
	var t: VisualTheme = ThemeProvider.theme

	# Flash to light color
	if _base_material:
		var flash_color := t.get_coin_color_light(currency_type)
		_base_material.albedo_color = flash_color
		var rest_color: Color = t.resolve(VisualTheme.Palette.BG_6) if _is_hit else t.get_bucket_color(currency_type)
		var color_tween := create_tween()
		color_tween.tween_property(_base_material, "albedo_color",
			rest_color, t.bucket_pulse_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# Scale pop
	var scale_tween := create_tween()
	var target_scale := Vector3.ONE * t.bucket_pulse_scale
	scale_tween.tween_property(self, "scale", target_scale, t.bucket_pulse_duration * 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	scale_tween.tween_property(self, "scale", Vector3.ONE, t.bucket_pulse_duration * 0.6) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
