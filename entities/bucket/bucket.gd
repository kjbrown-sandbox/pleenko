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


func mark_target() -> void:
	mark_hit()


func mark_unhit() -> void:
	_kill_color_tween()
	_is_hit = false
	scale = Vector3.ONE
	_apply_color(_resolve_default_color())
	_label.visible = true
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


## Chord-gated activation: snap to full color, then schedule a delayed fade
## that completes exactly as the chord change begins. Color stays at full
## until `bucket_fade_duration` seconds before the chord change, then fades
## over the same window — so the bucket is fully faded at the exact moment
## the next chord starts and is ready to receive a new hit. No-op if the
## bucket is already marked as hit/forbidden by a challenge.
func mark_active() -> void:
	if _is_hit:
		return
	_kill_color_tween()
	var t: VisualTheme = ThemeProvider.theme
	_apply_color(t.get_bucket_color(currency_type))
	set_process(true)
	var chord_remaining: float = maxf(AudioManager.get_time_until_next_chord(), t.bucket_fade_duration)
	var fade_duration: float = minf(t.bucket_fade_duration, chord_remaining)
	var delay: float = maxf(0.0, chord_remaining - fade_duration)

	_color_tween = create_tween()
	_color_tween.bind_node(self)
	_color_tween.tween_interval(delay)
	var faded: Color = t.get_bucket_color_faded(currency_type)
	_color_tween.tween_method(_apply_color,
		t.get_bucket_color(currency_type), faded, fade_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


## Backstop: called on chord_changed from PlinkoBoard. In the normal path
## mark_active's own scheduled fade has already completed by now; this just
## covers edge cases (idle reset before the scheduled fade starts, chord
## advancing earlier than expected). Kills any running tween and fades
## whatever state the bucket is currently in.
func mark_inactive(duration: float) -> void:
	if _is_hit:
		return
	_stop_pulsing()
	_kill_color_tween()
	var target: Color = ThemeProvider.theme.get_bucket_color_faded(currency_type)
	_color_tween = create_tween()
	_color_tween.bind_node(self)
	_color_tween.set_parallel(true)
	_color_tween.tween_property(_base_material, "albedo_color", target, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_color_tween.tween_property(_label, "modulate", target, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_color_tween.tween_property(self, "scale", Vector3.ONE, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _resolve_default_color() -> Color:
	return ThemeProvider.theme.get_bucket_color_faded(currency_type)


func _apply_color(color: Color) -> void:
	_base_material.albedo_color = color
	_label.modulate = color


func _stop_pulsing() -> void:
	set_process(false)


func _kill_color_tween() -> void:
	if _color_tween and _color_tween.is_valid():
		_color_tween.kill()
	_color_tween = null
