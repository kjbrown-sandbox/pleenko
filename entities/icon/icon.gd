class_name TintedIcon
extends TextureButton

const IconTintShader := preload("res://entities/icon/icon_tint.gdshader")

@export var icon_texture: Texture2D
@export var color_source: VisualTheme.Palette = VisualTheme.Palette.BG_4

# Icon from: <a href="https://www.flaticon.com/free-icons/configure" title="configure icons">Configure icons created by logisstudio - Flaticon</a>
# Arrow icon: <a href="https://www.flaticon.com/free-icons/next" title="next icons">Next icons created by Roundicons - Flaticon</a>
# Skull: <a href="https://www.flaticon.com/free-icons/skull" title="skull icons">Skull icons created by meaicon - Flaticon</a>
@export var interactive: bool = true

func _ready() -> void:
	texture_normal = icon_texture
	var mat := ShaderMaterial.new()
	mat.shader = IconTintShader
	mat.set_shader_parameter("tint_color", ThemeProvider.theme.resolve(color_source))
	material = mat
	if interactive:
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_mouse_entered() -> void:
	ThemeProvider.theme.pulse_control(self)
	(material as ShaderMaterial).set_shader_parameter("tint_color", ThemeProvider.theme.normal_text_color)


func _on_mouse_exited() -> void:
	(material as ShaderMaterial).set_shader_parameter("tint_color", ThemeProvider.theme.resolve(color_source))
