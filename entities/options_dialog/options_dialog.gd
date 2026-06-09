class_name OptionsDialog
extends CanvasLayer

## IN_GAME-only: the path the "Return to Main Menu" footer button loads. The
## MAIN_MENU footer never constructs that button, so this is unreachable there.
const MAIN_MENU_PATH := "res://entities/main_menu/main_menu.tscn"

## Where this dialog was opened from. Set by the parent BEFORE `add_child` (the
## whole UI, including the footer, is built in `_ready`). MAIN_MENU swaps the
## in-game "Return to Game / Main Menu" footer for "Reset Game / Close".
enum Context { IN_GAME, MAIN_MENU }
var context: Context = Context.IN_GAME

## Emitted (MAIN_MENU context only) when the player asks to reset their save.
## The parent owns the confirm + the destructive call (signals up, calls down).
signal reset_requested

## Emitted (IN_GAME context, during a challenge only) when the player asks to
## abandon the current challenge. The parent (Main) owns the teardown + reload.
signal exit_challenge_requested

var _overlay: ColorRect
var _panel: VBoxContainer
var _resume_button: Button
var _return_button: Button
var _volume_slider: HSlider
var _volume_label: Label
var _fps_option: OptionButton
var _display_option: OptionButton


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

	_panel.add_child(_make_section_header("PERFORMANCE", font))
	# Display row is desktop-only. On a Web export the browser's Fullscreen API
	# requires a real user gesture and itch.io's embed wrapper already exposes
	# its own fullscreen button, so an in-game toggle would be unreliable and
	# redundant — hide it entirely instead of disabling it.
	if not OS.has_feature("web"):
		_panel.add_child(_make_display_row(font))
	_panel.add_child(_make_fps_row(font))
	_panel.add_child(HSeparator.new())

	_build_footer(t)

	visible = false


## The only context-dependent part of the dialog. IN_GAME keeps the original
## "Return to Game / Return to Main Menu" pair. MAIN_MENU builds "Reset Game /
## Close" instead — and deliberately does NOT construct `_return_button` nor
## reference `_on_return_pressed` / `MAIN_MENU_PATH`, so that in-game-only
## navigation is structurally unreachable from the menu (not merely hidden).
func _build_footer(t: VisualTheme) -> void:
	if context == Context.MAIN_MENU:
		var reset_button := Button.new()
		reset_button.text = "Reset Game"
		t.apply_button_theme(reset_button)
		reset_button.pressed.connect(_on_reset_button_pressed)
		_panel.add_child(reset_button)

		var close_button := Button.new()
		close_button.text = "Close"
		t.apply_button_theme(close_button)
		close_button.pressed.connect(hide_dialog)
		_panel.add_child(close_button)
		return

	_resume_button = Button.new()
	_resume_button.text = "Return to Game"
	t.apply_button_theme(_resume_button)
	_resume_button.pressed.connect(hide_dialog)
	_panel.add_child(_resume_button)

	# Only meaningful mid-challenge — lets the player abandon it for the picker.
	if ChallengeManager.is_active_challenge:
		var exit_button := Button.new()
		exit_button.text = "Exit Challenge"
		t.apply_button_theme(exit_button)
		exit_button.pressed.connect(_on_exit_challenge_pressed)
		_panel.add_child(exit_button)

	_return_button = Button.new()
	_return_button.text = "Return to Main Menu"
	t.apply_button_theme(_return_button)
	_return_button.pressed.connect(_on_return_pressed)
	_panel.add_child(_return_button)


## MAIN_MENU only. The parent (MainMenu) owns the confirm overlay and the
## destructive SaveManager.full_reset() call — we just signal the intent up.
func _on_reset_button_pressed() -> void:
	reset_requested.emit()


## IN_GAME, during a challenge. The parent (Main) clears the challenge and
## reloads back to the picker — we just hide and signal the intent up.
func _on_exit_challenge_pressed() -> void:
	hide_dialog()
	exit_challenge_requested.emit()


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


