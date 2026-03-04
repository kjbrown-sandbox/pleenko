extends CanvasLayer

signal upgrade_pressed
signal orange_upgrade_pressed
signal red_upgrade_pressed
signal autodropper_pressed
signal orange_drop_rate_pressed
signal orange_queue_up_pressed
signal bucket_value_pressed
signal drop_rate_pressed
signal row_cap_pressed
signal value_cap_pressed
signal rate_cap_pressed
signal auto_cap_pressed

@onready var coin_label: Label = $CoinLabel
@onready var orange_coin_label: Label = $OrangeCoinLabel
@onready var red_coin_label: Label = $RedCoinLabel

@onready var level_progress_bar: ProgressBar = $LevelProgressBar
@onready var level_progress_label: Label = $LevelProgressLabel
@onready var level_label: Label = $UpgradePanel/VBoxContainer/LevelLabel
@onready var upgrade_button: Button = $UpgradePanel/VBoxContainer/UpgradeButton
@onready var cost_label: Label = $UpgradePanel/VBoxContainer/CostLabel
@onready var bucket_value_button: Button = $UpgradePanel/VBoxContainer/BucketValueButton
@onready var bucket_value_cost_label: Label = $UpgradePanel/VBoxContainer/BucketValueCostLabel
@onready var drop_rate_button: Button = $UpgradePanel/VBoxContainer/DropRateButton
@onready var drop_rate_cost_label: Label = $UpgradePanel/VBoxContainer/DropRateCostLabel
@onready var autodropper_button: Button = $UpgradePanel/VBoxContainer/AutodropperButton
@onready var autodropper_cost_label: Label = $UpgradePanel/VBoxContainer/AutodropperCostLabel

@onready var orange_upgrade_panel: PanelContainer = $OrangeUpgradePanel
@onready var orange_upgrade_button: Button = $OrangeUpgradePanel/VBoxContainer/UpgradeButton
@onready var orange_cost_label: Label = $OrangeUpgradePanel/VBoxContainer/CostLabel
@onready var orange_countdown_label: Label = $OrangeUpgradePanel/VBoxContainer/OrangeCountdownLabel
@onready var orange_queue_label: Label = $OrangeUpgradePanel/VBoxContainer/OrangeQueueLabel
@onready var orange_drop_rate_button: Button = $OrangeUpgradePanel/VBoxContainer/OrangeDropRateButton
@onready var orange_drop_rate_cost_label: Label = $OrangeUpgradePanel/VBoxContainer/OrangeDropRateCostLabel
@onready var orange_queue_up_button: Button = $OrangeUpgradePanel/VBoxContainer/OrangeQueueUpButton
@onready var orange_queue_up_cost_label: Label = $OrangeUpgradePanel/VBoxContainer/OrangeQueueUpCostLabel
@onready var row_cap_button: Button = $OrangeUpgradePanel/VBoxContainer/RowCapButton
@onready var row_cap_cost_label: Label = $OrangeUpgradePanel/VBoxContainer/RowCapCostLabel
@onready var value_cap_button: Button = $OrangeUpgradePanel/VBoxContainer/ValueCapButton
@onready var value_cap_cost_label: Label = $OrangeUpgradePanel/VBoxContainer/ValueCapCostLabel
@onready var rate_cap_button: Button = $OrangeUpgradePanel/VBoxContainer/RateCapButton
@onready var rate_cap_cost_label: Label = $OrangeUpgradePanel/VBoxContainer/RateCapCostLabel
@onready var auto_cap_button: Button = $OrangeUpgradePanel/VBoxContainer/AutoCapButton
@onready var auto_cap_cost_label: Label = $OrangeUpgradePanel/VBoxContainer/AutoCapCostLabel

@onready var red_upgrade_panel: PanelContainer = $RedUpgradePanel
@onready var red_countdown_label: Label = $RedUpgradePanel/VBoxContainer/RedCountdownLabel
@onready var red_queue_label: Label = $RedUpgradePanel/VBoxContainer/RedQueueLabel
@onready var red_add_row_button: Button = $RedUpgradePanel/VBoxContainer/RedAddRowButton
@onready var red_cost_label: Label = $RedUpgradePanel/VBoxContainer/RedCostLabel


func _ready() -> void:
	upgrade_button.pressed.connect(func(): upgrade_pressed.emit())
	orange_upgrade_button.pressed.connect(func(): orange_upgrade_pressed.emit())
	red_add_row_button.pressed.connect(func(): red_upgrade_pressed.emit())
	autodropper_button.pressed.connect(func(): autodropper_pressed.emit())
	orange_drop_rate_button.pressed.connect(func(): orange_drop_rate_pressed.emit())
	orange_queue_up_button.pressed.connect(func(): orange_queue_up_pressed.emit())
	bucket_value_button.pressed.connect(func(): bucket_value_pressed.emit())
	drop_rate_button.pressed.connect(func(): drop_rate_pressed.emit())
	row_cap_button.pressed.connect(func(): row_cap_pressed.emit())
	value_cap_button.pressed.connect(func(): value_cap_pressed.emit())
	rate_cap_button.pressed.connect(func(): rate_cap_pressed.emit())
	auto_cap_button.pressed.connect(func(): auto_cap_pressed.emit())


