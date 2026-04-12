class_name Bucket
extends Node3D

@export var value: int = 0:
	set(v):
		value = v
		if is_node_ready():
			_label.text = _label_text()

const SkullTexture := preload("res://assets/icons/skull.png")
const SpriteTintShader := preload("res://entities/bucket/sprite_tint.gdshader")

var currency_type: Enums.CurrencyType
var is_prestige_bucket: bool = false
var _base_material: StandardMaterial3D
var _is_hit: bool = false

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _label: Label3D = $BucketValue


func _ready() -> void:
	_label.text = _label_text()


func _label_text() -> String:
	return "?" if is_prestige_bucket else str(value)


func setup(bucket_color: Enums.CurrencyType, _position: Vector3, _value: int) -> void:
	currency_type = bucket_color
	position = _position
	value = _value

	var t: VisualTheme = ThemeProvider.theme
	_mesh.mesh = t.make_bucket_mesh()
	_base_material = t.make_bucket_material(currency_type)
	_mesh.material_override = _base_material

	_label.font_size = t.bucket_label_font_size
	_label.outline_size = t.label_outline_size
	_label.position = Vector3(0, t.bucket_label_offset, 0.05)
	_label.modulate = t.get_bucket_color(currency_type)
	if t.label_font:
		_label.font = t.label_font


func mark_hit() -> void:
	_is_hit = true
	var hit_color: Color = ThemeProvider.theme.hit_bucket_color
	_base_material.albedo_color = hit_color
	_label.modulate = hit_color


func mark_target() -> void:
	# Visually identical to mark_hit for now — separate method for semantic clarity
	mark_hit()


func mark_unhit() -> void:
	_is_hit = false
	var t: VisualTheme = ThemeProvider.theme
	_base_material.albedo_color = t.get_bucket_color(currency_type)
	_label.modulate = t.get_bucket_color(currency_type)
	_label.visible = true
	# Remove skull icon if present
	var skull := get_node_or_null("SkullIcon")
	if skull:
		skull.queue_free()


func mark_forbidden() -> void:
	mark_hit()
	_label.visible = false
	var t: VisualTheme = ThemeProvider.theme
	var skull := Sprite3D.new()
	skull.name = "SkullIcon"
	skull.texture = SkullTexture
	skull.pixel_size = 0.0006
	skull.position = Vector3(0, t.bucket_label_offset, 0.05)
	skull.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	skull.transparent = true
	var mat := ShaderMaterial.new()
	mat.shader = SpriteTintShader
	mat.set_shader_parameter("tint_color", t.hit_bucket_color)
	mat.set_shader_parameter("icon_texture", SkullTexture)
	skull.material_override = mat
	add_child(skull)


func pulse() -> void:
	var t: VisualTheme = ThemeProvider.theme
	if not t.bucket_pulse_enabled:
		return
	t.pulse_node3d(self, true, _base_material, currency_type, _is_hit)
