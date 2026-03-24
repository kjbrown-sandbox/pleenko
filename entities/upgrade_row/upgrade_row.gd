extends MarginContainer

signal hover_info_changed(text: String)

@onready var fill_bar = $FillBar

var _board_type: Enums.BoardType
var _upgrade_type: Enums.UpgradeType
var _callback: Callable
var _currency_type: int = -1

func setup(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType, on_upgrade: Callable) -> void:
	_board_type = board_type
	_upgrade_type = upgrade_type
	_callback = on_upgrade
	_currency_type = Enums.currency_for_board(_board_type)

func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	fill_bar.setup(t.button_enabled_color, t.button_disabled_color)

	_update_button()

	fill_bar.main_pressed.connect(_on_pressed)
	fill_bar.main_mouse_entered.connect(_on_mouse_entered)
	fill_bar.main_mouse_exited.connect(_on_mouse_exited)
	fill_bar.cap_pressed.connect(_on_cap_raise_pressed)
	fill_bar.cap_mouse_entered.connect(_on_cap_raise_mouse_entered)
	fill_bar.cap_mouse_exited.connect(_on_cap_raise_mouse_exited)
	CurrencyManager.currency_changed.connect(_on_currency_changed)
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	UpgradeManager.cap_raise_unlocked.connect(_on_cap_raise_unlocked)

	_update_cap_raise_visibility()


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
	var show := state.base_cap > 0 and UpgradeManager.is_cap_raise_available(_board_type)
	fill_bar.show_cap_button(show)

func _update_button() -> void:
	var data: BaseUpgradeData = UpgradeManager.get_upgrade(_upgrade_type)
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, _upgrade_type)
	var at_max := state.current_cap > 0 and state.level >= state.current_cap

	var display_text: String
	if at_max:
		display_text = "%s (MAX)" % data.display_name
	else:
		display_text = "%s" % [data.display_name]

	fill_bar.update_text(display_text)

	# Update fill percent
	if at_max:
		fill_bar.set_fill(1.0)
	elif state.cost > 0:
		var balance: int = CurrencyManager.get_balance(Enums.currency_for_board(_board_type))
		fill_bar.set_fill(clampf(float(balance) / float(state.cost), 0.0, 1.0))
	else:
		fill_bar.set_fill(0.0)

	var is_disabled := not UpgradeManager.can_buy(_board_type, _upgrade_type)
	fill_bar.set_main_disabled(is_disabled)
	fill_bar.apply_fill_colors(is_disabled, at_max)

	if fill_bar.cap_button.visible:
		var can_raise := UpgradeManager.can_buy_cap_raise(_board_type, _upgrade_type)
		fill_bar.set_cap_disabled(not can_raise)
		fill_bar.set_cap_filled(can_raise)


func _on_mouse_entered() -> void:
	if not fill_bar.main_button.disabled:
		fill_bar.apply_fill_colors(false)
	fill_bar.pulse_main(1.005)
	hover_info_changed.emit(_get_purchase_hover_text())

func _on_mouse_exited() -> void:
	if not fill_bar.main_button.disabled:
		fill_bar.apply_fill_colors(false)
	hover_info_changed.emit("")

func _on_cap_raise_mouse_entered() -> void:
	hover_info_changed.emit(_get_cap_raise_hover_text())
	fill_bar.pulse_cap()

func _on_cap_raise_mouse_exited() -> void:
	hover_info_changed.emit("")

func _get_currency_name(currency_type: int) -> String:
	return Enums.CurrencyType.keys()[currency_type].to_lower().replace("_", " ").replace(" coin", "")

func _get_purchase_hover_text() -> String:
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, _upgrade_type)
	var at_max := state.current_cap > 0 and state.level >= state.current_cap
	if at_max:
		return ""
	var currency_name := _get_currency_name(Enums.currency_for_board(_board_type))
	return "Cost: %d %s" % [state.cost, currency_name]

func _get_cap_raise_hover_text() -> String:
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, _upgrade_type)
	var cap_cost := UpgradeManager.get_cap_raise_cost(_board_type, _upgrade_type)
	var cap_currency: int = Enums.cap_raise_currency_for_board(_board_type)
	var currency_name := _get_currency_name(cap_currency)
	return "Cost: %d %s  |  Cap %d → %d" % [cap_cost, currency_name, state.current_cap, state.current_cap + 1]
