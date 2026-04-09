class_name ChallengeConnector
extends Node3D

@export var thickness := 0.05
@export var dash_length := 0.15
@export var gap_length := 0.12

var start_challenge: ChallengeButton
var end_challenge: ChallengeButton
var _segments: Array[MeshInstance3D] = []


func setup(start: ChallengeButton, end: ChallengeButton) -> void:
	start_challenge = start
	end_challenge = end


func _ready() -> void:
	_build_line.call_deferred()
	ChallengeProgressManager.challenge_state_changed.connect(_on_state_changed)


func _on_state_changed(_id: String, _state: ChallengeProgressManager.ChallengeState) -> void:
	_rebuild()


func _rebuild() -> void:
	for seg in _segments:
		seg.queue_free()
	_segments.clear()
	_build_line()


func _build_line() -> void:
	var raw_start := start_challenge.global_position
	var raw_end := end_challenge.global_position
	var direction := (raw_end - raw_start).normalized()

	var start_state := start_challenge._state
	var end_state := end_challenge._state
	var is_solid := _should_be_solid(start_state, end_state)
	var color := _get_line_color(start_state, end_state)

	# Inset from diamond edges so lines don't appear inside nodes
	var start_inset := _diamond_edge_dist(start_challenge, direction)
	var end_inset := _diamond_edge_dist(end_challenge, -direction)
	var start_pos := raw_start + direction * start_inset
	var end_pos := raw_end - direction * end_inset
	var total_length := start_pos.distance_to(end_pos)
	if total_length <= 0:
		return

	if is_solid:
		var midpoint := (start_pos + end_pos) / 2.0
		_add_segment(midpoint, direction, total_length, color)
	else:
		_add_dashed_segments(start_pos, direction, total_length, color)


## Distance from diamond center to edge along a given direction.
## For a rotated square (diamond), this varies with angle.
func _diamond_edge_dist(btn: ChallengeButton, dir: Vector3) -> float:
	var half_side := 0.55 / 2.0 * (1.5 if btn.is_boss else 1.0)
	# Diamond edge distance = half_diagonal / (|cos(θ)| + |sin(θ)|)
	# where half_diagonal = half_side * sqrt(2) and θ is the approach angle
	var half_diag := half_side * sqrt(2)
	var ax := absf(dir.x)
	var ay := absf(dir.y)
	var denom := ax + ay
	if denom < 0.001:
		return half_diag
	return half_diag / denom


func _should_be_solid(start_state: int, end_state: int) -> bool:
	var COMPLETED := ChallengeProgressManager.ChallengeState.COMPLETED
	var UNLOCKED := ChallengeProgressManager.ChallengeState.UNLOCKED
	# Solid between completed→unlocked or completed→completed
	if start_state == COMPLETED and (end_state == UNLOCKED or end_state == COMPLETED):
		return true
	if end_state == COMPLETED and (start_state == UNLOCKED or start_state == COMPLETED):
		return true
	return false


func _get_line_color(start_state: int, end_state: int) -> Color:
	var t: VisualTheme = ThemeProvider.theme
	var COMPLETED := ChallengeProgressManager.ChallengeState.COMPLETED
	# Both completed → tier color (gold)
	if start_state == COMPLETED and end_state == COMPLETED:
		return t.resolve(start_challenge.color_source)
	# One completed, one unlocked → tier color
	if start_state == COMPLETED or end_state == COMPLETED:
		return t.resolve(start_challenge.color_source)
	# Default (locked) → dimmed
	return t.resolve(VisualTheme.Palette.BG_3)


func _add_segment(center: Vector3, direction: Vector3, length: float, color: Color) -> void:
	var seg := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(thickness, thickness, length)
	seg.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	seg.material_override = mat
	add_child(seg)
	seg.global_position = center
	seg.look_at(center + direction)
	_segments.append(seg)


func _add_dashed_segments(start_pos: Vector3, direction: Vector3, total_length: float, color: Color) -> void:
	var stride := dash_length + gap_length
	var offset := 0.0
	while offset < total_length:
		var seg_length := minf(dash_length, total_length - offset)
		var seg_center := start_pos + direction * (offset + seg_length * 0.5)
		_add_segment(seg_center, direction, seg_length, color)
		offset += stride
