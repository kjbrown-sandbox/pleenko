extends Node3D

## Floating background particles rendered behind the plinko board.
## Uses a single MultiMeshInstance3D with QuadMesh for efficient batching.
## Each particle fades in, drifts slowly with gentle rotation, then fades out.

class ParticleState:
	var elapsed := 0.0
	var total_life := 0.0
	var fade_in := 0.0
	var fade_out := 0.0
	var start_pos := Vector3.ZERO
	var drift := Vector3.ZERO
	var rotation_speed := 0.0
	var current_rotation := 0.0
	var size := 0.0
	var base_color := Color.WHITE

var _particles: Array[ParticleState] = []
var _mm_instance: MultiMeshInstance3D
var _camera: Camera3D
var _hidden_xform := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -9999, 0))

const DARKEN_BIAS := 0.7  # probability of darkening on light backgrounds (vs lightening)


func setup(cam: Camera3D) -> void:
	_camera = cam
	var t: VisualTheme = ThemeProvider.theme
	print("[BackgroundParticles] bg_particles_enabled = ", t.bg_particles_enabled)
	if not t.bg_particles_enabled:
		queue_free()
		return

	_build_multimesh(t)
	_init_particles(t)
	ThemeProvider.theme_changed.connect(_on_theme_changed)
	print("[BackgroundParticles] Setup complete: %d particles, Z=%.1f, camera size=%.1f" % [t.bg_particles_count, t.bg_particles_z, _camera.size])


func _exit_tree() -> void:
	if ThemeProvider.theme_changed.is_connected(_on_theme_changed):
		ThemeProvider.theme_changed.disconnect(_on_theme_changed)


func _process(delta: float) -> void:
	if _particles.is_empty():
		return
	var mm := _mm_instance.multimesh
	var t: VisualTheme = ThemeProvider.theme
	for i in _particles.size():
		var p := _particles[i]
		p.elapsed += delta
		if p.elapsed >= p.total_life:
			_recycle_particle(p, t)
		p.current_rotation += p.rotation_speed * delta
		var alpha := _compute_alpha(p)
		var pos := p.start_pos + p.drift * p.elapsed
		var basis := Basis.IDENTITY.scaled(Vector3.ONE * p.size).rotated(Vector3.FORWARD, p.current_rotation)
		mm.set_instance_transform(i, Transform3D(basis, pos))
		mm.set_instance_color(i, Color(p.base_color.r, p.base_color.g, p.base_color.b, alpha))


func _build_multimesh(t: VisualTheme) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE  # scaled per-instance via transform basis

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = t.bg_particles_count

	for i in t.bg_particles_count:
		mm.set_instance_transform(i, _hidden_xform)

	_mm_instance = MultiMeshInstance3D.new()
	_mm_instance.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://entities/plinko_board/drop_burst_multimesh.gdshader")
	_mm_instance.material_override = mat
	add_child(_mm_instance)


func _init_particles(t: VisualTheme) -> void:
	_particles.resize(t.bg_particles_count)
	var total_cycle := t.bg_particles_fade_duration + t.bg_particles_lifetime + t.bg_particles_fade_duration
	for i in t.bg_particles_count:
		var p := ParticleState.new()
		_randomize_particle(p, t)
		# Stagger so particles don't all sync on first load
		p.elapsed = randf() * total_cycle
		_particles[i] = p


func _recycle_particle(p: ParticleState, t: VisualTheme) -> void:
	_randomize_particle(p, t)
	p.elapsed = 0.0
	p.current_rotation = 0.0


func _randomize_particle(p: ParticleState, t: VisualTheme) -> void:
	p.fade_in = t.bg_particles_fade_duration
	p.fade_out = t.bg_particles_fade_duration
	p.total_life = p.fade_in + t.bg_particles_lifetime + p.fade_out
	p.size = t.bg_particles_base_size * randf_range(t.bg_particles_size_range.x, t.bg_particles_size_range.y)
	p.rotation_speed = randf_range(-t.bg_particles_rotation_speed, t.bg_particles_rotation_speed)
	p.base_color = _pick_color(t)
	var spawn_rect := _get_spawn_rect()
	p.start_pos = Vector3(
		randf_range(spawn_rect.position.x, spawn_rect.end.x),
		randf_range(spawn_rect.position.y, spawn_rect.end.y),
		t.bg_particles_z
	)
	var angle := randf() * TAU
	var speed := randf_range(t.bg_particles_drift_speed * 0.5, t.bg_particles_drift_speed)
	p.drift = Vector3(cos(angle) * speed, sin(angle) * speed, 0.0)


func _compute_alpha(p: ParticleState) -> float:
	if p.elapsed < p.fade_in:
		return p.elapsed / p.fade_in
	var fade_out_start := p.total_life - p.fade_out
	if p.elapsed > fade_out_start:
		return 1.0 - (p.elapsed - fade_out_start) / p.fade_out
	return 1.0


func _pick_color(t: VisualTheme) -> Color:
	var bg := t.background_color
	var shift := t.bg_particles_color_shift
	var luminance := bg.get_luminance()
	if luminance > 0.5:
		if randf() < DARKEN_BIAS:
			return bg.darkened(randf_range(shift * 0.5, shift))
		else:
			return bg.lightened(randf_range(shift * 0.3, shift * 0.7))
	else:
		if randf() < DARKEN_BIAS:
			return bg.lightened(randf_range(shift * 0.5, shift))
		else:
			return bg.darkened(randf_range(shift * 0.3, shift * 0.7))


func _get_spawn_rect() -> Rect2:
	var half_h: float = _camera.size / 2.0
	var aspect: float = get_viewport().get_visible_rect().size.x / get_viewport().get_visible_rect().size.y
	var half_w: float = half_h * aspect
	var cx: float = _camera.global_position.x
	var cy: float = _camera.global_position.y
	var pad := 1.15  # 15% padding so particles drift in from off-screen
	return Rect2(
		cx - half_w * pad,
		cy - half_h * pad,
		half_w * 2.0 * pad,
		half_h * 2.0 * pad
	)


func _on_theme_changed() -> void:
	var t: VisualTheme = ThemeProvider.theme
	if not t.bg_particles_enabled:
		_mm_instance.visible = false
		return
	_mm_instance.visible = true
	for p in _particles:
		p.base_color = _pick_color(t)
