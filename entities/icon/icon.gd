extends TextureButton

@export var icon_texture: Texture2D

func _ready() -> void:
	texture_normal = icon_texture
	# modulate = ThemeProvider.theme