extends HBoxContainer

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
	_apply_outline_style(purchase_button)

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

	# Clip container for the fill
	_fill_clip = Control.new()
	_fill_clip.clip_contents = true
	_fill_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fill_clip.offset_left = inset
	_fill_clip.offset_top = inset
	_fill_clip.offset_right = -inset
	_fill_clip.offset_bottom = -inset
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

	# Cap raise button — standard themed button
	t.apply_button_theme(cap_raise_button)

	purchase_button.focus_mode = Control.FOCUS_NONE
	cap_raise_button.focus_mode = Control.FOCUS_NONE
	_update_button()
	purchase_button.pressed.connect(_on_pressed)
	purchase_button.mouse_entered.connect(_on_mouse_entered)
	purchase_button.mouse_exited.connect(_on_mouse_exited)
	cap_raise_button.pressed.connect(_on_cap_raise_pressed)
	cap_raise_button.mouse_entered.connect(_on_hover.bind(cap_raise_button))
	CurrencyManager.currency_changed.connect(_on_currency_changed)
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	UpgradeManager.cap_raise_unlocked.connect(_on_cap_raise_unlocked)

	_update_cap_raise_visibility()


func _apply_outline_style(button: Button) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var border_col := t.button_enabled_color
	var disabled_border := t.button_disabled_color

	var normal_style := t._make_stylebox(Color.TRANSPARENT, border_col)
	var hover_style := t._make_stylebox(Color.TRANSPARENT, t.button_hovered_color)
	var disabled_style := t._make_stylebox(Color.TRANSPARENT, disabled_border)

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", hover_style)
	button.add_theme_stylebox_override("disabled", disabled_style)
	button.add_theme_font_size_override("font_size", t.button_font_size)
	var btn_font: Font = t.button_font if t.button_font else t.label_font
	if btn_font:
		button.add_theme_font_override("font", btn_font)


func _on_pressed() -> void:
	_callback.call()
	_update_button()

func _on_cap_raise_pressed() -> void:
	UpgradeManager.buy_cap_raise(_board_type, _upgrade_type)
	_update_button()

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

func _update_button() -> void:
	var data: BaseUpgradeData = UpgradeManager.get_upgrade(_upgrade_type)
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, _upgrade_type)
	var at_max := state.current_cap > 0 and state.level >= state.current_cap

	var display_text: String
	if at_max:
		display_text = "%s (MAX)" % data.display_name
	else:
		var currency_name: String = Enums.CurrencyType.keys()[Enums.currency_for_board(_board_type)].to_lower().replace("_", " ")
		display_text = "%s — %d %s (Lv %d)" % [data.display_name, state.cost, currency_name, state.level]

	purchase_button.text = display_text
	_base_label.text = display_text
	_fill_label.text = display_text

	_update_fill(state)

	var is_disabled := not UpgradeManager.can_buy(_board_type, _upgrade_type)
	purchase_button.disabled = is_disabled
	_apply_fill_colors(is_disabled)

	if cap_raise_button.visible:
		var cap_cost := UpgradeManager.get_cap_raise_cost(_board_type, _upgrade_type)
		cap_raise_button.text = "+ (%d)" % cap_cost
		cap_raise_button.disabled = not UpgradeManager.can_buy_cap_raise(_board_type, _upgrade_type)


func _apply_fill_colors(is_disabled: bool) -> void:
	var t: VisualTheme = ThemeProvider.theme
	if is_disabled:
		_fill_rect.color = t.button_disabled_color
		_base_label.add_theme_color_override("font_color", t.normal_text_color.darkened(0.4))
		_fill_label.add_theme_color_override("font_color", t.background_color.darkened(0.2))
	elif _is_hovered:
		_fill_rect.color = t.button_hovered_color
		_base_label.add_theme_color_override("font_color", t.normal_text_color)
		_fill_label.add_theme_color_override("font_color", t.background_color)
	else:
		_fill_rect.color = t.button_enabled_color
		_base_label.add_theme_color_override("font_color", t.normal_text_color)
		_fill_label.add_theme_color_override("font_color", t.background_color)


func _sync_fill_label_size() -> void:
	if not _fill_label or not _base_label:
		return
	_fill_label.size = _base_label.size
	_fill_label.position = Vector2.ZERO


func _update_fill(state: UpgradeManager.UpgradeState) -> void:
	if not _fill_clip:
		return
	var fill_percent := 0.0
	if state.current_cap > 0:
		fill_percent = clampf(float(state.level) / float(state.current_cap), 0.0, 1.0)
	_fill_clip.anchor_right = fill_percent
	_fill_clip.offset_right = 0


func _on_mouse_entered() -> void:
	_is_hovered = true
	if not purchase_button.disabled:
		_apply_fill_colors(false)

func _on_mouse_exited() -> void:
	_is_hovered = false
	if not purchase_button.disabled:
		_apply_fill_colors(false)


func _on_hover(button: Button) -> void:
	if button.disabled:
		return
	var t: VisualTheme = ThemeProvider.theme
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * t.button_pulse_scale, t.button_pulse_duration * 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(button, "scale", Vector2.ONE, t.button_pulse_duration * 0.6) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