func _make_fps_row(font: Font) -> HBoxContainer:
	var t: VisualTheme = ThemeProvider.theme
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = "FPS Max"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", t.normal_text_color)
	if font:
		label.add_theme_font_override("font", font)
	row.add_child(label)

	_fps_option = OptionButton.new()
	_fps_option.custom_minimum_size = Vector2(200.0, 0.0)
	_fps_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.apply_button_theme(_fps_option)
	var current := PerformanceSettings.get_max_fps()
	for i in PerformanceSettings.FPS_OPTIONS.size():
		var fps: int = PerformanceSettings.FPS_OPTIONS[i]
		_fps_option.add_item(str(fps), i)
		if fps == current:
			_fps_option.select(i)
	_style_option_popup(_fps_option, font)
	_fps_option.item_selected.connect(_on_fps_selected)
	row.add_child(_fps_option)

	return row


## OptionButton's drop-down PopupMenu is not covered by apply_button_theme, so
## without this it renders with Godot's default styling — illegible against this
## game's themed background. Mirror apply_button_theme's exact pairings (the
## button-enabled/hovered backgrounds with button-text foreground) since those
## are the theme-tested, contrast-safe combinations; ad-hoc pairings are not.
func _style_option_popup(option: OptionButton, font: Font) -> void:
	var t: VisualTheme = ThemeProvider.theme

	var panel := StyleBoxFlat.new()
	panel.bg_color = t.button_enabled_color
	panel.border_color = t.button_border_color
	panel.set_border_width_all(1)
	panel.set_content_margin_all(8.0)

	var hover := StyleBoxFlat.new()
	hover.bg_color = t.button_hovered_color
	hover.border_color = t.button_border_color
	hover.set_border_width_all(1)

	var popup := option.get_popup()
	popup.add_theme_stylebox_override("panel", panel)
	popup.add_theme_stylebox_override("hover", hover)
	popup.add_theme_color_override("font_color", t.button_text_color)
	popup.add_theme_color_override("font_hover_color", t.button_text_color)
	popup.add_theme_color_override("font_accelerator_color", t.button_text_color)
	popup.add_theme_font_size_override("font_size", 20)
	if font:
		popup.add_theme_font_override("font", font)


func _on_fps_selected(index: int) -> void:
	# Applied live here; persisted via the normal save cycle (auto-save /
	# return-to-menu), matching the master-volume control above.
	PerformanceSettings.set_max_fps(PerformanceSettings.FPS_OPTIONS[index])


## Desktop-only — `_ready` skips building this row on a Web export, so the
## display preference cannot be changed from the browser. Mirrors the FPS row.
func _make_display_row(font: Font) -> HBoxContainer:
	var t: VisualTheme = ThemeProvider.theme
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = "Display"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", t.normal_text_color)
	if font:
		label.add_theme_font_override("font", font)
	row.add_child(label)

	_display_option = OptionButton.new()
	_display_option.custom_minimum_size = Vector2(200.0, 0.0)
	_display_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.apply_button_theme(_display_option)
	var current := PerformanceSettings.get_window_mode()
	for i in PerformanceSettings.WINDOW_MODE_OPTIONS.size():
		var mode: int = PerformanceSettings.WINDOW_MODE_OPTIONS[i]
		_display_option.add_item(_label_for_window_mode(mode), i)
		if mode == current:
			_display_option.select(i)
	_style_option_popup(_display_option, font)
	_display_option.item_selected.connect(_on_display_mode_selected)
	row.add_child(_display_option)

	return row


func _label_for_window_mode(mode: int) -> String:
	if mode == Window.MODE_FULLSCREEN:
		return "Fullscreen"
	return "Windowed"


func _on_display_mode_selected(index: int) -> void:
	# Applied live here; persisted via the normal save cycle (auto-save /
	# return-to-menu), matching the FPS control above.
	PerformanceSettings.set_window_mode(PerformanceSettings.WINDOW_MODE_OPTIONS[index])


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


## IN_GAME only — wired solely by the IN_GAME branch of `_build_footer`.
func _on_return_pressed() -> void:
	if not ChallengeManager.is_active_challenge:
		SaveManager.save_game()
		SaveManager.toggle_auto_save(false)
	else:
		ChallengeManager.clear_challenge()
		SaveManager.reset_state()
	SceneManager.set_new_scene(load(MAIN_MENU_PATH), false, ThemeProvider.Kind.NORMAL)
