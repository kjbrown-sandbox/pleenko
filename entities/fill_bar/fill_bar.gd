class_name FillBar
extends HBoxContainer

## A reusable row with a fill-bar button and optional "-" / "+" side buttons.
## Both upgrade rows and currency bars use this component.
##
## Usage:
##   fill_bar.setup(fill_color, disabled_color)
##   fill_bar.update_text("Add rows")
##   fill_bar.set_fill(0.6)
##   fill_bar.show_plus_button(true)

signal main_pressed
signal main_mouse_entered
signal main_mouse_exited
signal plus_pressed
signal plus_mouse_entered
signal plus_mouse_exited
signal minus_pressed
signal minus_mouse_entered
signal minus_mouse_exited
signal side_button_hover(text: String)

@onready var minus_button: Button = $MinusButton
@onready var main_button: Button = $MainButton
@onready var plus_button: Button = $PlusButton

var _fill_color: Color
var _disabled_color: Color

var _fill_clip: Control
var _fill_rect: ColorRect
var _fill_label: Label
var _base_label: Label
var _main_styles: Array[StyleBoxFlat] = []
var _plus_styles: Array[StyleBoxFlat] = []
var _minus_styles: Array[StyleBoxFlat] = []

var _plus_callback: Callable
var _plus_hover_callback: Callable
var _plus_update_callback: Callable
var _minus_callback: Callable
var _minus_hover_callback: Callable
var _minus_update_callback: Callable


func setup(fill_color: Color, disabled_color: Color) -> void:
	_fill_color = fill_color
	_disabled_color = disabled_color
	_build()


func _build() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var bold_font: Font = preload("res://style_lab/VendSans-Bold.ttf")
	var btn_font: Font = t.button_font if t.button_font else bold_font

	# Style main button
	_main_styles = _apply_outline_style(main_button, _fill_color, _disabled_color)

	# Hide the button's own text — we draw our own labels
	main_button.add_theme_color_override("font_color", Color.TRANSPARENT)
	main_button.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	main_button.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	main_button.add_theme_color_override("font_disabled_color", Color.TRANSPARENT)

	var inset: float = t.button_border_width

	# Base label (unfilled area)
	_base_label = Label.new()
	_base_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_base_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_base_label.add_theme_font_size_override("font_size", t.button_font_size)
	_base_label.add_theme_color_override("font_color", t.normal_text_color)
	_base_label.add_theme_font_override("font", btn_font)
	_base_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_base_label.offset_left = inset
	_base_label.offset_top = inset
	_base_label.offset_right = -inset
	_base_label.offset_bottom = -inset
	_base_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_button.add_child(_base_label)

	# Clip container for the fill
	_fill_clip = Control.new()
	_fill_clip.clip_contents = true
	_fill_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fill_inset: float = inset - 0.5
	_fill_clip.offset_left = fill_inset
	_fill_clip.offset_top = fill_inset
	_fill_clip.offset_right = -fill_inset
	_fill_clip.offset_bottom = -fill_inset
	_fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_button.add_child(_fill_clip)

	# Fill color rect
	_fill_rect = ColorRect.new()
	_fill_rect.color = _fill_color
	_fill_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fill_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_clip.add_child(_fill_rect)

	# Fill label (clipped to filled area)
	_fill_label = Label.new()
	_fill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fill_label.add_theme_font_size_override("font_size", t.button_font_size)
	_fill_label.add_theme_color_override("font_color", t.button_fill_text_color)
	_fill_label.add_theme_font_override("font", btn_font)
	_fill_label.anchor_left = 0
	_fill_label.anchor_top = 0
	_fill_label.anchor_right = 0
	_fill_label.anchor_bottom = 0
	_fill_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_clip.add_child(_fill_label)

	_base_label.resized.connect(_sync_fill_label_size)
	_sync_fill_label_size.call_deferred()

	# Style plus button (same outline style, with visible text)
	_plus_styles = _apply_outline_style(plus_button, _fill_color, _disabled_color)
	plus_button.add_theme_color_override("font_color", t.normal_text_color)
	plus_button.add_theme_color_override("font_hover_color", t.normal_text_color)
	plus_button.add_theme_color_override("font_pressed_color", t.normal_text_color)
	plus_button.add_theme_color_override("font_disabled_color", t.button_disabled_text_color)

	# Style minus button (same outline style, with visible text)
	_minus_styles = _apply_outline_style(minus_button, _fill_color, _disabled_color)
	minus_button.add_theme_color_override("font_color", t.normal_text_color)
	minus_button.add_theme_color_override("font_hover_color", t.normal_text_color)
	minus_button.add_theme_color_override("font_pressed_color", t.normal_text_color)
	minus_button.add_theme_color_override("font_disabled_color", t.button_disabled_text_color)

	main_button.focus_mode = Control.FOCUS_NONE
	plus_button.focus_mode = Control.FOCUS_NONE
	minus_button.focus_mode = Control.FOCUS_NONE

	# Wire signals
	main_button.pressed.connect(func(): main_pressed.emit())
	main_button.mouse_entered.connect(func(): main_mouse_entered.emit())
	main_button.mouse_exited.connect(func(): main_mouse_exited.emit())
	plus_button.pressed.connect(_on_plus_pressed)
	plus_button.mouse_entered.connect(_on_plus_mouse_entered)
	plus_button.mouse_exited.connect(_on_plus_mouse_exited)
	minus_button.pressed.connect(_on_minus_pressed)
	minus_button.mouse_entered.connect(_on_minus_mouse_entered)
	minus_button.mouse_exited.connect(_on_minus_mouse_exited)

	_update_corner_radii()


