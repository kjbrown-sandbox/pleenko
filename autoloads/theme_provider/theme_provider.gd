extends Node

signal theme_changed

@export var theme: VisualTheme = VisualTheme.new():
	set(value):
		if value == null:
			value = VisualTheme.new()
		theme = value
		RenderingServer.set_default_clear_color(theme.background_color)
		theme_changed.emit()
