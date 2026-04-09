class_name UpgradeRow
extends MarginContainer

signal hover_info_changed(text: String)

@onready var fill_bar = $FillBar

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
	fill_bar.setup(t.button_enabled_color, t.button_disabled_color)

	_update_button()

	fill_bar.main_pressed.connect(_on_pressed)
	fill_bar.main_mouse_entered.connect(_on_mouse_entered)
	fill_bar.main_mouse_exited.connect(_on_mouse_exited)
	fill_bar.side_button_hover.connect(_on_side_button_hover)
	CurrencyManager.currency_changed.connect(_on_currency_changed)
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)


func start_attention() -> void:
	_needs_attention = true
	fill_bar.set_attention(true)


func setup_plus(on_pressed: Callable, on_hover: Callable = Callable(), on_update: Callable = Callable()) -> void:
	fill_bar.setup_plus(on_pressed, on_hover, on_update)


func setup_minus(on_pressed: Callable, on_hover: Callable = Callable(), on_update: Callable = Callable()) -> void:
	fill_bar.setup_minus(on_pressed, on_hover, on_update)


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
		var balance: int = CurrencyManager.get_balance(TierRegistry.primary_currency(_board_type))
		fill_bar.set_fill(clampf(float(balance) / float(state.cost), 0.0, 1.0))
	else:
		fill_bar.set_fill(0.0)

	var is_disabled: bool = not UpgradeManager.can_buy(_board_type, _upgrade_type)
	fill_bar.set_main_disabled(is_disabled)
	fill_bar.apply_fill_colors(is_disabled, at_max)

	fill_bar.update_plus()
	fill_bar.update_minus()


func _on_mouse_entered() -> void:
	if _needs_attention:
		_needs_attention = false
		fill_bar.set_attention(false)
	if not fill_bar.main_button.disabled:
		fill_bar.apply_fill_colors(false)
	fill_bar.pulse_main(1.005)
	hover_info_changed.emit(_get_purchase_hover_text())

func _on_mouse_exited() -> void:
	if not fill_bar.main_button.disabled:
		fill_bar.apply_fill_colors(false)
	hover_info_changed.emit("")


func _get_currency_name(currency_type: int) -> String:
	return FormatUtils.currency_name(currency_type, false)

func _get_purchase_hover_text() -> String:
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, _upgrade_type)
	var at_max: bool = state.current_cap > 0 and state.level >= state.current_cap
	if at_max:
		return ""
	var currency_name: String = _get_currency_name(TierRegistry.primary_currency(_board_type))
	return "Cost: %s %s" % [FormatUtils.format_number(state.cost), currency_name]
