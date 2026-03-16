extends HBoxContainer
@onready var purchase_upgrade_button: Button = $PurchaseUpgradeButton
@onready var cap_raise_button: Button = $CapRaiseButton

var _board_type: Enums.BoardType
var _upgrade_type: Enums.UpgradeType
var _callback: Callable

func setup(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType, on_upgrade: Callable) -> void:
	_board_type = board_type
	_upgrade_type = upgrade_type
	_callback = on_upgrade

func _ready() -> void:
	_update_button()
	purchase_upgrade_button.pressed.connect(_on_pressed)
	cap_raise_button.pressed.connect(_on_cap_raise_pressed)
	CurrencyManager.currency_changed.connect(_on_currency_changed)
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	UpgradeManager.cap_raise_unlocked.connect(_on_cap_raise_unlocked)

	# Check if cap raising is already available (board was unlocked before this row existed)
	_update_cap_raise_visibility()

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
	# Only show for capped upgrades when cap raising is available
	cap_raise_button.visible = state.base_cap > 0 and UpgradeManager.is_cap_raise_available(_board_type)

func _update_button() -> void:
	var data: BaseUpgradeData = UpgradeManager.get_upgrade(_upgrade_type)
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, _upgrade_type)
	var at_max := state.current_cap > 0 and state.level >= state.current_cap

	if at_max:
		purchase_upgrade_button.text = "%s (MAX)" % data.display_name
	else:
		var currency_name: String = Enums.CurrencyType.keys()[Enums.currency_for_board(_board_type)].to_lower().replace("_", " ")
		purchase_upgrade_button.text = "%s — %d %s (Lv %d)" % [data.display_name, state.cost, currency_name, state.level]

	purchase_upgrade_button.disabled = not UpgradeManager.can_buy(_board_type, _upgrade_type)

	# Update cap raise button state
	if cap_raise_button.visible:
		var cap_cost := UpgradeManager.get_cap_raise_cost(_board_type, _upgrade_type)
		cap_raise_button.text = "+ (%d)" % cap_cost
		cap_raise_button.disabled = not UpgradeManager.can_buy_cap_raise(_board_type, _upgrade_type)
