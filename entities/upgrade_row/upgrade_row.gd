extends HBoxContainer

signal hover_info_changed(text: String)

@onready var purchase_button: Button = $PurchaseButton
@onready var cap_raise_button: Button = $CapRaiseButton

var _board_type: Enums.BoardType
var _upgrade_type: Enums.UpgradeType
var _callback: Callable
var _currency_type: int = -1

# Progress bar fill nodes (built in _ready)
var _fill_clip: Control
var _fill_rect: ColorRect
var _fill_label: Label
var _base_label: Label
var _is_hovered := false
var _purchase_styles: Array[StyleBoxFlat] = []  # normal, hover, pressed, disabled
var _cap_styles: Array[StyleBoxFlat] = []

func setup(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType, on_upgrade: Callable) -> void:
	_board_type = board_type
	_upgrade_type = upgrade_type
	_callback = on_upgrade
	_currency_type = Enums.currency_for_board(_board_type)

func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var bold_font: Font = preload("res://style_lab/VendSans-Bold.ttf")
	var btn_font: Font = t.button_font if t.button_font else bold_font

	# Style the purchase button as an outline-only container
	_purchase_styles = _apply_outline_style(purchase_button)

	# Hide the button's own text — we draw our own labels
	purchase_button.add_theme_color_override("font_color", Color.TRANSPARENT)
	purchase_button.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	purchase_button.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	purchase_button.add_theme_color_override("font_disabled_color", Color.TRANSPARENT)

	# Inset for labels/fill so they sit inside the border
	var inset: float = t.button_border_width

	# Base label (unfilled area — text color)
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
	purchase_button.add_child(_base_label)

	# Clip container for the fill — inset to sit just inside the border
	_fill_clip = Control.new()
	_fill_clip.clip_contents = true
	_fill_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fill_inset: float = inset - 0.5
	_fill_clip.offset_left = fill_inset
	_fill_clip.offset_top = fill_inset
	_fill_clip.offset_right = -fill_inset
	_fill_clip.offset_bottom = -fill_inset
	_fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	purchase_button.add_child(_fill_clip)

	# Fill color rect (full size within clip)
	_fill_rect = ColorRect.new()
	_fill_rect.color = t.button_enabled_color
	_fill_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fill_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_clip.add_child(_fill_rect)

	# Fill label (inverted text — bg color, clipped to filled area)
	# Must span the full button content area so text centers correctly,
	# even though the clip container may be narrower.
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
	# Keep fill label sized to match base label (which auto-sizes via anchors)
	_base_label.resized.connect(_sync_fill_label_size)
	_sync_fill_label_size.call_deferred()

	# Cap raise button — same outline style as purchase button
	_cap_styles = _apply_outline_style(cap_raise_button)
	cap_raise_button.add_theme_color_override("font_color", t.normal_text_color)
	cap_raise_button.add_theme_color_override("font_hover_color", t.normal_text_color)
	cap_raise_button.add_theme_color_override("font_pressed_color", t.normal_text_color)
	cap_raise_button.add_theme_color_override("font_disabled_color", t._resolve(VisualTheme.Palette.BG_5))

	purchase_button.focus_mode = Control.FOCUS_NONE
	cap_raise_button.focus_mode = Control.FOCUS_NONE
	_update_button()
	purchase_button.pressed.connect(_on_pressed)
	purchase_button.mouse_entered.connect(_on_mouse_entered)
	purchase_button.mouse_exited.connect(_on_mouse_exited)
	cap_raise_button.pressed.connect(_on_cap_raise_pressed)
	cap_raise_button.mouse_entered.connect(_on_cap_raise_mouse_entered)
	cap_raise_button.mouse_exited.connect(_on_cap_raise_mouse_exited)
	CurrencyManager.currency_changed.connect(_on_currency_changed)
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	UpgradeManager.cap_raise_unlocked.connect(_on_cap_raise_unlocked)

	_update_cap_raise_visibility()


func _apply_outline_style(button: Button) -> Array[StyleBoxFlat]:
	var t: VisualTheme = ThemeProvider.theme
	var border_col := t.button_enabled_color
	var disabled_border := t.button_disabled_color

	var base_bg := t.bg_shade_1
	var normal_style := t._make_stylebox(base_bg, border_col)
	var hover_style := t._make_stylebox(base_bg, t.button_hovered_color)
	var pressed_style := t._make_stylebox(base_bg, t.button_hovered_color)
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


func _on_pressed() -> void:
	_callback.call()
	_update_button()
	hover_info_changed.emit(_get_purchase_hover_text())

func _on_cap_raise_pressed() -> void:
	UpgradeManager.buy_cap_raise(_board_type, _upgrade_type)
	_update_button()
	hover_info_changed.emit(_get_cap_raise_hover_text())

func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
	_update_button()

func _on_upgrade_purchased(_type: Enums.UpgradeType, _board: Enums.BoardType, _new_level: int) -> void:
	_update_button()

func _on_cap_raise_unlocked(board_type: Enums.BoardType) -> void:
	if board_type == _board_type:
		_update_cap_raise_visibility()

func _update_cap_raise_visibility() -> void:
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, _upgrade_type)
	cap_raise_button.visible = state.base_cap > 0 and UpgradeManager.is_cap_raise_available(_board_type)
	_update_corner_radii()