func _apply_outline_style(button: Button, border_col: Color, disabled_border: Color) -> Array[StyleBoxFlat]:
	var t: VisualTheme = ThemeProvider.theme

	var base_bg := t.button_bg_color
	var normal_style := t._make_stylebox(base_bg, border_col)
	var hover_style := t._make_stylebox(base_bg, t.normal_text_color)
	var pressed_style := t._make_stylebox(base_bg, t.normal_text_color)
	var disabled_style := t._make_stylebox(base_bg, disabled_border)

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("disabled", disabled_style)
	button.add_theme_font_size_override("font_size", t.button_font_size)
	var btn_font: Font = t.button_font if t.button_font else t.label_font
	if btn_font:
		button.add_theme_font_override("font", btn_font)
	return [normal_style, hover_style, pressed_style, disabled_style] as Array[StyleBoxFlat]


# ── Public API ──────────────────────────────────────────────────────

func update_text(new_text: String) -> void:
	main_button.text = new_text
	if _base_label:
		_base_label.text = new_text
	if _fill_label:
		_fill_label.text = new_text


func set_fill(percent: float) -> void:
	if not _fill_clip:
		return
	percent = clampf(percent, 0.0, 1.0)
	_fill_clip.anchor_right = percent
	var fill_inset: float = ThemeProvider.theme.button_border_width - 0.5
	_fill_clip.offset_right = -fill_inset if percent > 0.99 else 0.0


func set_main_disabled(is_disabled: bool) -> void:
	main_button.disabled = is_disabled


func apply_fill_colors(is_disabled: bool, at_max: bool = false) -> void:
	if not _fill_rect:
		return
	var t: VisualTheme = ThemeProvider.theme
	if is_disabled or at_max:
		_fill_rect.color = _disabled_color
		_base_label.add_theme_color_override("font_color", t.button_disabled_text_color)
		_fill_label.add_theme_color_override("font_color", t.button_disabled_text_color)
	else:
		_fill_rect.color = _fill_color
		_base_label.add_theme_color_override("font_color", t.normal_text_color)
		_fill_label.add_theme_color_override("font_color", t.button_fill_text_color)


func setup_plus(on_pressed: Callable, on_hover: Callable = Callable(), on_update: Callable = Callable()) -> void:
	_plus_callback = on_pressed
	_plus_hover_callback = on_hover
	_plus_update_callback = on_update
	show_plus_button(true)


