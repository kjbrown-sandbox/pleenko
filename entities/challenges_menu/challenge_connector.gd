extends MeshInstance3D

var start_challenge: ChallengeButton
var end_challenge: ChallengeButton

func setup(start: ChallengeButton, end: ChallengeButton) -> void:
   start_challenge = start
   end_challenge = end

func _ready() -> void:
   var immediate_mesh: ImmediateMesh = mesh

   immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
   immediate_mesh.surface_add_vertex(start_challenge.global_position)
   immediate_mesh.surface_add_vertex(end_challenge.global_position)
   immediate_mesh.surface_end()

   var mat := StandardMaterial3D.new()
   mat.albedo_color = ThemeProvider.theme.resolve(end_challenge.color_source)
   mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
   material_override = mat


