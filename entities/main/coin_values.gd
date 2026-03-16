extends VBoxContainer

var _cap_buttons: Dictionary = {}  # CurrencyType -> Button
var _labels: Dictionary = {}  # CurrencyType -> Label
var _visible_currencies: Array[Enums.CurrencyType] = [Enums.CurrencyType.GOLD_COIN]

var _board_manager: BoardManager

func setup(board_manager: BoardManager) -> void:
	_board_manager = board_manager

	# Check if any boards are already unlocked
	for currency_type in Enums.CurrencyType.values():
		if not _visible_currencies.has(currency_type) and _is_board_for_coin_type_unlocked(currency_type):
			_visible_currencies.append(currency_type)

	_visible_currencies.sort()
	_update_currencies()

func _ready() -> void:
	CurrencyManager.currency_changed.connect(_on_currency_changed)
	UpgradeManager.cap_raise_unlocked.connect(_on_cap_raise_unlocked)

	# Check if any cap raises are already available
	_update_all_cap_buttons()


func _on_currency_changed(type: Enums.CurrencyType, new_balance: int, cap: int) -> void:
	# Check if new currencies should become visible
	if not _visible_currencies.has(type) and _is_board_for_coin_type_unlocked(type):
		_visible_currencies.append(type)
		_visible_currencies.sort()
		_update_currencies()

	# Update the label if this currency has a row
	var label: Label = _labels.get(type)
	if label:
		var coin_name = Enums.CurrencyType.keys()[type]
		label.text = "%s: %d / %d" % [coin_name, new_balance, cap]
		if new_balance >= cap:
			label.add_theme_color_override("font_color", Color(1, 0.15, 0.15))
		else:
			label.add_theme_color_override("font_color", Color(1, 1, 1))

	_update_all_cap_buttons()


func _is_board_for_coin_type_unlocked(coin_type: Enums.CurrencyType) -> bool:
	match coin_type:
		Enums.CurrencyType.ORANGE_COIN, Enums.CurrencyType.RAW_ORANGE:
			return _board_manager.is_board_unlocked(Enums.BoardType.ORANGE)
		Enums.CurrencyType.RED_COIN, Enums.CurrencyType.RAW_RED:
			return _board_manager.is_board_unlocked(Enums.BoardType.RED)
		_:
			return true


func _update_currencies() -> void:
	# Clear existing rows and references
	for child in get_children():
		child.queue_free()
	_cap_buttons.clear()
	_labels.clear()

	# Rebuild from _visible_currencies
	for currency_type in _visible_currencies:
		var row := HBoxContainer.new()

		var label := Label.new()
		var amount = CurrencyManager.get_balance(currency_type)
		var cap = CurrencyManager.get_cap(currency_type)
		var coin_name = Enums.CurrencyType.keys()[currency_type]
		label.text = "%s: %d / %d" % [coin_name, amount, cap]
		row.add_child(label)
		_labels[currency_type] = label

		var cap_button := Button.new()
		cap_button.visible = false
		cap_button.pressed.connect(_on_cap_raise_pressed.bind(currency_type))
		row.add_child(cap_button)
		_cap_buttons[currency_type] = cap_button

		add_child(row)

	_update_all_cap_buttons()


func refresh_visible_currencies() -> void:
	var changed := false
	for currency_type in Enums.CurrencyType.values():
		if not _visible_currencies.has(currency_type) and _is_board_for_coin_type_unlocked(currency_type):
			_visible_currencies.append(currency_type)
			changed = true
	if changed:
		# Re-sort to match enum definition order
		_visible_currencies.sort()
		_update_currencies()


func _on_cap_raise_unlocked(_board_type: Enums.BoardType) -> void:
	_update_all_cap_buttons()


func _on_cap_raise_pressed(type: Enums.CurrencyType) -> void:
	CurrencyManager.buy_cap_raise(type)


func _update_all_cap_buttons() -> void:
	for currency_type in _cap_buttons:
		var button: Button = _cap_buttons[currency_type]
		var board: int = CurrencyManager.cap_raise_board(currency_type)
		button.visible = board != -1 and UpgradeManager.is_cap_raise_available(board)
		if button.visible:
			var cost := CurrencyManager.get_cap_raise_cost(currency_type)
			var raise_amount := CurrencyManager.cap_raise_amount(currency_type)
			button.text = "+%d (%d)" % [raise_amount, cost]
			button.disabled = not CurrencyManager.can_buy_cap_raise(currency_type)
