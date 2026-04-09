class_name VfxUtils


## Spawns screen-space shockwave rings from a UV center point.
## All parameters after uv_center are optional named overrides;
## defaults come from VisualTheme prestige ring settings.
##
## Usage:
##   VfxUtils.spawn_shockwave(node, uv_center)
##   VfxUtils.spawn_shockwave(node, uv_center, ring_count=3, duration=2.0)
static func spawn_shockwave(
	caller: Node,
	uv_center: Vector2,
	ring_width: float = -1.0,
	distortion_strength: float = -1.0,
	ring_count: int = -1,
	ring_stagger: float = -1.0,
	duration: float = -1.0,
) -> void:
	var t: VisualTheme = ThemeProvider.theme

	# Apply defaults from VisualTheme when not overridden
	if ring_width < 0.0:
		ring_width = 0.06
	if distortion_strength < 0.0:
		distortion_strength = 0.008
	if ring_count < 0:
		ring_count = t.prestige_ring_count
	if ring_stagger < 0.0:
		ring_stagger = t.prestige_ring_stagger
	if duration < 0.0:
		duration = t.prestige_ring_duration

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

	var tween := caller.create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tween.set_speed_scale(1.0 / maxf(Engine.time_scale, 0.001))
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_method(func(r: float): mat.set_shader_parameter("radius", r), 0.0, 1.5, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(canvas.queue_free)
