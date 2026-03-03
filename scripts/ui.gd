extends CanvasLayer

signal upgrade_pressed

@onready var coin_label: Label = $CoinLabel
@onready var upgrade_button: Button = $UpgradePanel/VBoxContainer/UpgradeButton
@onready var cost_label: Label = $UpgradePanel/VBoxContainer/CostLabel


func _ready() -> void:
	upgrade_button.pressed.connect(func(): upgrade_pressed.emit())


func update_coins(total: int) -> void:
	coin_label.text = "Coins: " + str(total)


func update_upgrade(cost: int) -> void:
	cost_label.text = "Cost: " + str(cost)
