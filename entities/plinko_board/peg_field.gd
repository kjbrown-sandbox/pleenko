class_name PegField
extends Node3D

## Every peg on one board, drawn as a single MultiMesh, plus the contact VFX
## (colour flash, scale pulse, glow halo, sparkle ring).
##
## Pegs are purely visual — nothing here affects where a coin goes. The board
## owns the lattice and hands down peg positions; this node owns the rendering.
## Sits at the board's origin, so peg positions are board-local either way.
##
## Flash and pulse are driven by a manual delta loop rather than per-peg Tweens:
## many pegs can be lit at once and tween churn showed up at coin volume.

const HALO_SHADER: Shader = preload("res://entities/coin/coin_halo.gdshader")
const RING_SHADER: Shader = preload("res://entities/plinko_board/peg_ring.gdshader")

var positions: PackedVector3Array = PackedVector3Array()
var base_color: Color
## Mesh rotation from the theme's peg shape — cylinders lie on their side.
var mesh_basis: Basis = Basis.IDENTITY

var _mm_instance: MultiMeshInstance3D
var _flashes: Dictionary = {}  # peg_index -> { start_color, elapsed, duration }
## Per-peg override of the colour a flash decays back to. Empty for almost every
## peg, which rests at base_color; a lucky peg sits here so a coin striking it
## flashes and then settles back to LUCKY rather than erasing the marker.
var _rest_colors: Dictionary = {}  # peg_index -> Color
var _pulses: Dictionary = {}  # peg_index -> { elapsed, duration }


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if not _flashes.is_empty():
		_update_flashes(delta)
	if not _pulses.is_empty():
		_update_pulses(delta)
	if _flashes.is_empty() and _pulses.is_empty():
		set_process(false)


func multimesh() -> MultiMesh:
	return _mm_instance.multimesh if _mm_instance else null


func count() -> int:
	return positions.size()


func is_built() -> bool:
	return _mm_instance != null


## Rebuilds the MultiMesh for `peg_positions`. Drops any in-flight flash/pulse —
## their indices refer to the old layout.
func build(peg_positions: PackedVector3Array, t: VisualTheme) -> void:
	clear()
	positions = peg_positions
	base_color = t.peg_color
	mesh_basis = Basis.from_euler(Vector3(PI / 2, 0, 0)) \
		if t.peg_shape == VisualTheme.PegShape.CYLINDER else Basis.IDENTITY

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = positions.size()
	mm.mesh = t.make_peg_mesh()
	for i in positions.size():
		mm.set_instance_transform(i, Transform3D(mesh_basis, positions[i]))
		mm.set_instance_color(i, base_color)

	_mm_instance = MultiMeshInstance3D.new()
	_mm_instance.multimesh = mm
	_mm_instance.material_override = t.make_peg_shader_material()
	add_child(_mm_instance)


func clear() -> void:
	if _mm_instance:
		_mm_instance.queue_free()
		_mm_instance = null
	_flashes.clear()
	_pulses.clear()
	_rest_colors.clear()
	set_process(false)


## Flat index of the peg nearest `local_pos`, or -1 if none is within max_dist.
func nearest_to(local_pos: Vector3, max_dist: float) -> int:
	var best := -1
	var best_dist := max_dist
	for i in positions.size():
		var d := local_pos.distance_to(positions[i])
		if d < best_dist:
			best_dist = d
			best = i
	return best


func position_of(idx: int) -> Vector3:
	return positions[idx] if idx >= 0 and idx < positions.size() else Vector3.ZERO


## The colour peg `idx` settles at once nothing is animating it.
func rest_color(idx: int) -> Color:
	return _rest_colors.get(idx, base_color)


## Paints a peg and keeps it painted: the colour survives flash decay and board
## rebuilds are handled by the caller re-applying after build(). Pass a marker
## colour to set, call clear_rest_color to release.
func set_rest_color(idx: int, color: Color) -> void:
	if not _mm_instance or idx < 0 or idx >= positions.size():
		return
	_rest_colors[idx] = color
	# Only snap if no flash owns the colour right now; otherwise the flash will
	# decay into the new rest colour on its own.
	if not _flashes.has(idx):
		_mm_instance.multimesh.set_instance_color(idx, color)


func clear_rest_color(idx: int) -> void:
	if not _rest_colors.has(idx):
		return
	_rest_colors.erase(idx)
	if _mm_instance and not _flashes.has(idx):
		_mm_instance.multimesh.set_instance_color(idx, base_color)


func flash(idx: int, color: Color, duration: float) -> void:
	if not _mm_instance:
		return
	_mm_instance.multimesh.set_instance_color(idx, color)
	_flashes[idx] = {"start_color": color, "elapsed": 0.0, "duration": duration}
	set_process(true)


func pulse(idx: int, duration: float) -> void:
	if not _mm_instance:
		return
	_pulses[idx] = {"elapsed": 0.0, "duration": duration}
	set_process(true)


