class_name ChallengeConnector
extends MeshInstance3D

@export var thickness := 0.05

var start_challenge: ChallengeButton
var end_challenge: ChallengeButton

func setup(start: ChallengeButton, end: ChallengeButton) -> void:
	start_challenge = start
	end_challenge = end

func _ready() -> void:
	var start_pos = start_challenge.global_position
	var end_pos = end_challenge.global_position
	var length = start_pos.distance_to(end_pos)

	var box = BoxMesh.new()
	box.size = Vector3(thickness, thickness, length)
	mesh = box

	global_position = (start_pos + end_pos) / 2.0
	look_at(end_pos)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = ThemeProvider.theme.resolve(end_challenge.color_source)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_override = mat


