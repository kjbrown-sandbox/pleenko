extends CanvasLayer

signal upgrade_pressed
signal orange_upgrade_pressed

@onready var coin_label: Label = $CoinLabel
@onready var orange_coin_label: Label = $OrangeCoinLabel
@onready var upgrade_button: Button = $UpgradePanel/VBoxContainer/UpgradeButton
@onready var cost_label: Label = $UpgradePanel/VBoxContainer/CostLabel
@onready var orange_upgrade_panel: PanelContainer = $OrangeUpgradePanel
@onready var orange_upgrade_button: Button = $OrangeUpgradePanel/VBoxContainer/UpgradeButton
@onready var orange_cost_label: Label = $OrangeUpgradePanel/VBoxContainer/CostLabel


func _ready() -> void:
	upgrade_button.pressed.connect(func(): upgrade_pressed.emit())
	orange_upgrade_button.pressed.connect(func(): orange_upgrade_pressed.emit())


func update_coins(total: int) -> void:
	coin_label.text = "Coins: " + str(total)


func update_upgrade(cost: int) -> void:
	cost_label.text = "Cost: " + str(cost)


func update_orange_coins(total: int) -> void:
	orange_coin_label.text = "Orange: " + str(total)


func update_orange_upgrade(cost: int) -> void:
	orange_cost_label.text = "Cost: " + str(cost)


func show_orange_panel() -> void:
	orange_coin_label.visible = true
	orange_upgrade_panel.visible = true
