class_name FrostedOverlay
extends ColorRect

## Reusable frosted-glass modal backdrop. Drops in wherever a dialog used a flat
## `theme.overlay_color` ColorRect: it owns a per-instance ShaderMaterial that
## blurs + darkens the live screen behind it, and fades the whole dialog in/out.
##
## Each dialog parents its panel UNDER this node, so tweening `modulate:a` fades
## the panel cohesively while the shader's `fade` uniform fades the glass — both
## driven from `fade_in()` / `fade_out()`. The shader overwrites COLOR.a, hence
## the explicit `fade` uniform rather than relying on this node's own modulate.
##
## mouse_filter is left to the caller (some overlays swallow input, some wire
## gui_input) — this node imposes none.

const SHADER := preload("res://entities/frosted_overlay/frosted_overlay.gdshader")

var _fade_tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var t: VisualTheme = ThemeProvider.theme
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("blur_size", t.overlay_blur_size)
	mat.set_shader_parameter("tint_color", t.overlay_color)
	mat.set_shader_parameter("tint_strength", t.overlay_opacity)
	mat.set_shader_parameter("fade", 0.0)
	material = mat

	# Start hidden so children don't flash before the first fade_in.
	modulate.a = 0.0


## Reveal the glass + panel. Safe to call repeatedly; re-entry restarts the fade.
func fade_in() -> void:
	show()
	_start_fade(1.0)


## Fade the glass + panel out, then invoke `on_done` (callers hide/free). The
## callback always fires (bound to this node's own tween).
func fade_out(on_done: Callable = Callable()) -> void:
	_start_fade(0.0, on_done)


func _start_fade(target: float, on_done: Callable = Callable()) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	var duration: float = ThemeProvider.theme.overlay_blur_fade_duration
	# IDLE process + speed-scale so the fade runs in real time even when a
	# dialog (challenge-complete / offline) is shown under Engine.time_scale.
	_fade_tween = create_tween()
	_fade_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_fade_tween.set_speed_scale(1.0 / maxf(Engine.time_scale, 0.001))
	_fade_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_fade_tween.tween_method(
		func(v: float): material.set_shader_parameter("fade", v),
		material.get_shader_parameter("fade"), target, duration
	)
	_fade_tween.parallel().tween_property(self, "modulate:a", target, duration)
	if on_done.is_valid():
		_fade_tween.tween_callback(on_done)


func _exit_tree() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
