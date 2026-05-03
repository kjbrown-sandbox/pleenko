class_name Bucket
extends Node3D

@export var value: int = 0:
	set(v):
		value = v
		if is_node_ready():
			_label.text = _label_text()

const SkullTexture := preload("res://assets/icons/skull.png")
const SpriteTintShader := preload("res://entities/bucket/sprite_tint.gdshader")

const PRESS_DEPTH: float = 0.1
const SING_DURATION := 4.0  # matches Harp.DECAY_SECONDS
const SING_FADE_DURATION := 1.0

signal stopped_singing

var currency_type: Enums.CurrencyType
var is_prestige_bucket: bool = false
var _base_material: StandardMaterial3D
var _is_hit: bool = false
var _is_singing: bool = false
var _sing_timer: float = 0.0
var _color_tween: Tween
var _press_tween: Tween
var _upgrade_label_tween: Tween
var _rest_y: float

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _label: Label3D = $BucketValue


func _ready() -> void:
	_label.text = _label_text()
	set_process(false)


## Counts down the singing timer. Bucket stays at peak scale + full color
## for the entire duration; _stop_singing tweens back over SING_FADE_DURATION.
func _process(delta: float) -> void:
	_sing_timer -= delta
	if _sing_timer <= 0.0:
		_stop_singing()


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


func is_singing() -> bool:
	return _is_singing


## Snap to full color and start the self-timed scale pulse (SING_DURATION).
## If already singing, this is a no-op — the original timer keeps counting.
func mark_singing() -> void:
	if _is_singing:
		return
	_kill_color_tween()
	_is_singing = true
	_sing_timer = SING_DURATION
	set_process(true)

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * ThemeProvider.theme.bucket_active_scale_peak, 0.2) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	if not _is_hit:
		_apply_color(ThemeProvider.theme.get_bucket_color(currency_type))


## Externally callable stop (e.g. drum-tier expiration). Delegates to _stop_singing.
func mark_stop_singing() -> void:
	_stop_singing()


## Internal: ends singing with a short tween back to faded.
func _stop_singing() -> void:
	if not _is_singing:
		return
	_kill_color_tween()
	_is_singing = false
	_sing_timer = 0.0
	set_process(false)
	_color_tween = create_tween()
	_color_tween.bind_node(self)
	_color_tween.set_parallel(true)
	_color_tween.tween_property(self, "scale", Vector3.ONE, SING_FADE_DURATION) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	if not _is_hit:
		var faded: Color = ThemeProvider.theme.get_bucket_color_faded(currency_type)
		_color_tween.tween_property(_base_material, "albedo_color", faded, SING_FADE_DURATION) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_color_tween.tween_property(_label, "modulate", faded, SING_FADE_DURATION) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	stopped_singing.emit()


## Trampoline press: punch down on Y, spring back with a slight overshoot.
func pulse() -> void:
	var t: VisualTheme = ThemeProvider.theme if ThemeProvider else null
	if not t or not t.bucket_pulse_enabled:
		return
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	position.y = _rest_y
	_press_tween = create_tween()
	_press_tween.bind_node(self)
	_press_tween.tween_property(self, "position:y", _rest_y - PRESS_DEPTH, t.bucket_pulse_duration * 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_press_tween.tween_property(self, "position:y", _rest_y, t.bucket_pulse_duration * 0.75) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


## First half of pulse: press down.
func pulse_down() -> void:
	var t: VisualTheme = ThemeProvider.theme if ThemeProvider else null
	if not t or not t.bucket_pulse_enabled:
		return
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	position.y = _rest_y
	_press_tween = create_tween()
	_press_tween.bind_node(self)
	_press_tween.tween_property(self, "position:y", _rest_y - PRESS_DEPTH, t.bucket_pulse_duration * 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## Second half of pulse: spring back up with overshoot.
func pulse_up() -> void:
	var t: VisualTheme = ThemeProvider.theme if ThemeProvider else null
	if not t or not t.bucket_pulse_enabled:
		return
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.bind_node(self)
	_press_tween.tween_property(self, "position:y", _rest_y, t.bucket_pulse_duration * 0.75) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


## Rapidly increments the label from old_value to new_value over duration seconds.
## The internal value property should already be set before calling this.
func animate_value_upgrade(old_value: int, new_value: int, duration: float) -> void:
	if old_value == new_value or is_prestige_bucket:
		return
	if _upgrade_label_tween and _upgrade_label_tween.is_valid():
		_upgrade_label_tween.kill()
	var steps: int = new_value - old_value
	_upgrade_label_tween = create_tween()
	_upgrade_label_tween.bind_node(self)
	_upgrade_label_tween.tween_method(func(t: float) -> void:
		var current: int = old_value + roundi(t * steps)
		_label.text = str(current)
	, 0.0, 1.0, duration)


func mark_gameplay_target() -> void:
	_kill_color_tween()
	_is_hit = true
	_apply_color(ThemeProvider.theme.hit_bucket_color)


func start_gameplay_target_fade(duration: float) -> void:
	_kill_color_tween()
	_is_hit = false
	var faded_color: Color = _resolve_default_color()
	_color_tween = create_tween()
	_color_tween.bind_node(self)
	_color_tween.tween_property(_base_material, "albedo_color", faded_color, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_color_tween.parallel().tween_property(_label, "modulate", faded_color, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func stop_gameplay_target() -> void:
	_kill_color_tween()
	_is_hit = false
	_apply_color(_resolve_default_color())


func _resolve_default_color() -> Color:
	return ThemeProvider.theme.get_bucket_color_faded(currency_type)


func _apply_color(color: Color) -> void:
	_base_material.albedo_color = color
	_label.modulate = color


func _kill_color_tween() -> void:
	if _color_tween and _color_tween.is_valid():
		_color_tween.kill()
	_color_tween = null
