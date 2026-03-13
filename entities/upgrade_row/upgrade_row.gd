extends HBoxContainer
@onready var purchase_upgrade_button: Button = $PurchaseUpgradeButton

var _board_type: Enums.BoardType
var _upgrade_id: String
var _callback: Callable

func setup(board_type: Enums.BoardType, upgrade_id: String, on_upgrade: Callable) -> void:
	_board_type = board_type
	_upgrade_id = upgrade_id
	_callback = on_upgrade

func _ready() -> void:
	_update_button()
	purchase_upgrade_button.pressed.connect(_on_pressed)
	CurrencyManager.currency_changed.connect(_on_currency_changed)
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)

func _on_pressed() -> void:
	_callback.call()
	_update_button()

func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
	_update_button()

func _on_upgrade_purchased(_id: String, _type: Enums.BoardType, _new_level: int) -> void:
	_update_button()

func _update_button() -> void:
	var data: BaseUpgradeData = UpgradeManager.get_upgrade(_upgrade_id)
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, _upgrade_id)
	var at_max := state.max_level > 0 and state.level >= state.max_level

	if at_max:
		purchase_upgrade_button.text = "%s (MAX)" % data.display_name
	else:
		purchase_upgrade_button.text = "%s — %d gold (Lv %d)" % [data.display_name, state.cost, state.level]

	purchase_upgrade_button.disabled = not UpgradeManager.can_buy(_board_type, _upgrade_id)
