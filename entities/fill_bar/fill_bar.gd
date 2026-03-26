extends HBoxContainer

## A reusable row with a fill-bar button and an optional "+" cap button.
## Both upgrade rows and currency bars use this component.
##
## Usage:
##   fill_bar.setup(fill_color, disabled_color)
##   fill_bar.update_text("Add rows")
##   fill_bar.set_fill(0.6)
##   fill_bar.show_cap_button(true)

signal main_pressed
signal main_mouse_entered
signal main_mouse_exited
signal cap_pressed
signal cap_mouse_entered
signal cap_mouse_exited

@onready var main_button: Button = $MainButton
@onready var cap_button: Button = $CapButton

var _fill_color: Color
var _disabled_color: Color

var _fill_clip: Control
var _fill_rect: ColorRect
var _fill_label: Label
var _base_label: Label
var _main_styles: Array[StyleBoxFlat] = []
var _cap_styles: Array[StyleBoxFlat] = []


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
	_fill_label.add_theme_color_override("font_color", t.background_color)
	_fill_label.add_theme_font_override("font", btn_font)
	_fill_label.anchor_left = 0
	_fill_label.anchor_top = 0
	_fill_label.anchor_right = 0
	_fill_label.anchor_bottom = 0
	_fill_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_clip.add_child(_fill_label)

	_base_label.resized.connect(_sync_fill_label_size)
	_sync_fill_label_size.call_deferred()

	# Style cap button (same outline style, with visible text)
	_cap_styles = _apply_outline_style(cap_button, _fill_color, _disabled_color)
	cap_button.add_theme_color_override("font_color", t.normal_text_color)
	cap_button.add_theme_color_override("font_hover_color", t.normal_text_color)
	cap_button.add_theme_color_override("font_pressed_color", t.normal_text_color)
	cap_button.add_theme_color_override("font_disabled_color", t._resolve(VisualTheme.Palette.BG_5))

	main_button.focus_mode = Control.FOCUS_NONE
	cap_button.focus_mode = Control.FOCUS_NONE

	# Wire signals
	main_button.pressed.connect(func(): main_pressed.emit())
	main_button.mouse_entered.connect(func(): main_mouse_entered.emit())
	main_button.mouse_exited.connect(func(): main_mouse_exited.emit())
	cap_button.pressed.connect(func(): cap_pressed.emit())
	cap_button.mouse_entered.connect(func(): cap_mouse_entered.emit())
	cap_button.mouse_exited.connect(func(): cap_mouse_exited.emit())

	_update_corner_radii()


func _apply_outline_style(button: Button, border_col: Color, disabled_border: Color) -> Array[StyleBoxFlat]:
	var t: VisualTheme = ThemeProvider.theme

	var base_bg := t.bg_shade_1
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
	var text_color: Color
	if is_disabled or at_max:
		text_color = t._resolve(VisualTheme.Palette.BG_5)
		_fill_rect.color = _disabled_color
	else:
		text_color = t.normal_text_color
		_fill_rect.color = _fill_color
	_base_label.add_theme_color_override("font_color", text_color)
	_fill_label.add_theme_color_override("font_color", text_color)


func show_cap_button(visible: bool) -> void:
	cap_button.visible = visible
	_update_corner_radii()


func set_cap_disabled(is_disabled: bool) -> void:
	cap_button.disabled = is_disabled


func set_cap_filled(can_afford: bool) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var cap_bg: Color = _fill_color if can_afford else t.bg_shade_1
	for style in _cap_styles:
		style.bg_color = cap_bg


func pulse_main(scale_override: float = 0.0) -> void:
	_pulse_button(main_button, scale_override)


func pulse_cap() -> void:
	_pulse_button(cap_button)


# ── Internal ────────────────────────────────────────────────────────

func _update_corner_radii() -> void:
	var r: int = ThemeProvider.theme.button_border_radius
	var joined := cap_button.visible
	for style in _main_styles:
		style.corner_radius_top_right = 0 if joined else r
		style.corner_radius_bottom_right = 0 if joined else r
	for style in _cap_styles:
		style.corner_radius_top_left = 0
		style.corner_radius_bottom_left = 0


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
