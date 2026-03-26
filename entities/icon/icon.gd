extends TextureButton

const IconTintShader := preload("res://entities/icon/icon_tint.gdshader")

@export var icon_texture: Texture2D
@export var color_source: VisualTheme.Palette = VisualTheme.Palette.BG_5

# Icon from: <a href="https://www.flaticon.com/free-icons/configure" title="configure icons">Configure icons created by logisstudio - Flaticon</a>
func _ready() -> void:
	texture_normal = icon_texture
	var mat := ShaderMaterial.new()
	mat.shader = IconTintShader
	mat.set_shader_parameter("tint_color", ThemeProvider.theme._resolve(color_source))
	material = mat