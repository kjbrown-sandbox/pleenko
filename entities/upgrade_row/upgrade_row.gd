class_name UpgradeRow
extends MarginContainer

signal hover_info_changed(text: String)

@onready var bar = $Bar

var _board_type: Enums.BoardType
var _upgrade_type: Enums.UpgradeType
var _callback: Callable
var _currency_type: int = -1
var _dirty := false
var _needs_attention := false

func setup(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType, on_upgrade: Callable) -> void:
	_board_type = board_type
	_upgrade_type = upgrade_type
	_callback = on_upgrade
	_currency_type = TierRegistry.primary_currency(_board_type)

func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	bar.setup(t.button_enabled_color, t.button_disabled_color)

	_update_button()

	bar.main_pressed.connect(_on_pressed)
	bar.main_mouse_entered.connect(_on_mouse_entered)
	bar.main_mouse_exited.connect(_on_mouse_exited)
	bar.side_button_hover.connect(_on_side_button_hover)
	CurrencyManager.currency_changed.connect(_on_currency_changed)
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)


func start_attention() -> void:
	_needs_attention = true
	bar.set_attention(true)


## Clip-reveal animation: slides the row in from left to right inside its
## parent VBoxContainer, then calls start_attention().
func materialize() -> void:
	visible = true
	var container: Control = get_parent()
	var idx: int = get_index()
	container.remove_child(self)

	var wrapper := Control.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(wrapper)
	container.move_child(wrapper, idx)

	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(clip)
	clip.add_child(self)

	_animate_clip_reveal.call_deferred(container, wrapper, clip)


func _animate_clip_reveal(container: Control, wrapper: Control, clip: Control) -> void:
	var target_width: float = container.size.x
	var row_height: float = size.y

	wrapper.custom_minimum_size.y = row_height
	position = Vector2.ZERO
	size = Vector2(target_width, row_height)
	clip.size = Vector2(0, row_height)

	var t: VisualTheme = ThemeProvider.theme
	var tween := clip.create_tween()
	tween.tween_property(clip, "size:x", target_width, t.upgrade_materialize_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		var i: int = wrapper.get_index()
		clip.remove_child(self)
		container.remove_child(wrapper)
		container.add_child(self)
		container.move_child(self, i)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrapper.queue_free()
		start_attention()
	)


func setup_plus(on_pressed: Callable, on_hover: Callable = Callable(), on_update: Callable = Callable()) -> void:
	bar.setup_plus(on_pressed, on_hover, on_update)


func setup_minus(on_pressed: Callable, on_hover: Callable = Callable(), on_update: Callable = Callable()) -> void:
	bar.setup_minus(on_pressed, on_hover, on_update)


func _on_pressed() -> void:
	_callback.call()
	_update_button()
	hover_info_changed.emit(_get_purchase_hover_text())


func _on_currency_changed(type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
	if type != _currency_type:
		return
	if not _dirty:
		_dirty = true
		_deferred_update.call_deferred()


func _deferred_update() -> void:
	_dirty = false
	_update_button()


func _on_upgrade_purchased(_type: Enums.UpgradeType, _board: Enums.BoardType, _new_level: int) -> void:
	_update_button()


func _on_side_button_hover(text: String) -> void:
	hover_info_changed.emit(text)


func _update_button() -> void:
	var data: BaseUpgradeData = UpgradeManager.get_upgrade(_upgrade_type)
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, _upgrade_type)
	var at_max: bool = state.current_cap > 0 and state.level >= state.current_cap

	bar.update_text(data.display_name)
	# Right-side text: "level/cap". When the upgrade has no cap (e.g. unlimited
	# / unreachable here), num is empty and title centers across the whole bar.
	# A full bar reads as MAX visually, no "(MAX)" suffix needed.
	if state.current_cap > 0:
		bar.num_text = "%d/%d" % [state.level, state.current_cap]
	else:
		bar.num_text = ""

	# Update fill percent
	if at_max:
		bar.set_fill(1.0)
	elif state.cost > 0:
		var balance: int = CurrencyManager.get_balance(TierRegistry.primary_currency(_board_type))
		bar.set_fill(clampf(float(balance) / float(state.cost), 0.0, 1.0))
	else:
		bar.set_fill(0.0)

	var is_disabled: bool = not UpgradeManager.can_buy(_board_type, _upgrade_type)
	bar.set_main_disabled(is_disabled)
	bar.apply_fill_colors(is_disabled, at_max)

	bar.update_plus()
	bar.update_minus()


func _on_mouse_entered() -> void:
	if _needs_attention:
		_needs_attention = false
		bar.set_attention(false)
	if not bar.main_button.disabled:
		bar.apply_fill_colors(false)
	bar.pulse_main(1.005)
	hover_info_changed.emit(_get_purchase_hover_text())

func _on_mouse_exited() -> void:
	if not bar.main_button.disabled:
		bar.apply_fill_colors(false)
	hover_info_changed.emit("")


func _get_currency_name(currency_type: int) -> String:
	return FormatUtils.currency_name(currency_type, false)

func _get_purchase_hover_text() -> String:
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, _upgrade_type)
	var at_max: bool = state.current_cap > 0 and state.level >= state.current_cap
	if at_max:
		return ""
	var currency_name: String = _get_currency_name(TierRegistry.primary_currency(_board_type))
	var text := "Cost: %s %s" % [FormatUtils.format_number(state.cost), currency_name]
	if _upgrade_type == Enums.UpgradeType.PEG_DEFLECTOR:
		var odds := roundi(PlinkoBoard.deflector_bias_for_strength(
			PlinkoBoard.DEFLECTOR_BASE_STRENGTH) * 100.0)
		text += "\ncurrent odds: %d%%" % odds
	return text
