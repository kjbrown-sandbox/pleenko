extends TextureButton

@export var icon_texture: Texture2D
@export var color_source: VisualTheme.Palette = VisualTheme.Palette.BG_5   

func _ready() -> void:
	texture_normal = icon_texture
	modulate = ThemeProvider.theme._resolve(color_source)     
	# modulate = ThemeProvider.theme.background_color