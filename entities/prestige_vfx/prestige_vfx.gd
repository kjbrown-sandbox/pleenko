class_name PrestigeVFX
extends Node3D

## Self-contained VFX bundle for the prestige contact moment.
## Spawns particles, shockwave ring, and desaturates the world.
## Screen shake is handled via camera h_offset/v_offset.
## All children are cleaned up automatically when this node is freed.

var _camera: Camera3D
var _board: PlinkoBoard
var _target_bucket: Bucket
var _target_coin: Coin
var _shake_active: bool = false
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_elapsed: float = 0.0
## Stores original colors so they can be restored on abort: [[material, original_color], ...]
var _darkened_materials: Array = []
## Stores original coin shader material colors: [[ShaderMaterial, original_color], ...]
var _darkened_coin_materials: Array = []
## Stores original label modulates: [[Label3D, original_color], ...]
var _darkened_labels: Array = []
## Stores original peg instance colors for MultiMesh desaturation: [[MultiMesh, index, original_color], ...]
var _darkened_peg_instances: Array = []
## Stores original cached_color for MultiMesh coins: [[Coin, original_color], ...]
var _darkened_coin_caches: Array = []
## Shockwave CanvasLayers added to root (not children of this node) that need manual cleanup.
var _shockwave_layers: Array[CanvasLayer] = []


func setup(camera: Camera3D, board: PlinkoBoard, target_bucket: Bucket, target_coin: Coin = null) -> void:
	_camera = camera
	_board = board
	_target_bucket = target_bucket
	_target_coin = target_coin
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_collect_world_materials()


## Gathers all peg and non-target-bucket materials so we can desaturate them.
func _collect_world_materials() -> void:
	var t: VisualTheme = ThemeProvider.theme
	# Pegs (MultiMesh — store per-instance colors)
	if _board._peg_multimesh_instance:
		var mm := _board._peg_multimesh_instance.multimesh
		for i in mm.instance_count:
			var color := mm.get_instance_color(i)
			_darkened_peg_instances.append([mm, i, color])

	# Non-target buckets (and their labels)
	for bucket in _board.buckets_container.get_children():
		if bucket == _target_bucket:
			continue
		var b := bucket as Bucket
		if b and b._base_material:
			_darkened_materials.append([b._base_material, b._base_material.albedo_color])
		if b and b._label:
			_darkened_labels.append([b._label, b._label.modulate])

	# Non-prestige coins — desaturate via cached_color (MultiMesh sync propagates it)
	for coin: Coin in _board._active_coin_indices:
		if coin == _target_coin:
			continue
		_darkened_coin_caches.append([coin, coin.cached_color])

	# Individually-rendered coins (ejected prestige coin handled by PrestigeAnimator)
	for child in _board.get_children():
		if child is Coin and child != _target_coin and child.multimesh_index < 0:
			var mesh := child.get_node_or_null("MeshInstance3D") as MeshInstance3D
			if mesh and mesh.material_override is ShaderMaterial:
				var shader_mat := mesh.material_override as ShaderMaterial
				var color: Color = shader_mat.get_shader_parameter("albedo_color")
				_darkened_coin_materials.append([shader_mat, color])


## Called during slow-mo to desaturate the world based on progress (0.0 to 1.0).
func update_desaturation(progress: float) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var bg: Color = t.background_color
	var amount: float = clampf(progress, 0.0, 1.0) * t.prestige_desaturation_amount

	for entry in _darkened_materials:
		var mat: StandardMaterial3D = entry[0]
		var original: Color = entry[1]
		mat.albedo_color = original.lerp(bg, amount)

	for entry in _darkened_coin_materials:
		var shader_mat: ShaderMaterial = entry[0]
		var original: Color = entry[1]
		shader_mat.set_shader_parameter("albedo_color", original.lerp(bg, amount))

	for entry in _darkened_labels:
		var label: Label3D = entry[0]
		var original: Color = entry[1]
		label.modulate = original.lerp(bg, amount)

	for entry in _darkened_peg_instances:
		var mm: MultiMesh = entry[0]
		var idx: int = entry[1]
		var original: Color = entry[2]
		mm.set_instance_color(idx, original.lerp(bg, amount))

	for entry in _darkened_coin_caches:
		var coin: Coin = entry[0]
		var original: Color = entry[1]
		if is_instance_valid(coin):
			coin.cached_color = original.lerp(bg, amount)


## Triggers all contact VFX: particles, shockwave, and screen shake.
func play_contact(contact_position: Vector3) -> void:
	var t: VisualTheme = ThemeProvider.theme
	_spawn_shockwave_ring(contact_position, t)
	start_shake(t.prestige_shake_intensity, t.prestige_shake_duration)