func setup_minus(on_pressed: Callable, on_hover: Callable = Callable(), on_update: Callable = Callable()) -> void:
	_minus_callback = on_pressed
	_minus_hover_callback = on_hover
	_minus_update_callback = on_update
	show_minus_button(true)


func show_plus_button(visible: bool) -> void:
	plus_button.visible = visible
	_update_corner_radii()


func set_plus_disabled(is_disabled: bool) -> void:
	plus_button.disabled = is_disabled


func set_plus_filled(can_afford: bool) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var bg: Color = _fill_color if can_afford else t.button_bg_color
	var text_col: Color = t.button_fill_text_color if can_afford else t.normal_text_color
	for style in _plus_styles:
		style.bg_color = bg
	plus_button.add_theme_color_override("font_color", text_col)
	plus_button.add_theme_color_override("font_hover_color", text_col)
	plus_button.add_theme_color_override("font_pressed_color", text_col)


func update_plus() -> void:
	if _plus_update_callback.is_valid():
		_plus_update_callback.call()


func show_minus_button(visible: bool) -> void:
	minus_button.visible = visible
	_update_corner_radii()


func set_minus_disabled(is_disabled: bool) -> void:
	minus_button.disabled = is_disabled


func set_minus_filled(active: bool) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var bg: Color = _fill_color if active else t.button_bg_color
	var text_col: Color = t.button_fill_text_color if active else t.normal_text_color
	for style in _minus_styles:
		style.bg_color = bg
	minus_button.add_theme_color_override("font_color", text_col)
	minus_button.add_theme_color_override("font_hover_color", text_col)
	minus_button.add_theme_color_override("font_pressed_color", text_col)


func update_minus() -> void:
	if _minus_update_callback.is_valid():
		_minus_update_callback.call()


func pulse_main(scale_override: float = 0.0) -> void:
	_pulse_button(main_button, scale_override)


func pulse_plus() -> void:
	_pulse_button(plus_button)


func pulse_minus() -> void:
	_pulse_button(minus_button)


# ── Internal ────────────────────────────────────────────────────────

func _on_plus_pressed() -> void:
	if _plus_callback.is_valid():
		_plus_callback.call()
	plus_pressed.emit()


func _on_plus_mouse_entered() -> void:
	pulse_plus()
	if _plus_hover_callback.is_valid():
		side_button_hover.emit(_plus_hover_callback.call())
	plus_mouse_entered.emit()


func _on_plus_mouse_exited() -> void:
	side_button_hover.emit("")
	plus_mouse_exited.emit()


func _on_minus_pressed() -> void:
	if _minus_callback.is_valid():
		_minus_callback.call()
	minus_pressed.emit()


func _on_minus_mouse_entered() -> void:
	pulse_minus()
	if _minus_hover_callback.is_valid():
		side_button_hover.emit(_minus_hover_callback.call())
	minus_mouse_entered.emit()


func _on_minus_mouse_exited() -> void:
	side_button_hover.emit("")
	minus_mouse_exited.emit()


func _update_corner_radii() -> void:
	var r: int = ThemeProvider.theme.button_border_radius
	var right_joined := plus_button.visible
	var left_joined := minus_button.visible
	for style in _main_styles:
		style.corner_radius_top_right = 0 if right_joined else r
		style.corner_radius_bottom_right = 0 if right_joined else r
		style.corner_radius_top_left = 0 if left_joined else r
		style.corner_radius_bottom_left = 0 if left_joined else r
	for style in _plus_styles:
		style.corner_radius_top_left = 0
		style.corner_radius_bottom_left = 0
	for style in _minus_styles:
		style.corner_radius_top_right = 0
		style.corner_radius_bottom_right = 0


func _sync_fill_label_size() -> void:
	if not _fill_label or not _base_label:
		return
	var inset: float = ThemeProvider.theme.button_border_width
	var fill_inset: float = inset - 0.5
	var label_offset: float = inset - fill_inset
	_fill_label.position = Vector2(label_offset, label_offset)
	_fill_label.size = _base_label.size


func _pulse_button(button: Button, scale_override: float = 0.0) -> void:
	if button.disabled:
		return
	ThemeProvider.theme.pulse_control(button, scale_override)
