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


# ── Burst-and-swoop particles ─────────────────────────────────────────────────
# Two-phase sparkle flight: particles burst upward from a source, then swoop to
# a target. Used by the first-time intro animators and the milestone bar. Split
# into three steps so each caller keeps its own policy for what happens between
# and after the phases.

## Particle edge length, in pixels.
const BURST_PARTICLE_SIZE := Vector2(6, 6)
## Horizontal scatter and upward travel of the burst phase.
const BURST_SCATTER_X := 60.0
const BURST_RISE_MIN := 80.0
const BURST_RISE_MAX := 200.0


## Phase 1 — spawns `count` particles into `overlay` and bursts them upward.
## `start_fn(i) -> Vector2` gives each particle's global start position.
## Returns the particles so a later swoop/fade can drive them.
static func burst_particles(overlay: Control, count: int, color: Color,
		start_fn: Callable) -> Array[ColorRect]:
	var t: VisualTheme = ThemeProvider.theme
	var particles: Array[ColorRect] = []

	for i in count:
		var start: Vector2 = start_fn.call(i)
		var particle := ColorRect.new()
		particle.size = BURST_PARTICLE_SIZE
		particle.color = color
		particle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		particle.position = start
		overlay.add_child(particle)
		particles.append(particle)

		var scattered := Vector2(
			start.x + randf_range(-BURST_SCATTER_X, BURST_SCATTER_X),
			start.y - randf_range(BURST_RISE_MIN, BURST_RISE_MAX))
		var tween := particle.create_tween()
		tween.tween_property(particle, "position", scattered,
			t.level_up_particle_burst_duration * randf_range(0.7, 1.0)) 			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	return particles


## Phase 2 — swoops each particle to `target_fn(i)` and frees it on arrival.
## `on_all_arrived` fires once every particle has landed; particles already
## freed count as arrived, so the callback can't be stranded. Callers guard
## against re-entry themselves.
static func swoop_particles(particles: Array[ColorRect], target_fn: Callable,
		on_all_arrived: Callable) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var arrived := [0]
	var total := particles.size()

	var count_one := func() -> void:
		arrived[0] += 1
		if arrived[0] >= total:
			on_all_arrived.call()

	for i in particles.size():
		var particle := particles[i]
		if not is_instance_valid(particle):
			count_one.call()
			continue

		var tween := particle.create_tween()
		tween.tween_property(particle, "position", target_fn.call(i),
			t.level_up_particle_swoop_duration * randf_range(0.8, 1.2)) 			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(func() -> void:
			particle.queue_free()
			count_one.call()
		)


## Alternative phase 2 — fades the particles out where they are.
static func fade_particles(particles: Array[ColorRect], duration: float) -> void:
	for particle in particles:
		if not is_instance_valid(particle):
			continue
		var tween := particle.create_tween()
		tween.tween_property(particle, "modulate:a", 0.0, duration) 			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(particle.queue_free)