func _update_corner_radii() -> void:
	var r: int = ThemeProvider.theme.button_border_radius
	var joined := cap_raise_button.visible
	for style in _purchase_styles:
		style.corner_radius_top_right = 0 if joined else r
		style.corner_radius_bottom_right = 0 if joined else r
	for style in _cap_styles:
		style.corner_radius_top_left = 0
		style.corner_radius_bottom_left = 0

func _update_button() -> void:
	var data: BaseUpgradeData = UpgradeManager.get_upgrade(_upgrade_type)
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, _upgrade_type)
	var at_max := state.current_cap > 0 and state.level >= state.current_cap

	var display_text: String
	if at_max:
		display_text = "%s (MAX)" % data.display_name
	else:
		var currency_name: String = Enums.CurrencyType.keys()[Enums.currency_for_board(_board_type)].to_lower().replace("_", " ")
		display_text = "%s" % [data.display_name]

	purchase_button.text = display_text
	_base_label.text = display_text
	_fill_label.text = display_text

	_update_fill(state, at_max)

	var is_disabled := not UpgradeManager.can_buy(_board_type, _upgrade_type)
	purchase_button.disabled = is_disabled
	_apply_fill_colors(is_disabled, at_max)

	if cap_raise_button.visible:
		cap_raise_button.text = "+"
		cap_raise_button.disabled = not UpgradeManager.can_buy_cap_raise(_board_type, _upgrade_type)


func _apply_fill_colors(is_disabled: bool, at_max: bool = false) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var text_color: Color
	if is_disabled or at_max:
		text_color = t._resolve(VisualTheme.Palette.BG_5)
		_fill_rect.color = t.button_disabled_color
	else:
		text_color = t.normal_text_color
		_fill_rect.color = t.button_enabled_color
	_base_label.add_theme_color_override("font_color", text_color)
	_fill_label.add_theme_color_override("font_color", text_color)


func _sync_fill_label_size() -> void:
	if not _fill_label or not _base_label:
		return
	# The fill clip starts at (fill_inset, fill_inset) in button space.
	# The base label starts at (inset, inset) in button space.
	# Offset the fill label so it aligns with base label.
	var inset: float = ThemeProvider.theme.button_border_width
	var fill_inset: float = inset - 0.5
	var label_offset: float = inset - fill_inset
	_fill_label.position = Vector2(label_offset, label_offset)
	_fill_label.size = _base_label.size


func _update_fill(state: UpgradeManager.UpgradeState, at_max: bool) -> void:
	if not _fill_clip:
		return
	var fill_percent := 0.0
	if at_max:
		fill_percent = 1.0
	elif state.cost > 0:
		var balance: int = CurrencyManager.get_balance(Enums.currency_for_board(_board_type))
		fill_percent = clampf(float(balance) / float(state.cost), 0.0, 1.0)
	_fill_clip.anchor_right = fill_percent
	# Keep the right inset so the border stays visible even at 100% fill.
	var fill_inset: float = ThemeProvider.theme.button_border_width - 0.5
	_fill_clip.offset_right = -fill_inset if fill_percent > 0.99 else 0.0


func _on_mouse_entered() -> void:
	_is_hovered = true
	if not purchase_button.disabled:
		_apply_fill_colors(false)
	_pulse_button(purchase_button, 1.005)
	hover_info_changed.emit(_get_purchase_hover_text())

func _on_mouse_exited() -> void:
	_is_hovered = false
	if not purchase_button.disabled:
		_apply_fill_colors(false)
	hover_info_changed.emit("")

func _on_cap_raise_mouse_entered() -> void:
	hover_info_changed.emit(_get_cap_raise_hover_text())
	_pulse_button(cap_raise_button)

func _on_cap_raise_mouse_exited() -> void:
	hover_info_changed.emit("")

func _pulse_button(button: Button, scale_override: float = 0.0) -> void:
	if button.disabled:
		return
	var t: VisualTheme = ThemeProvider.theme
	var s: float = scale_override if scale_override > 0.0 else t.button_pulse_scale
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * s, t.button_pulse_duration * 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(button, "scale", Vector2.ONE, t.button_pulse_duration * 0.6) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)

func _get_currency_name(currency_type: int) -> String:
	return Enums.CurrencyType.keys()[currency_type].to_lower().replace("_", " ").replace(" coin", "")

func _get_purchase_hover_text() -> String:
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, _upgrade_type)
	var at_max := state.current_cap > 0 and state.level >= state.current_cap
	if at_max:
		return ""
	var currency_name := _get_currency_name(Enums.currency_for_board(_board_type))
	# var level_text := "Lv %d → %d" % [state.level, state.level + 1]
	# if state.current_cap > 0:
	# 	level_text += " (max %d)" % state.current_cap
	return "Cost: %d %s" % [state.cost, currency_name]

func _get_cap_raise_hover_text() -> String:
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, _upgrade_type)
	var cap_cost := UpgradeManager.get_cap_raise_cost(_board_type, _upgrade_type)
	var cap_currency: int = Enums.cap_raise_currency_for_board(_board_type)
	var currency_name := _get_currency_name(cap_currency)
	return "Cost: %d %s  |  Cap %d → %d" % [cap_cost, currency_name, state.current_cap, state.current_cap + 1]
