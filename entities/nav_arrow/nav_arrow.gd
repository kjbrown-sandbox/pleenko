extends MarginContainer

const IconTintShader := preload("res://entities/icon/icon_tint.gdshader")

@onready var button: TextureButton = $Button

@export var icon_texture: Texture2D
@export var color_source: VisualTheme.Palette = VisualTheme.Palette.BG_5


func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	add_theme_constant_override("margin_left", t.hud_margin)
	add_theme_constant_override("margin_right", t.hud_margin)
	add_theme_constant_override("margin_top", t.hud_margin)
	add_theme_constant_override("margin_bottom", t.hud_margin)

	button.texture_normal = icon_texture
	var mat := ShaderMaterial.new()
	mat.shader = IconTintShader
	mat.set_shader_parameter("tint_color", t.resolve(color_source))
	button.material = mat
	button.mouse_entered.connect(_on_mouse_entered)
	button.mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered() -> void:
	ThemeProvider.theme.pulse_control(button)
	(button.material as ShaderMaterial).set_shader_parameter("tint_color", ThemeProvider.theme.normal_text_color)


func _on_mouse_exited() -> void:
	(button.material as ShaderMaterial).set_shader_parameter("tint_color", ThemeProvider.theme.resolve(color_source))
