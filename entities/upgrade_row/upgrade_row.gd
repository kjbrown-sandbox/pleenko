extends Control
@onready var purchase_upgrade_button: Button = $PurchaseUpgradeButton

var _label: String
var _callback: Callable

func setup(upgrade_text: String, on_upgrade: Callable) -> void:
	_label = upgrade_text
	_callback = on_upgrade

func _ready() -> void:
	purchase_upgrade_button.text = _label
	purchase_upgrade_button.pressed.connect(_callback)
