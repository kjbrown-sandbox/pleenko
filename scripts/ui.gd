extends CanvasLayer

signal upgrade_action(action_name: String)
signal board_tab_selected(board_type: int)  # PlinkoBoard.BoardType value

@onready var coin_label: Label = $CoinLabel
@onready var orange_coin_label: Label = $OrangeCoinLabel
@onready var red_coin_label: Label = $RedCoinLabel

@onready var level_progress_bar: ProgressBar = $LevelProgressBar
@onready var level_progress_label: Label = $LevelProgressLabel
@onready var header_label: Label = $UpgradePanel/VBoxContainer/HeaderLabel
@onready var level_label: Label = $UpgradePanel/VBoxContainer/LevelLabel
@onready var upgrade_list: VBoxContainer = $UpgradePanel/VBoxContainer/UpgradeList
@onready var cap_cost_label: Label = $CapCostLabel
@onready var board_tabs: HBoxContainer = $UpgradePanel/VBoxContainer/BoardTabs
@onready var gold_tab: Button = $UpgradePanel/VBoxContainer/BoardTabs/GoldTab
@onready var orange_tab: Button = $UpgradePanel/VBoxContainer/BoardTabs/OrangeTab
@onready var red_tab: Button = $UpgradePanel/VBoxContainer/BoardTabs/RedTab

# Tracks live widgets by action name for targeted updates
var current_entries: Dictionary = {}


func _ready() -> void:
	gold_tab.pressed.connect(func(): board_tab_selected.emit(0))    # GOLD
	orange_tab.pressed.connect(func(): board_tab_selected.emit(1))  # ORANGE
	red_tab.pressed.connect(func(): board_tab_selected.emit(2))     # RED


func update_coins(total: int) -> void:
	coin_label.text = "Gold: " + str(total)


func update_orange_coins(total: int) -> void:
	orange_coin_label.text = "Orange: " + str(total)


func update_red_coins(total: int) -> void:
	red_coin_label.text = "Red: " + str(total)


func update_level(level: int, next_threshold: int) -> void:
	if next_threshold > 0:
		level_label.text = "Level: " + str(level) + " (next: " + str(next_threshold) + ")"
	else:
		level_label.text = "Level: " + str(level) + " (max)"


func update_level_progress(current: int, next_threshold: int) -> void:
	if next_threshold <= 0:
		level_progress_bar.max_value = 1.0
		level_progress_bar.value = 1.0
		level_progress_label.text = "MAX"
	else:
		level_progress_bar.min_value = 0.0
		level_progress_bar.max_value = next_threshold
		level_progress_bar.value = mini(current, next_threshold)
		level_progress_label.text = str(current) + "/" + str(next_threshold)


func update_header(text: String) -> void:
	header_label.text = text


func show_orange_currency() -> void:
	orange_coin_label.visible = true
	orange_tab.visible = true


func show_red_currency() -> void:
	red_coin_label.visible = true
	red_tab.visible = true


## Clears the upgrade list and rebuilds it from an array of dictionaries.
## Each dictionary has:
##   "action": String — action name emitted on press
##   "label": String — button text
##   "cost_text": String — cost/info label text
##   "cap_action": String (optional) — action name for "+" cap-raise button
##   "cap_hover": String (optional) — hover text for cap cost label
func show_upgrades_for_board(header: String, upgrades: Array[Dictionary]) -> void:
	header_label.text = header

	# Clear existing entries
	for child in upgrade_list.get_children():
		child.queue_free()
	current_entries.clear()
	cap_cost_label.text = ""

	for upgrade in upgrades:
		var action: String = upgrade["action"]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Main upgrade button
		var btn := Button.new()
		btn.text = upgrade["label"]
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func(): upgrade_action.emit(action))
		row.add_child(btn)

		# Cost label
		var cost_lbl := Label.new()
		cost_lbl.text = upgrade.get("cost_text", "")
		cost_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cost_lbl)

		# Optional "+" cap-raise button
		var cap_btn: Button = null
		if upgrade.has("cap_action"):
			cap_btn = Button.new()
			cap_btn.text = "+"
			cap_btn.focus_mode = Control.FOCUS_NONE
			cap_btn.custom_minimum_size = Vector2(30, 0)
			var cap_action: String = upgrade["cap_action"]
			var cap_hover: String = upgrade.get("cap_hover", "")
			cap_btn.pressed.connect(func(): upgrade_action.emit(cap_action))
			cap_btn.mouse_entered.connect(func(): cap_cost_label.text = cap_hover)
			cap_btn.mouse_exited.connect(func(): cap_cost_label.text = "")
			row.add_child(cap_btn)

		upgrade_list.add_child(row)

		# Track widgets for targeted updates
		current_entries[action] = {
			"row": row,
			"button": btn,
			"cost_label": cost_lbl,
			"cap_button": cap_btn,
		}
		if upgrade.has("cap_action"):
			current_entries[upgrade["cap_action"]] = {
				"row": row,
				"cap_button": cap_btn,
			}


## Update just the cost text of a single entry without rebuilding the whole list.
func update_entry_cost(action_name: String, cost_text: String) -> void:
	if current_entries.has(action_name):
		var entry: Dictionary = current_entries[action_name]
		if entry.has("cost_label") and entry["cost_label"] != null:
			(entry["cost_label"] as Label).text = cost_text


## Update the hover text for a cap-raise button.
func update_cap_hover(cap_action: String, hover_text: String) -> void:
	if current_entries.has(cap_action):
		var entry: Dictionary = current_entries[cap_action]
		if entry.has("cap_button") and entry["cap_button"] != null:
			var cap_btn: Button = entry["cap_button"]
			# Reconnect hover signals with new text
			if cap_btn.mouse_entered.get_connections().size() > 0:
				for conn in cap_btn.mouse_entered.get_connections():
					cap_btn.mouse_entered.disconnect(conn["callable"])
			if cap_btn.mouse_exited.get_connections().size() > 0:
				for conn in cap_btn.mouse_exited.get_connections():
					cap_btn.mouse_exited.disconnect(conn["callable"])
			cap_btn.mouse_entered.connect(func(): cap_cost_label.text = hover_text)
			cap_btn.mouse_exited.connect(func(): cap_cost_label.text = "")