func update_coins(total: int) -> void:
	coin_label.text = "Gold: " + str(total)


func update_upgrade(cost: int, rows: int, cap: int) -> void:
	cost_label.text = "Cost: " + str(cost) + " | Rows: " + str(rows) + "/" + str(cap)


func update_orange_coins(total: int) -> void:
	orange_coin_label.text = "Orange: " + str(total)


func update_orange_upgrade(cost: int) -> void:
	orange_cost_label.text = "Cost: " + str(cost)


func update_orange_queue(current: int, max_val: int) -> void:
	orange_queue_label.text = "Queue: " + str(current) + "/" + str(max_val)


func update_orange_countdown(text: String) -> void:
	orange_countdown_label.text = text


func update_red_coins(total: int) -> void:
	red_coin_label.text = "Red: " + str(total)


func update_red_upgrade(cost: int) -> void:
	red_cost_label.text = "Cost: " + str(cost)


func update_red_queue(current: int, max_val: int) -> void:
	red_queue_label.text = "Queue: " + str(current) + "/" + str(max_val)


func update_red_countdown(text: String) -> void:
	red_countdown_label.text = text


func update_autodropper(cost: int, level: int, cap: int) -> void:
	autodropper_cost_label.text = "Cost: " + str(cost) + " | Lvl: " + str(level) + "/" + str(cap)


func update_orange_drop_rate(cost: int, rate: float) -> void:
	orange_drop_rate_cost_label.text = "Cost: " + str(cost) + " | Rate: " + str(snapped(rate, 0.01)) + "s"


func update_orange_queue_up(cost: int, queue_max: int) -> void:
	orange_queue_up_cost_label.text = "Cost: " + str(cost) + " | Queue: " + str(queue_max)


func update_level(level: int, next_threshold: int) -> void:
	if next_threshold > 0:
		level_label.text = "Level: " + str(level) + " (next: " + str(next_threshold) + ")"
	else:
		level_label.text = "Level: " + str(level) + " (max)"


func update_level_progress(current: int, next_threshold: int) -> void:
	if next_threshold <= 0:
		# Max level — fill the bar
		level_progress_bar.max_value = 1.0
		level_progress_bar.value = 1.0
		level_progress_label.text = "MAX"
	else:
		level_progress_bar.min_value = 0.0
		level_progress_bar.max_value = next_threshold
		level_progress_bar.value = mini(current, next_threshold)
		level_progress_label.text = str(current) + "/" + str(next_threshold)


func show_add_row() -> void:
	upgrade_button.visible = true
	cost_label.visible = true


func show_bucket_value() -> void:
	bucket_value_button.visible = true
	bucket_value_cost_label.visible = true


func update_bucket_value(cost: int, level: int, cap: int) -> void:
	bucket_value_cost_label.text = "Cost: " + str(cost) + " | Lvl: " + str(level) + "/" + str(cap)


func show_drop_rate() -> void:
	drop_rate_button.visible = true
	drop_rate_cost_label.visible = true


func update_drop_rate(cost: int, rate: float, level: int, cap: int) -> void:
	drop_rate_cost_label.text = "Cost: " + str(cost) + " | Rate: " + str(snapped(rate, 0.01)) + "s | Lvl: " + str(level) + "/" + str(cap)


func show_autodropper() -> void:
	autodropper_button.visible = true
	autodropper_cost_label.visible = true


func update_row_cap(cost: int, cap: int) -> void:
	row_cap_cost_label.text = "Cost: " + str(cost) + " | Cap: " + str(cap)


func update_value_cap(cost: int, cap: int) -> void:
	value_cap_cost_label.text = "Cost: " + str(cost) + " | Cap: " + str(cap)


func update_rate_cap(cost: int, cap: int) -> void:
	rate_cap_cost_label.text = "Cost: " + str(cost) + " | Cap: " + str(cap)


func update_auto_cap(cost: int, cap: int) -> void:
	auto_cap_cost_label.text = "Cost: " + str(cost) + " | Cap: " + str(cap)


func show_orange_panel() -> void:
	orange_coin_label.visible = true
	orange_upgrade_panel.visible = true


func show_red_panel() -> void:
	red_coin_label.visible = true
	red_upgrade_panel.visible = true
