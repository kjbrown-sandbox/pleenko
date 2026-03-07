extends CanvasLayer

signal upgrade_action(action_name: String)
signal board_tab_selected(board_type: int)  # PlinkoBoard.BoardType value
signal reset_pressed
signal reset_dev_pressed
signal level_up_dismissed
signal drop_unrefined_pressed
signal drop_coin_pressed
signal speed_toggle_pressed

@onready var coin_label: Label = $CoinLabel
@onready var unrefined_orange_label: Label = $UnrefinedOrangeLabel
@onready var orange_coin_label: Label = $OrangeCoinLabel
@onready var red_coin_label: Label = $RedCoinLabel

@onready var game_timer_label: Label = $GameTimerLabel
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

# Spawn-area buttons
var drop_unrefined_btn: Button

# Level-up dialog
var level_up_overlay: ColorRect
var level_up_panel: PanelContainer
var level_up_title: Label
var level_up_message: Label
var level_up_button: Button


func _ready() -> void:
	gold_tab.pressed.connect(func(): board_tab_selected.emit(0))    # GOLD
	orange_tab.pressed.connect(func(): board_tab_selected.emit(1))  # ORANGE
	red_tab.pressed.connect(func(): board_tab_selected.emit(2))     # RED

	# Reset buttons container — left side, vertically centered
	var reset_container := VBoxContainer.new()
	reset_container.anchor_left = 0.0
	reset_container.anchor_right = 0.0
	reset_container.anchor_top = 0.5
	reset_container.anchor_bottom = 0.5
	reset_container.offset_left = 20.0
	reset_container.offset_top = -35.0
	reset_container.offset_right = 110.0
	reset_container.offset_bottom = 35.0
	add_child(reset_container)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.pressed.connect(func(): reset_pressed.emit())
	reset_container.add_child(reset_btn)

	var reset_dev_btn := Button.new()
	reset_dev_btn.text = "Reset(3)"
	reset_dev_btn.focus_mode = Control.FOCUS_NONE
	reset_dev_btn.pressed.connect(func(): reset_dev_pressed.emit())
	reset_container.add_child(reset_dev_btn)

	var speed_btn := Button.new()
	speed_btn.text = "Speed x10"
	speed_btn.focus_mode = Control.FOCUS_NONE
	speed_btn.pressed.connect(func(): speed_toggle_pressed.emit())
	reset_container.add_child(speed_btn)

	# Spawn-area buttons — centered above the board
	var spawn_btn_container := VBoxContainer.new()
	spawn_btn_container.anchor_left = 0.5
	spawn_btn_container.anchor_right = 0.5
	spawn_btn_container.anchor_top = 0.0
	spawn_btn_container.anchor_bottom = 0.0
	spawn_btn_container.offset_left = -65.0
	spawn_btn_container.offset_right = 65.0
	spawn_btn_container.offset_top = 20.0
	spawn_btn_container.offset_bottom = 80.0
	add_child(spawn_btn_container)

	drop_unrefined_btn = Button.new()
	drop_unrefined_btn.text = "Drop Unrefined (1)"
	drop_unrefined_btn.focus_mode = Control.FOCUS_NONE
	drop_unrefined_btn.visible = false
	drop_unrefined_btn.pressed.connect(func(): drop_unrefined_pressed.emit())
	spawn_btn_container.add_child(drop_unrefined_btn)

	var drop_coin_btn := Button.new()
	drop_coin_btn.text = "Drop Coin"
	drop_coin_btn.focus_mode = Control.FOCUS_NONE
	drop_coin_btn.tooltip_text = "Hotkey: spacebar"
	drop_coin_btn.pressed.connect(func(): drop_coin_pressed.emit())
	spawn_btn_container.add_child(drop_coin_btn)

	# Level-up dialog (hidden by default)
	level_up_overlay = ColorRect.new()
	level_up_overlay.color = Color(0, 0, 0, 0.5)
	level_up_overlay.anchor_right = 1.0
	level_up_overlay.anchor_bottom = 1.0
	level_up_overlay.visible = false
	add_child(level_up_overlay)

	level_up_panel = PanelContainer.new()
	level_up_panel.anchor_left = 0.5
	level_up_panel.anchor_right = 0.5
	level_up_panel.anchor_top = 0.5
	level_up_panel.anchor_bottom = 0.5
	level_up_panel.offset_left = -150.0
	level_up_panel.offset_right = 150.0
	level_up_panel.offset_top = -80.0
	level_up_panel.offset_bottom = 80.0
	level_up_overlay.add_child(level_up_panel)

	var vbox := VBoxContainer.new()
	vbox.layout_mode = 2
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	level_up_panel.add_child(vbox)

	level_up_title = Label.new()
	level_up_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_up_title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(level_up_title)

	level_up_message = Label.new()
	level_up_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_up_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(level_up_message)

	level_up_button = Button.new()
	level_up_button.text = "Claim Reward"
	level_up_button.focus_mode = Control.FOCUS_NONE
	level_up_button.pressed.connect(_on_level_up_dismissed)
	vbox.add_child(level_up_button)


