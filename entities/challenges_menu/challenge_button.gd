class_name ChallengeButton
extends Node3D

signal pressed

@export var color_source: VisualTheme.Palette = VisualTheme.Palette.GOLD_NORMAL
@export var challenge: ChallengeData
@export var challenge_ui_name: String
@export var next_challenges: Array[String] = [] 

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var area: Area3D = $Area3D

var _hovered := false


func _ready() -> void:
	_apply_theme()
	ThemeProvider.theme_changed.connect(_apply_theme)
	area.input_event.connect(_on_input_event)
	area.mouse_entered.connect(_on_mouse_entered)
	area.mouse_exited.connect(_on_mouse_exited)


func _apply_theme() -> void:
	if not mesh_instance:
		return
	var t: VisualTheme = ThemeProvider.theme
	var mat := StandardMaterial3D.new()
	mat.albedo_color = t.resolve(color_source)
	if t.unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = mat


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()


func _on_mouse_entered() -> void:
	_hovered = true
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 1.15, 0.1)


func _on_mouse_exited() -> void:
	_hovered = false
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.1)
