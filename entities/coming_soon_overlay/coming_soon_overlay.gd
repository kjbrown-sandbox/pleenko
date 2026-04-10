class_name ComingSoonOverlay
extends CanvasLayer

## Demo lockdown overlay. Shown when the player navigates to the red board or
## the orange/red challenge groups, which are unfinished. Cannot be dismissed —
## the player must navigate away with arrow keys or the nav arrow icons.

func _ready() -> void:
	layer = 5
	var t: VisualTheme = ThemeProvider.theme

	# Full-screen semi-transparent overlay. mouse_filter defaults to STOP on
	# ColorRect, which blocks all clicks on the main HUD CanvasLayer underneath.
	# The nav icons sit on a higher CanvasLayer (NavIconsLayer, layer 6) so they
	# remain clickable through this overlay.
	var overlay := ColorRect.new()
	overlay.color = t.overlay_color
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# Centered "More coming soon!" message
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var label := Label.new()
	label.text = "More coming soon!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", t.normal_text_color)
	var font: Font = t.label_font if t.label_font else null
	if font:
		label.add_theme_font_override("font", font)
	center.add_child(label)

	visible = false
