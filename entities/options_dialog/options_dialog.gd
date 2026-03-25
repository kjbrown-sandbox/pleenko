extends CanvasLayer

signal return_to_menu_pressed

var _overlay: ColorRect
var _panel: VBoxContainer
var _return_button: Button

func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme

	# Full-screen semi-transparent overlay
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.6)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.gui_input.connect(_on_overlay_input)
	add_child(_overlay)

	# Centered panel
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 20)
	center.add_child(_panel)

	# "OPTIONS" title
	var title := Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", t.normal_text_color)
	var font: Font = t.button_font if t.button_font else t.label_font
	if font:
		title.add_theme_font_override("font", font)
	_panel.add_child(title)

	# "Return to Main Menu" button
	_return_button = Button.new()
	_return_button.text = "Return to Main Menu"
	t.apply_button_theme(_return_button)
	_return_button.pressed.connect(_on_return_pressed)
	_panel.add_child(_return_button)

	visible = false


func show_dialog() -> void:
	visible = true


func hide_dialog() -> void:
	visible = false


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Only close if clicking outside the panel
		var panel_rect := _panel.get_global_rect()
		if not panel_rect.has_point(event.global_position):
			hide_dialog()


func _on_return_pressed() -> void:
	return_to_menu_pressed.emit()
