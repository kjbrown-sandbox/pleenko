class_name ComingSoonOverlay
extends CanvasLayer

const ButtonScene := preload("res://entities/refined_baseline_button/refined_baseline_button.tscn")

## Injectable for headless tests (MainMenu precedent).
var _shell_open_fn := func(url: String) -> void: OS.shell_open(url)

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

	# Centered end-of-demo message + wishlist button
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 32)
	center.add_child(vbox)

	var label := Label.new()
	label.text = "That's the end of the demo!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", t.normal_text_color)
	var font: Font = t.label_font if t.label_font else null
	if font:
		label.add_theme_font_override("font", font)
	vbox.add_child(label)

	var wishlist_button: RefinedBaselineButton = ButtonScene.instantiate()
	wishlist_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wishlist_button.auto_size = true
	wishlist_button.fill_amount = 1.0
	wishlist_button.title_text = "Wishlist on Steam"
	wishlist_button.main_pressed.connect(_on_wishlist_pressed)
	vbox.add_child(wishlist_button)

	visible = false


func _on_wishlist_pressed() -> void:
	_shell_open_fn.call(DemoBuild.store_link())

