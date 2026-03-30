extends TextureButton

const IconTintShader := preload("res://entities/icon/icon_tint.gdshader")

@export var color_source: VisualTheme.Palette = VisualTheme.Palette.BG_5
## Rotation in radians applied to the icon. 0 = right, PI/2 = down, -PI/2 = up, PI = left.
@export var rotation_angle: float = 0.0


func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var mat := ShaderMaterial.new()
	mat.shader = IconTintShader
	mat.set_shader_parameter("tint_color", t.resolve(color_source))
	material = mat
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_apply_rotation.call_deferred()


func setup(_rotation_angle: float) -> void:
	rotation_angle = _rotation_angle
	_apply_rotation.call_deferred()


func _apply_rotation() -> void:
	if rotation_angle == 0.0:
		return
	pivot_offset = size / 2.0
	if absf(rotation_angle - PI) < 0.01 or absf(rotation_angle + PI) < 0.01:
		flip_h = true
	else:
		rotation = rotation_angle


func _on_mouse_entered() -> void:
	ThemeProvider.theme.pulse_control(self)
	(material as ShaderMaterial).set_shader_parameter("tint_color", ThemeProvider.theme.normal_text_color)


func _on_mouse_exited() -> void:
	(material as ShaderMaterial).set_shader_parameter("tint_color", ThemeProvider.theme.resolve(color_source))
