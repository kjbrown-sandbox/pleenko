class_name ChallengeButton
extends Node3D

signal pressed
signal hovered(button: ChallengeButton)

@export var color_source: VisualTheme.Palette = VisualTheme.Palette.GOLD_MAIN
@export var challenge: ChallengeData
@export var challenge_ui_name: String
@export var next_challenges: Array[String] = []
@export var is_boss := false

# Continuous attention pulse for available-but-incomplete challenges. Gentler
# than the hover pop (1.15) so hovering still reads as a distinct extra step.
const PULSE_PEAK_SCALE := 1.1

@onready var outline: Node3D = $Outline
@onready var fill_mesh: MeshInstance3D = $FillMesh
@onready var area: Area3D = $Area3D

var _state: ChallengeProgressManager.ChallengeState = ChallengeProgressManager.ChallengeState.LOCKED
var _hovered := false
var _base_scale := Vector3.ONE
var _outline_meshes: Array[MeshInstance3D] = []
var _pulse_tween: Tween


func _ready() -> void:
	if is_boss:
		_base_scale = Vector3.ONE * 1.5
		scale = _base_scale

	# Collect all outline mesh children (edges + corners)
	for child in outline.get_children():
		if child is MeshInstance3D:
			_outline_meshes.append(child)

	_apply_theme()
	ThemeProvider.theme_changed.connect(_apply_theme)
	area.input_event.connect(_on_input_event)
	area.mouse_entered.connect(_on_mouse_entered)
	area.mouse_exited.connect(_on_mouse_exited)
	ChallengeProgressManager.challenge_state_changed.connect(_on_challenge_state_changed)
	_update_pulse()


func set_state(state: ChallengeProgressManager.ChallengeState) -> void:
	_state = state
	_apply_theme()
	_update_pulse()


func _apply_theme() -> void:
	if _outline_meshes.is_empty() or not fill_mesh:
		return
	var t: VisualTheme = ThemeProvider.theme
	var tier_color: Color = t.resolve(color_source)

	var outline_color: Color
	var show_fill := false
	var fill_color: Color

	match _state:
		ChallengeProgressManager.ChallengeState.LOCKED:
			# One step toward the background so locked challenges recede.
			outline_color = t.resolve(VisualTheme.Palette.BG_5)
		ChallengeProgressManager.ChallengeState.UNLOCKED:
			outline_color = t.normal_text_color if _hovered else tier_color
		ChallengeProgressManager.ChallengeState.COMPLETED:
			outline_color = t.normal_text_color if _hovered else tier_color
			show_fill = true
			fill_color = tier_color

	# Apply outline color to all edge + corner meshes
	var outline_mat := StandardMaterial3D.new()
	if t.unshaded:
		outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_mat.albedo_color = outline_color
	for mesh_inst in _outline_meshes:
		mesh_inst.material_override = outline_mat

	# Fill only shown for completed
	fill_mesh.visible = show_fill
	if show_fill:
		var fill_mat := StandardMaterial3D.new()
		if t.unshaded:
			fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fill_mat.albedo_color = fill_color
		fill_mesh.material_override = fill_mat



func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	# Only unlocked/completed challenges can be started
	if _state == ChallengeProgressManager.ChallengeState.LOCKED:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()


func _on_mouse_entered() -> void:
	# All challenges are hoverable (to see details), regardless of state
	_hovered = true
	_apply_theme()
	_kill_pulse()  # hover pop owns the scale while hovered
	var tween := create_tween()
	tween.tween_property(self, "scale", _base_scale * 1.15, 0.1)
	hovered.emit(self)


func _on_mouse_exited() -> void:
	_hovered = false
	_apply_theme()
	if _should_pulse():
		# Let the resumed pulse animate the scale home; don't run a second
		# return-to-base tween in parallel (they'd fight over `scale`).
		_start_pulse()
	else:
		var tween := create_tween()
		tween.tween_property(self, "scale", _base_scale, 0.1)


func _should_pulse() -> bool:
	# Available but not yet completed — the actionable state worth flagging.
	return _state == ChallengeProgressManager.ChallengeState.UNLOCKED and not _hovered


func _update_pulse() -> void:
	if _should_pulse():
		if not _pulse_tween or not _pulse_tween.is_valid():
			_start_pulse()
	else:
		_kill_pulse()


func _start_pulse() -> void:
	# Kill the handle directly (not _kill_pulse) so we don't snap scale home —
	# the first leg then animates smoothly from wherever scale currently sits
	# (e.g. the 1.15 hover pop on un-hover).
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	# Mirrors VisualTheme.blink_scale_fade (Control-only) in 3D: same timing and
	# ease so the diamond pulse matches the nav-arrow pulse.
	var half: float = ThemeProvider.theme.attention_blink_duration / 2.0
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(self, "scale", _base_scale * PULSE_PEAK_SCALE, half) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(self, "scale", _base_scale, half) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _kill_pulse() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	# Only snap home when the hover pop isn't the current owner of `scale`.
	if not _hovered:
		scale = _base_scale


func _on_challenge_state_changed(challenge_id: String, new_state: ChallengeProgressManager.ChallengeState) -> void:
	if challenge_id == challenge_ui_name:
		set_state(new_state)
