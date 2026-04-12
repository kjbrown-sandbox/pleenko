class_name VfxUtils


## Spawns screen-space shockwave rings from a UV center point.
## Pass overrides in opts dictionary. Unset keys use VisualTheme defaults.
##
## Supported keys:
##   ring_width: float        (default 0.06)
##   distortion_strength: float (default 0.008)
##   ring_count: int          (default prestige_ring_count)
##   ring_stagger: float      (default prestige_ring_stagger)
##   duration: float          (default prestige_ring_duration)
##
## Usage:
##   VfxUtils.spawn_shockwave(self, uv_center)
##   VfxUtils.spawn_shockwave(self, uv_center, { "ring_count": 1, "duration": 1.5 })
static func spawn_shockwave(caller: Node, uv_center: Vector2, opts: Dictionary = {}) -> void:
	var t: VisualTheme = ThemeProvider.theme

	var ring_width: float = opts.get("ring_width", 0.06)
	var distortion_strength: float = opts.get("distortion_strength", 0.008)
	var ring_count: int = opts.get("ring_count", t.prestige_ring_count)
	var ring_stagger: float = opts.get("ring_stagger", t.prestige_ring_stagger)
	var duration: float = opts.get("duration", t.prestige_ring_duration)

	for i in ring_count:
		_spawn_single_ring(caller, uv_center, ring_width, distortion_strength, duration, i * ring_stagger)


static func _spawn_single_ring(
	caller: Node,
	uv_center: Vector2,
	ring_width: float,
	distortion_strength: float,
	duration: float,
	delay: float,
) -> void:
	var shockwave_shader: Shader = preload("res://entities/prestige_vfx/shockwave.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shockwave_shader
	mat.set_shader_parameter("center", uv_center)
	mat.set_shader_parameter("radius", 0.0)
	mat.set_shader_parameter("ring_width", ring_width)
	mat.set_shader_parameter("distortion_strength", distortion_strength)

	var canvas := CanvasLayer.new()
	canvas.layer = 90
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	caller.get_tree().root.add_child(canvas)

	var rect := ColorRect.new()
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(rect)

	# Bind the tween to the canvas, not the caller. The canvas lives on root
	# until its cleanup callback frees it, so tying the tween to its lifetime
	# guarantees the callback fires — even if the caller is freed, reparented,
	# or has its tweens killed mid-animation (which used to leave a permanent
	# screen-wide distortion shader behind when level-ups happened during
	# challenge mode transitions).
	var tween := canvas.create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tween.set_speed_scale(1.0 / maxf(Engine.time_scale, 0.001))
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_method(func(r: float): mat.set_shader_parameter("radius", r), 0.0, 1.5, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(canvas.queue_free)
