class_name OptionsDialog
extends CanvasLayer

const MAIN_MENU_PATH := "res://entities/main_menu/main_menu.tscn"

var _overlay: ColorRect
var _panel: VBoxContainer
var _return_button: Button
var _volume_slider: HSlider
var _volume_label: Label


func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var font: Font = t.button_font if t.button_font else t.label_font

	_overlay = ColorRect.new()
	_overlay.color = t.overlay_color
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.gui_input.connect(_on_overlay_input)
	add_child(_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 16)
	_panel.custom_minimum_size = Vector2(680.0, 0.0)
	center.add_child(_panel)

	var title := Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", t.normal_text_color)
	if font:
		title.add_theme_font_override("font", font)
	_panel.add_child(title)

	_panel.add_child(HSeparator.new())
	_panel.add_child(_make_section_header("SOUND", font))
	_panel.add_child(_make_slider_row(font))
	_panel.add_child(HSeparator.new())

	_return_button = Button.new()
	_return_button.text = "Return to Main Menu"
	t.apply_button_theme(_return_button)
	_return_button.pressed.connect(_on_return_pressed)
	_panel.add_child(_return_button)

	visible = false


func _make_section_header(text: String, font: Font) -> Label:
	var t: VisualTheme = ThemeProvider.theme
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", t.normal_text_color)
	if font:
		label.add_theme_font_override("font", font)
	return label


func _make_slider_row(font: Font) -> HBoxContainer:
	var t: VisualTheme = ThemeProvider.theme
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = "Master Volume"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", t.normal_text_color)
	if font:
		label.add_theme_font_override("font", font)
	row.add_child(label)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 100.0
	_volume_slider.step = 1.0
	_volume_slider.value = AudioManager.get_master_volume()
	_volume_slider.custom_minimum_size = Vector2(200.0, 0.0)
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume_slider.value_changed.connect(_on_volume_slider_changed)
	row.add_child(_volume_slider)

	_volume_label = Label.new()
	_volume_label.text = str(int(AudioManager.get_master_volume()))
	_volume_label.custom_minimum_size = Vector2(36.0, 0.0)
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_volume_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume_label.add_theme_font_size_override("font_size", 18)
	_volume_label.add_theme_color_override("font_color", t.normal_text_color)
	if font:
		_volume_label.add_theme_font_override("font", font)
	row.add_child(_volume_label)

	return row


func _on_volume_slider_changed(value: float) -> void:
	AudioManager.set_master_volume(value)
	_volume_label.text = str(int(value))


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide_dialog()
		get_viewport().set_input_as_handled()


func show_dialog() -> void:
	visible = true


func hide_dialog() -> void:
	visible = false


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if not _panel.get_global_rect().has_point(event.global_position):
			hide_dialog()


func _on_return_pressed() -> void:
	if not ChallengeManager.is_active_challenge:
		SaveManager.save_game()
		SaveManager.toggle_auto_save(false)
	else:
		ChallengeManager.clear_challenge()
		SaveManager.reset_state()
	SceneManager.set_new_scene(load(MAIN_MENU_PATH), false, ThemeProvider.Kind.NORMAL)
