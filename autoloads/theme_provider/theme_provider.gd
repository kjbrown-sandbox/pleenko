extends Node

signal theme_changed

@export var theme: VisualTheme = VisualTheme.new():
	set(value):
		if value == null:
			value = VisualTheme.new()
		theme = value
		theme_changed.emit()