func show_level_up_dialog(level: int, message: String) -> void:
	level_up_title.text = "LEVEL UP!"
	level_up_message.text = "You are now level " + str(level) + ".\n" + message
	level_up_overlay.visible = true


func _on_level_up_dismissed() -> void:
	level_up_overlay.visible = false
	level_up_dismissed.emit()


func is_level_up_visible() -> bool:
	return level_up_overlay.visible


func update_game_timer(total_seconds: float) -> void:
	var secs := int(total_seconds)
	var hours := secs / 3600
	var mins := (secs % 3600) / 60
	var s := secs % 60
	game_timer_label.text = str(hours) + ":" + str(mins).pad_zeros(2) + ":" + str(s).pad_zeros(2)


var show_coin_max: bool = false

func update_coins(total: int, max_coins: int = 0) -> void:
	if show_coin_max and max_coins > 0:
		coin_label.text = "Gold: " + str(total) + "/" + str(max_coins)
	else:
		coin_label.text = "Gold: " + str(total)


func update_unrefined_orange(total: int) -> void:
	unrefined_orange_label.text = "Unrefined: " + str(total)


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


func show_unrefined_orange() -> void:
	unrefined_orange_label.visible = true


func show_drop_unrefined_button() -> void:
	drop_unrefined_btn.visible = true


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

		# Color based on state
		var state: String = upgrade.get("state", "available")
		match state:
			"available":
				var style := StyleBoxFlat.new()
				style.bg_color = Color(0.3, 0.55, 0.3)
				style.set_corner_radius_all(3)
				btn.add_theme_stylebox_override("normal", style)
				var hover_style := StyleBoxFlat.new()
				hover_style.bg_color = Color(0.35, 0.65, 0.35)
				hover_style.set_corner_radius_all(3)
				btn.add_theme_stylebox_override("hover", hover_style)
			"maxed":
				var style := StyleBoxFlat.new()
				style.bg_color = Color(0.2, 0.2, 0.2)
				style.set_corner_radius_all(3)
				btn.add_theme_stylebox_override("normal", style)
				btn.add_theme_stylebox_override("hover", style)
				btn.disabled = true
			# "too_expensive": keep default gray

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


## Update the visual state of a single upgrade button without rebuilding the list.
func update_entry_state(action_name: String, state: String) -> void:
	if not current_entries.has(action_name):
		return
	var entry: Dictionary = current_entries[action_name]
	if not entry.has("button") or entry["button"] == null:
		return
	var btn: Button = entry["button"]
	match state:
		"available":
			btn.disabled = false
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.3, 0.55, 0.3)
			style.set_corner_radius_all(3)
			btn.add_theme_stylebox_override("normal", style)
			var hover_style := StyleBoxFlat.new()
			hover_style.bg_color = Color(0.35, 0.65, 0.35)
			hover_style.set_corner_radius_all(3)
			btn.add_theme_stylebox_override("hover", hover_style)
		"maxed":
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.2, 0.2)
			style.set_corner_radius_all(3)
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_stylebox_override("hover", style)
			btn.disabled = true
		"too_expensive":
			btn.disabled = false
			btn.remove_theme_stylebox_override("normal")
			btn.remove_theme_stylebox_override("hover")


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