## Cleans up all VFX before scene transition.
func cleanup() -> void:
	# Restore original material colors
	for entry in _darkened_materials:
		var mat: StandardMaterial3D = entry[0]
		var original: Color = entry[1]
		if is_instance_valid(mat):
			mat.albedo_color = original
	for entry in _darkened_coin_materials:
		var shader_mat: ShaderMaterial = entry[0]
		var original: Color = entry[1]
		if is_instance_valid(shader_mat):
			shader_mat.set_shader_parameter("albedo_color", original)
	for entry in _darkened_labels:
		var label: Label3D = entry[0]
		var original: Color = entry[1]
		if is_instance_valid(label):
			label.modulate = original
	for entry in _darkened_peg_instances:
		var mm: MultiMesh = entry[0]
		var idx: int = entry[1]
		var original: Color = entry[2]
		mm.set_instance_color(idx, original)
	for entry in _darkened_coin_caches:
		var coin: Coin = entry[0]
		var original: Color = entry[1]
		if is_instance_valid(coin):
			coin.cached_color = original
	_darkened_materials.clear()
	_darkened_coin_materials.clear()
	_darkened_labels.clear()
	_darkened_peg_instances.clear()
	_darkened_coin_caches.clear()
	# Free shockwave CanvasLayers (added to root, not children of this node)
	for layer in _shockwave_layers:
		if is_instance_valid(layer):
			layer.queue_free()
	_shockwave_layers.clear()
	# Reset camera shake offsets
	if _camera:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0


func _spawn_particles(contact_pos: Vector3, t: VisualTheme) -> void:
	var palette_white: Color = t.resolve(VisualTheme.Palette.BG_6)
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = t.prestige_particle_radius
	particle_mesh.height = t.prestige_particle_radius * 2.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = palette_white
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for i in t.prestige_particle_count:
		var angle: float = (TAU / t.prestige_particle_count) * i
		var direction := Vector3(cos(angle), sin(angle), 0.0)
		var end_pos: Vector3 = contact_pos + direction * t.prestige_particle_speed

		var particle := MeshInstance3D.new()
		particle.mesh = particle_mesh
		# Each particle needs its own material for independent alpha fade
		var particle_mat := mat.duplicate() as StandardMaterial3D
		particle.material_override = particle_mat
		particle.position = contact_pos
		add_child(particle)

		var tween := create_tween()
		tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
		tween.set_speed_scale(1.0 / maxf(Engine.time_scale, 0.001))
		tween.tween_property(particle, "position", end_pos, t.prestige_particle_duration) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.parallel().tween_property(particle_mat, "albedo_color:a", 0.0, t.prestige_particle_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(particle.queue_free)


func _spawn_shockwave_ring(contact_pos: Vector3, t: VisualTheme) -> void:
	var screen_center: Vector2 = _camera.unproject_position(contact_pos)
	var viewport_size: Vector2 = _camera.get_viewport().get_visible_rect().size
	var uv_center := screen_center / viewport_size

	for i in t.prestige_ring_count:
		_spawn_single_ring(uv_center, t, i * t.prestige_ring_stagger)


func _spawn_single_ring(uv_center: Vector2, t: VisualTheme, delay: float) -> void:
	var shockwave_shader: Shader = preload("res://entities/prestige_vfx/shockwave.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shockwave_shader
	mat.set_shader_parameter("center", uv_center)
	mat.set_shader_parameter("radius", 0.0)
	mat.set_shader_parameter("ring_width", 0.06)
	mat.set_shader_parameter("distortion_strength", 0.008)

	var canvas := CanvasLayer.new()
	canvas.layer = 90
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(canvas)

	var rect := ColorRect.new()
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(rect)
	_shockwave_layers.append(canvas)

	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tween.set_speed_scale(1.0 / maxf(Engine.time_scale, 0.001))
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_method(func(r: float): mat.set_shader_parameter("radius", r), 0.0, 1.5, t.prestige_ring_duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(canvas.queue_free)


## Starts a screen shake that lerps from the given intensity to 0 over duration (real time).
func start_shake(intensity: float, duration: float) -> void:
	if not _camera:
		return
	_shake_active = true
	_shake_intensity = intensity
	_shake_duration = duration
	_shake_elapsed = 0.0
	set_process(true)


func _process(delta: float) -> void:
	if not _shake_active:
		set_process(false)
		return

	# Real-time delta regardless of Engine.time_scale
	var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
	_shake_elapsed += real_delta

	if _shake_elapsed >= _shake_duration:
		_shake_active = false
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		set_process(false)
		return

	var progress: float = _shake_elapsed / _shake_duration
	# Exponential decay: drops fast at first, long subtle tail
	# At progress 0.2 it's already at ~18% intensity, but still gently shaking near the end
	var decay: float = exp(-4.0 * progress)
	var current_intensity: float = _shake_intensity * decay
	_camera.h_offset = randf_range(-current_intensity, current_intensity)
	_camera.v_offset = randf_range(-current_intensity, current_intensity)
