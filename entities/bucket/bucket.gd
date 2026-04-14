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
var _fade_tween: Tween
var _is_pulsing: bool = false

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _label: Label3D = $BucketValue


func _ready() -> void:
	_label.text = _label_text()
	set_process(false)


func _process(_delta: float) -> void:
	# Runs only while _is_pulsing. Breathing pulse synced to the autodrop
	# cadence: peaks at phase 0.5 (offbeat), back to 1.0 at each tick.
	var t: VisualTheme = ThemeProvider.theme
	if not t.bucket_active_pulse_enabled:
		return
	var phase: float = AudioManager.get_autodrop_phase()
	var amp: float = t.bucket_active_pulse_amplitude - 1.0
	scale = Vector3.ONE * (1.0 + amp * sin(phase * PI))


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

	# Buckets start faded and light up only when a coin lands in them (until
	# the next chord change). See mark_active / mark_inactive.
	_apply_color(_resolve_default_color())


func mark_hit() -> void:
	_stop_pulsing()
	_kill_fade_tween()
	_is_hit = true
	_apply_color(ThemeProvider.theme.hit_bucket_color)


func mark_target() -> void:
	# Visually identical to mark_hit for now — separate method for semantic clarity
	mark_hit()


func mark_unhit() -> void:
	_kill_fade_tween()
	_is_hit = false
	_apply_color(_resolve_default_color())
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


## Chord-gated activation: snap to full (optionally brightened) bucket color
## instantly and start the beat-synced breathing pulse. Called by PlinkoBoard
## when a coin lands. No-op if the bucket is already marked as hit/forbidden
## by a challenge — those markers win.
func mark_active() -> void:
	if _is_hit:
		return
	_kill_fade_tween()
	_apply_color(ThemeProvider.theme.get_bucket_color(currency_type))
	if ThemeProvider.theme.bucket_active_pulse_enabled:
		_is_pulsing = true
		set_process(true)


## Chord change: tween color + scale back to the faded baseline over `duration`
## seconds. No-op if marked hit/forbidden by a challenge. EASE_IN + TRANS_QUAD
## matches the feel of bucket_pulse so the motion language stays consistent;
## the audio fade uses EASE_OUT on purpose (see AudioManager._fade_drone).
## Stops pulsing immediately so the per-frame scale write can't clobber the
## scale-return tween.
func mark_inactive(duration: float) -> void:
	if _is_hit:
		return
	_stop_pulsing()
	_kill_fade_tween()
	var target: Color = ThemeProvider.theme.get_bucket_color_faded(currency_type)
	_fade_tween = create_tween()
	_fade_tween.bind_node(self)
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(_base_material, "albedo_color", target, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_fade_tween.tween_property(_label, "modulate", target, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_fade_tween.tween_property(self, "scale", Vector3.ONE, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _resolve_default_color() -> Color:
	return ThemeProvider.theme.get_bucket_color_faded(currency_type)


func _apply_color(color: Color) -> void:
	_base_material.albedo_color = color
	_label.modulate = color


func _stop_pulsing() -> void:
	_is_pulsing = false
	set_process(false)


func _kill_fade_tween() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
