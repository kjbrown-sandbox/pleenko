class_name ChallengeButton
extends Node3D

signal pressed
signal hovered(button: ChallengeButton)

@export var color_source: VisualTheme.Palette = VisualTheme.Palette.GOLD_NORMAL
@export var challenge: ChallengeData
@export var challenge_ui_name: String
@export var next_challenges: Array[String] = []

@onready var outer_mesh: MeshInstance3D = $OuterMesh
@onready var inner_mesh: MeshInstance3D = $InnerMesh
@onready var area: Area3D = $Area3D

var _state: ChallengeProgressManager.ChallengeState = ChallengeProgressManager.ChallengeState.LOCKED
var _hovered := false


func _ready() -> void:
	_apply_theme()
	ThemeProvider.theme_changed.connect(_apply_theme)
	area.input_event.connect(_on_input_event)
	area.mouse_entered.connect(_on_mouse_entered)
	area.mouse_exited.connect(_on_mouse_exited)
	ChallengeProgressManager.challenge_state_changed.connect(_on_challenge_state_changed)


func set_state(state: ChallengeProgressManager.ChallengeState) -> void:
	_state = state
	_apply_theme()


func _apply_theme() -> void:
	if not outer_mesh or not inner_mesh:
		return
	var t: VisualTheme = ThemeProvider.theme
	var tier_color: Color = t.resolve(color_source)

	var outer_mat := StandardMaterial3D.new()
	var inner_mat := StandardMaterial3D.new()
	if t.unshaded:
		outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	match _state:
		ChallengeProgressManager.ChallengeState.LOCKED:
			var dimmed := t.resolve(VisualTheme.Palette.BG_3)
			outer_mat.albedo_color = dimmed
			inner_mat.albedo_color = dimmed.darkened(0.3)
		ChallengeProgressManager.ChallengeState.UNLOCKED:
			outer_mat.albedo_color = tier_color if not _hovered else t.normal_text_color
			inner_mat.albedo_color = t.resolve(VisualTheme.Palette.BG_1)
		ChallengeProgressManager.ChallengeState.COMPLETED:
			outer_mat.albedo_color = tier_color if not _hovered else t.normal_text_color
			inner_mat.albedo_color = tier_color

	outer_mesh.material_override = outer_mat
	inner_mesh.material_override = inner_mat


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if _state == ChallengeProgressManager.ChallengeState.LOCKED:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()


func _on_mouse_entered() -> void:
	if _state == ChallengeProgressManager.ChallengeState.LOCKED:
		return
	_hovered = true
	_apply_theme()
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 1.15, 0.1)
	hovered.emit(self)


func _on_mouse_exited() -> void:
	if _state == ChallengeProgressManager.ChallengeState.LOCKED:
		return
	_hovered = false
	_apply_theme()
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.1)


func _on_challenge_state_changed(challenge_id: String, new_state: ChallengeProgressManager.ChallengeState) -> void:
	if challenge_id == challenge_ui_name:
		set_state(new_state)