func set_instance_transform(idx: int, xform: Transform3D) -> void:
	if _mm_instance:
		_mm_instance.multimesh.set_instance_transform(idx, xform)


## Scale-zeroes pegs (bomb cuts, and the not-yet-revealed pegs of a new row).
## Clears any flash/pulse claim so the per-frame loops can't write the scale
## back — otherwise a peg detonated mid-flash lingers for the pulse duration.
func hide_pegs(indices: PackedInt32Array) -> void:
	if not _mm_instance:
		return
	var hidden := mesh_basis.scaled(Vector3.ZERO)
	for idx in indices:
		if idx < 0 or idx >= positions.size():
			continue
		_flashes.erase(idx)
		_pulses.erase(idx)
		_mm_instance.multimesh.set_instance_transform(idx, Transform3D(hidden, positions[idx]))


func reveal_pegs(indices: PackedInt32Array) -> void:
	if not _mm_instance:
		return
	for idx in indices:
		if idx < 0 or idx >= positions.size():
			continue
		_mm_instance.multimesh.set_instance_transform(idx, Transform3D(mesh_basis, positions[idx]))


## Soft glow behind the struck peg.
func spawn_halo(peg_pos: Vector3, glow_color: Color, t: VisualTheme) -> void:
	var halo := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(t.peg_glow_halo_radius, t.peg_glow_halo_radius)
	halo.mesh = mesh

	var mat := ShaderMaterial.new()
	mat.shader = HALO_SHADER
	var halo_color := glow_color
	halo_color.a = t.peg_glow_halo_opacity
	mat.set_shader_parameter("glow_color", halo_color)
	mat.set_shader_parameter("opacity_mult", 1.0)
	halo.material_override = mat
	halo.position = Vector3(peg_pos.x, peg_pos.y, peg_pos.z - 0.05)
	add_child(halo)

	var tween := create_tween()
	tween.tween_property(mat, "shader_parameter/opacity_mult", 0.0, t.peg_glow_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(halo.queue_free)


## Expanding ring — the sparkle accent, rarer than the halo.
func spawn_ring(peg_pos: Vector3, ring_color: Color, t: VisualTheme) -> void:
	var ring := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	var quad_size: float = t.peg_ring_max_radius * 2.0
	mesh.size = Vector2(quad_size, quad_size)
	ring.mesh = mesh

	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter("ring_color", ring_color)
	mat.set_shader_parameter("ring_thickness", t.peg_ring_thickness)
	mat.set_shader_parameter("ring_radius", 0.0)
	mat.set_shader_parameter("opacity_mult", 0.0)
	ring.material_override = mat
	ring.position = Vector3(peg_pos.x, peg_pos.y, peg_pos.z - 0.04)
	add_child(ring)

	var max_opacity: float = t.peg_ring_max_opacity
	var tween := create_tween()
	tween.tween_method(
		func(p: float) -> void:
			mat.set_shader_parameter("ring_radius", p)
			mat.set_shader_parameter("opacity_mult", sin(p * PI) * max_opacity),
		0.0, 1.0, t.peg_ring_duration)
	tween.tween_callback(ring.queue_free)


func _update_flashes(delta: float) -> void:
	var mm := _mm_instance.multimesh
	var finished: PackedInt32Array = []
	for idx: int in _flashes:
		var f: Dictionary = _flashes[idx]
		f.elapsed += delta
		var k: float = clampf(f.elapsed / f.duration, 0.0, 1.0)
		mm.set_instance_color(idx, f.start_color.lerp(rest_color(idx), k * k))  # EASE_IN quad
		if k >= 1.0:
			finished.append(idx)
	for idx in finished:
		# Land exactly on the rest colour — lerp's endpoint is approximate, and a
		# lucky peg that settles one shade off reads as a rendering bug.
		mm.set_instance_color(idx, rest_color(idx))
		_flashes.erase(idx)


## Snap to peak, then elastic-out back to rest — the same jello feel as the
## menu board's peg wobble.
func _update_pulses(delta: float) -> void:
	var mm := _mm_instance.multimesh
	var peak: float = 1.0 + (ThemeProvider.theme.bucket_pulse_scale - 1.0) * 3.0
	var finished: PackedInt32Array = []
	for idx: int in _pulses:
		var p: Dictionary = _pulses[idx]
		p.elapsed += delta
		var k: float = clampf(p.elapsed / p.duration, 0.0, 1.0)
		var scale: float = lerpf(peak, 1.0, elastic_out(k))
		mm.set_instance_transform(idx, Transform3D(mesh_basis.scaled(Vector3.ONE * scale), positions[idx]))
		if k >= 1.0:
			finished.append(idx)
	for idx in finished:
		mm.set_instance_transform(idx, Transform3D(mesh_basis, positions[idx]))
		_pulses.erase(idx)


## Equivalent to Tween.TRANS_ELASTIC + EASE_OUT. Static so the curve is unit-
## testable without a scene tree.
static func elastic_out(x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	return pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * (TAU / 3.0)) + 1.0
