extends VBoxContainer

const FillBarScene := preload("res://entities/fill_bar/fill_bar.tscn")
const TooltipScene := preload("res://entities/tooltip/tooltip.tscn")

var _bars: Dictionary = {}  # CurrencyType -> FillBar node
var _visible_currencies: Array[Enums.CurrencyType] = [Enums.CurrencyType.GOLD_COIN]
var _hover_tooltip: Tooltip

var _board_manager: BoardManager

# Debounce: collapse multiple currency_changed signals into one deferred update
var _dirty := false
var _dirty_types: Array[Enums.CurrencyType] = []

func setup(board_manager: BoardManager) -> void:
	_board_manager = board_manager

	for currency_type in Enums.CurrencyType.values():
		if not _visible_currencies.has(currency_type) and _is_board_for_coin_type_unlocked(currency_type):
			_visible_currencies.append(currency_type)

	_visible_currencies.sort()
	_update_currencies()

func _ready() -> void:
	CurrencyManager.currency_changed.connect(_on_currency_changed)
	UpgradeManager.cap_raise_unlocked.connect(_on_cap_raise_unlocked)
	_update_all_bars()


func _on_currency_changed(type: Enums.CurrencyType, _new_balance: int, _cap: int) -> void:
	if not _dirty_types.has(type):
		_dirty_types.append(type)
	if not _dirty:
		_dirty = true
		_flush.call_deferred()


func _flush() -> void:
	_dirty = false

	# Check if any new currencies need to become visible
	var layout_changed := false
	for type in _dirty_types:
		if not _visible_currencies.has(type) and _is_board_for_coin_type_unlocked(type):
			_visible_currencies.append(type)
			layout_changed = true

	if layout_changed:
		_visible_currencies.sort()
		_dirty_types.clear()
		_update_currencies()
		return

	# Update only the bars that changed
	for type in _dirty_types:
		var bar = _bars.get(type)
		if bar:
			var amount := CurrencyManager.get_balance(type)
			var cap := CurrencyManager.get_cap(type)
			_update_bar(bar, type, amount, cap)

	_dirty_types.clear()
	_update_cap_button_affordability()


func _is_board_for_coin_type_unlocked(coin_type: Enums.CurrencyType) -> bool:
	var tier := TierRegistry.get_tier_for_currency(coin_type)
	if not tier:
		return true
	# Starting tier currencies are always visible
	if TierRegistry.is_starting_tier(tier.board_type):
		return true
	# Raw currencies show up as soon as you have any (earned before board unlocks)
	if TierRegistry.is_raw_currency(coin_type) and CurrencyManager.get_balance(coin_type) > 0:
		return true
	# Otherwise, the tier's board must be unlocked
	return _board_manager.is_board_unlocked(tier.board_type)


func _update_currencies() -> void:
	for child in get_children():
		child.queue_free()
	_bars.clear()
	_hover_tooltip = null

	for currency_type in _visible_currencies:
		var bar = FillBarScene.instantiate()
		add_child(bar)

		var t: VisualTheme = ThemeProvider.theme
		var fill_color: Color = t.get_coin_color(currency_type)
		var disabled_color: Color = t.get_coin_color_faded(currency_type)
		bar.setup(fill_color, disabled_color)
		bar._disabled_text_override = t.button_fill_text_color

		var amount := CurrencyManager.get_balance(currency_type)
		var cap := CurrencyManager.get_cap(currency_type)
		_update_bar(bar, currency_type, amount, cap)

		# Main bar is not clickable
		bar.main_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

		bar.plus_pressed.connect(_on_cap_raise_pressed.bind(currency_type))
		bar.plus_mouse_entered.connect(_on_cap_hover.bind(currency_type))
		bar.plus_mouse_exited.connect(_on_cap_unhover)

		_bars[currency_type] = bar

	# Hover tooltip at the bottom
	_hover_tooltip = TooltipScene.instantiate()
	_hover_tooltip.use_parent_signals = false
	_hover_tooltip.position_side = Tooltip.Placement.INLINE
	_hover_tooltip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hover_tooltip)

	_update_all_cap_buttons()


func _update_bar(bar, type: Enums.CurrencyType, balance: int, cap: int) -> void:
	var at_cap := cap > 0 and balance >= cap
	var coin_name := _get_currency_name(type)

	var fmt_balance := FormatUtils.format_number(balance)
	var fmt_cap := FormatUtils.format_number(cap)
	if at_cap:
		bar.update_text("%s %s/%s (MAX)" % [coin_name, fmt_balance, fmt_cap])
		bar.set_fill(1.0)
		bar.set_main_disabled(true)
		bar.apply_fill_colors(true, true)
	else:
		bar.update_text("%s %s/%s" % [coin_name, fmt_balance, fmt_cap])
		var fill_pct := clampf(float(balance) / float(cap), 0.0, 1.0) if cap > 0 else 0.0
		bar.set_fill(fill_pct)
		bar.set_main_disabled(false)
		bar.apply_fill_colors(false)


func _get_currency_name(type: int) -> String:
	return FormatUtils.currency_name(type)


func _on_cap_hover(type: Enums.CurrencyType) -> void:
	if not _hover_tooltip:
		return
	var cost := CurrencyManager.get_cap_raise_cost(type)
	var cap_currency: int = CurrencyManager.cap_raise_currency(type)
	var currency_name := _get_currency_name(cap_currency)
	_hover_tooltip.update_and_show("Cost: %s %s" % [FormatUtils.format_number(cost), currency_name])


func _on_cap_unhover() -> void:
	if _hover_tooltip:
		_hover_tooltip.hide_tooltip()


func refresh_visible_currencies() -> void:
	var changed := false
	for currency_type in Enums.CurrencyType.values():
		if not _visible_currencies.has(currency_type) and _is_board_for_coin_type_unlocked(currency_type):
			_visible_currencies.append(currency_type)
			changed = true
	if changed:
		_visible_currencies.sort()
		_update_currencies()
	else:
		_update_all_bars()


func _on_cap_raise_unlocked(_board_type: Enums.BoardType) -> void:
	_update_all_cap_buttons()


func _on_cap_raise_pressed(type: Enums.CurrencyType) -> void:
	CurrencyManager.buy_cap_raise(type)
	_update_all_cap_buttons()
	if _hover_tooltip and _hover_tooltip.visible:
		_on_cap_hover(type)


func _update_all_bars() -> void:
	for currency_type in _bars:
		var bar = _bars[currency_type]
		var amount := CurrencyManager.get_balance(currency_type)
		var cap := CurrencyManager.get_cap(currency_type)
		_update_bar(bar, currency_type, amount, cap)
	_update_all_cap_buttons()


func _update_all_cap_buttons() -> void:
	for currency_type in _bars:
		var bar = _bars[currency_type]
		var board: int = CurrencyManager.cap_raise_board(currency_type)
		var show := board != -1 and UpgradeManager.is_cap_raise_available(board)
		bar.show_plus_button(show)
		if show:
			var can_afford := CurrencyManager.can_buy_cap_raise(currency_type)
			bar.set_plus_disabled(not can_afford)
			bar.set_plus_filled(can_afford)


func _update_cap_button_affordability() -> void:
	for currency_type in _bars:
		var bar = _bars[currency_type]
		if not bar.plus_button.visible:
			continue
		var can_afford := CurrencyManager.can_buy_cap_raise(currency_type)
		bar.set_plus_disabled(not can_afford)
		bar.set_plus_filled(can_afford)
