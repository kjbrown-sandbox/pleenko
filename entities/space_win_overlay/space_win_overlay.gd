class_name SpaceWinOverlay
extends CanvasLayer

## Dismissible full-screen "You win!" card, shown when all 11 space-board
## buckets are activated. Pure view: it grants nothing and changes no state —
## the win is a celebration, not a progression gate (locked decision 7).
##
## Built in code from the palette, following ComingSoonOverlay. Main owns the
## lifecycle and re-creates it on every trigger, so it stays re-triggerable for
## filming.

## Above VfxUtils' shockwave canvas (layer 90) so the activation ring can never
## draw over the win card.
const LAYER := 95

signal dismissed()


func _ready() -> void:
	layer = LAYER
	# Survive the slow-mo / freeze of any cinematic that may still be winding
	# down when the final bucket lights.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var t: VisualTheme = ThemeProvider.theme

	var backdrop := ColorRect.new()
	backdrop.color = t.overlay_color
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 32)
	center.add_child(column)

	var title := Label.new()
	title.text = "YOU WIN!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", t.normal_text_color)
	if t.label_font:
		title.add_theme_font_override("font", t.label_font)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Every colour has reached space."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 28)
	subtitle.add_theme_color_override("font_color", t.body_text_color)
	if t.label_font:
		subtitle.add_theme_font_override("font", t.label_font)
	column.add_child(subtitle)

	var button := Button.new()
	button.text = "Continue"
	button.custom_minimum_size = Vector2(240, 56)
	button.add_theme_color_override("font_color", t.button_text_color)
	button.add_theme_color_override("font_hover_color", t.button_hovered_color)
	if t.label_font:
		button.add_theme_font_override("font", t.label_font)
	button.pressed.connect(dismiss)
	column.add_child(button)


func dismiss() -> void:
	dismissed.emit()
	queue_free()
