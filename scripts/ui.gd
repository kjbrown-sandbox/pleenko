extends CanvasLayer

signal upgrade_pressed
signal orange_upgrade_pressed
signal red_upgrade_pressed
signal autodropper_pressed
signal gold_bonus_pressed
signal gold_row_cap_pressed
signal orange_row_cap_pressed
signal auto_cap_pressed

@onready var coin_label: Label = $CoinLabel
@onready var orange_coin_label: Label = $OrangeCoinLabel
@onready var red_coin_label: Label = $RedCoinLabel

@onready var upgrade_button: Button = $UpgradePanel/VBoxContainer/UpgradeButton
@onready var cost_label: Label = $UpgradePanel/VBoxContainer/CostLabel

@onready var orange_upgrade_panel: PanelContainer = $OrangeUpgradePanel
@onready var orange_upgrade_button: Button = $OrangeUpgradePanel/VBoxContainer/UpgradeButton
@onready var orange_cost_label: Label = $OrangeUpgradePanel/VBoxContainer/CostLabel
@onready var orange_countdown_label: Label = $OrangeUpgradePanel/VBoxContainer/OrangeCountdownLabel
@onready var orange_queue_label: Label = $OrangeUpgradePanel/VBoxContainer/OrangeQueueLabel
@onready var autodropper_button: Button = $OrangeUpgradePanel/VBoxContainer/AutodropperButton
@onready var autodropper_cost_label: Label = $OrangeUpgradePanel/VBoxContainer/AutodropperCostLabel
@onready var gold_bonus_button: Button = $OrangeUpgradePanel/VBoxContainer/GoldBonusButton
@onready var gold_bonus_cost_label: Label = $OrangeUpgradePanel/VBoxContainer/GoldBonusCostLabel

@onready var red_upgrade_panel: PanelContainer = $RedUpgradePanel
@onready var red_add_row_button: Button = $RedUpgradePanel/VBoxContainer/RedAddRowButton
@onready var red_cost_label: Label = $RedUpgradePanel/VBoxContainer/RedCostLabel
@onready var gold_row_cap_button: Button = $RedUpgradePanel/VBoxContainer/GoldRowCapButton
@onready var gold_row_cap_cost_label: Label = $RedUpgradePanel/VBoxContainer/GoldRowCapCostLabel
@onready var orange_row_cap_button: Button = $RedUpgradePanel/VBoxContainer/OrangeRowCapButton
@onready var orange_row_cap_cost_label: Label = $RedUpgradePanel/VBoxContainer/OrangeRowCapCostLabel
@onready var auto_cap_button: Button = $RedUpgradePanel/VBoxContainer/AutoCapButton
@onready var auto_cap_cost_label: Label = $RedUpgradePanel/VBoxContainer/AutoCapCostLabel


func _ready() -> void:
	upgrade_button.pressed.connect(func(): upgrade_pressed.emit())
	orange_upgrade_button.pressed.connect(func(): orange_upgrade_pressed.emit())
	red_add_row_button.pressed.connect(func(): red_upgrade_pressed.emit())
	autodropper_button.pressed.connect(func(): autodropper_pressed.emit())
	gold_bonus_button.pressed.connect(func(): gold_bonus_pressed.emit())
	gold_row_cap_button.pressed.connect(func(): gold_row_cap_pressed.emit())
	orange_row_cap_button.pressed.connect(func(): orange_row_cap_pressed.emit())
	auto_cap_button.pressed.connect(func(): auto_cap_pressed.emit())


func update_coins(total: int) -> void:
	coin_label.text = "Gold: " + str(total)


func update_upgrade(cost: int) -> void:
	cost_label.text = "Cost: " + str(cost)


func update_orange_coins(total: int) -> void:
	orange_coin_label.text = "Orange: " + str(total)


func update_orange_upgrade(cost: int) -> void:
	orange_cost_label.text = "Cost: " + str(cost)


func update_red_coins(total: int) -> void:
	red_coin_label.text = "Red: " + str(total)


func update_red_upgrade(cost: int) -> void:
	red_cost_label.text = "Cost: " + str(cost)


func update_autodropper(cost: int, level: int, cap: int) -> void:
	autodropper_cost_label.text = "Cost: " + str(cost) + " | Lvl: " + str(level) + " | Cap: " + str(cap)


func update_gold_bonus(cost: int, level: int) -> void:
	gold_bonus_cost_label.text = "Cost: " + str(cost) + " | Lvl: " + str(level)


func update_gold_row_cap(cost: int, cap: int) -> void:
	gold_row_cap_cost_label.text = "Cost: " + str(cost) + " | Cap: " + str(cap)


func update_orange_row_cap(cost: int, cap: int) -> void:
	orange_row_cap_cost_label.text = "Cost: " + str(cost) + " | Cap: " + str(cap)


func update_auto_cap(cost: int, cap: int) -> void:
	auto_cap_cost_label.text = "Cost: " + str(cost) + " | Cap: " + str(cap)


func update_orange_queue(current: int, max_val: int) -> void:
	orange_queue_label.text = "Queue: " + str(current) + "/" + str(max_val)


func update_orange_countdown(text: String) -> void:
	orange_countdown_label.text = text


func show_orange_panel() -> void:
	orange_coin_label.visible = true
	orange_upgrade_panel.visible = true


func show_red_panel() -> void:
	red_coin_label.visible = true
	red_upgrade_panel.visible = true
