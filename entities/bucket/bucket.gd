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
var _color_tween: Tween
var _press_tween: Tween
var _rest_y: float

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _label: Label3D = $BucketValue


func _ready() -> void:
	_label.text = _label_text()
	set_process(false)


# So that singing buckets all shrink at the same size
func _process(_delta: float) -> void:
	var phase: float = AudioManager.get_chord_phase()
	var peak: float = ThemeProvider.theme.bucket_active_scale_peak
	# Ease-out settle: drops fast from peak, eases into 1.0 by chord end.
	var t: float = 1.0 - (1.0 - phase) * (1.0 - phase)
	scale = Vector3.ONE * lerpf(peak, 1.0, t)


func _label_text() -> String:
	return "?" if is_prestige_bucket else str(value)


func setup(bucket_color: Enums.CurrencyType, _position: Vector3, _value: int) -> void:
	currency_type = bucket_color
	position = _position
	_rest_y = _position.y
	value = _value

	var t: VisualTheme = ThemeProvider.theme
	_mesh.mesh = t.make_bucket_mesh()
	_base_material = t.make_bucket_material(currency_type)
	_mesh.material_override = _base_material

	_label.font_size = t.bucket_label_font_size
	_label.outline_size = t.label_outline_size
	_label.position = Vector3(0, t.bucket_label_offset, 0.05)
	if t.label_font:
		_label.font = t.label_font

	_apply_color(_resolve_default_color())


func mark_hit() -> void:
	_kill_color_tween()
	_is_hit = true
	_apply_color(ThemeProvider.theme.hit_bucket_color)


func mark_unhit() -> void:
	_kill_color_tween()
	_is_hit = false
	scale = Vector3.ONE
	_apply_color(_resolve_default_color())
	_label.visible = true
	var skull := get_node_or_null("SkullIcon")
	if skull:
		skull.queue_free()


func mark_target() -> void:
	mark_hit()


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


## Snap to full color and start the chord-synced scale pulse. The fade back
## is driven externally by PlinkoBoard on chord_changed via mark_stop_singing.
## Hit/forbidden buckets keep their marker color but still participate in the
## scale pulse.
func mark_singing() -> void:
	_kill_color_tween()
	# set_process(true)

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * ThemeProvider.theme.bucket_active_scale_peak, 0.2) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	if not _is_hit:
		_apply_color(ThemeProvider.theme.get_bucket_color(currency_type))


## Called on chord_changed from PlinkoBoard. Stops the scale pulse and fades
## color back to the faded rest color. Hit/forbidden buckets fade scale only;
## their marker color is preserved.
func mark_stop_singing(duration: float) -> void:
	_kill_color_tween()
	set_process(false)
	_color_tween = create_tween()
	_color_tween.bind_node(self)
	_color_tween.set_parallel(true)
	_color_tween.tween_property(self, "scale", Vector3.ONE, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	if not _is_hit:
		var faded: Color = ThemeProvider.theme.get_bucket_color_faded(currency_type)
		_color_tween.tween_property(_base_material, "albedo_color", faded, duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_color_tween.tween_property(_label, "modulate", faded, duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


## Trampoline press: punch down on Y, spring back with a slight overshoot.
func pulse() -> void:
	var t: VisualTheme = ThemeProvider.theme
	if not t.bucket_pulse_enabled:
		return
	const PRESS_DURATION: float = 1.1
	const PRESS_DEPTH: float = 0.1
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	position.y = _rest_y
	_press_tween = create_tween()
	_press_tween.bind_node(self)
	_press_tween.tween_property(self, "position:y", _rest_y - PRESS_DEPTH, PRESS_DURATION * 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_press_tween.tween_property(self, "position:y", _rest_y, PRESS_DURATION * 0.75) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _resolve_default_color() -> Color:
	return ThemeProvider.theme.get_bucket_color_faded(currency_type)


func _apply_color(color: Color) -> void:
	_base_material.albedo_color = color
	_label.modulate = color


func _kill_color_tween() -> void:
	if _color_tween and _color_tween.is_valid():
		_color_tween.kill()
	_color_tween = null
