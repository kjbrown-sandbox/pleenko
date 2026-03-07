extends CanvasLayer

signal upgrade_action(action_name: String)
signal board_tab_selected(board_type: int)  # PlinkoBoard.BoardType value
signal reset_pressed
signal reset_dev_pressed
signal level_up_dismissed
signal drop_unrefined_pressed
signal drop_coin_pressed
signal speed_toggle_pressed
signal quicksave_pressed
signal quickload_pressed
signal autodropper_plus_pressed
signal autodropper_minus_pressed

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
var drop_coin_btn: Button

# Level-up dialog
var level_up_overlay: ColorRect
var level_up_panel: PanelContainer
var level_up_title: Label
var level_up_message: Label
var level_up_button: Button

# Helper text panel
var helper_text_panel: PanelContainer
var helper_text_label: Label

# Autodropper row
var autodropper_row: HBoxContainer
var autodropper_minus_btn: Button
var autodropper_label: Label
var autodropper_plus_btn: Button
var _autodropper_free: int = 0
var _autodropper_total: int = 0

# Level label to the left of progress bar
var level_lvl_label: Label


func _ready() -> void:
	gold_tab.pressed.connect(func(): board_tab_selected.emit(0))    # GOLD
	orange_tab.pressed.connect(func(): board_tab_selected.emit(1))  # ORANGE
	red_tab.pressed.connect(func(): board_tab_selected.emit(2))     # RED
	gold_tab.mouse_entered.connect(func(): show_helper_text("Hotkeys: <- and -> arrow keys"))
	gold_tab.mouse_exited.connect(func(): hide_helper_text())
	orange_tab.mouse_entered.connect(func(): show_helper_text("Hotkeys: <- and -> arrow keys"))
	orange_tab.mouse_exited.connect(func(): hide_helper_text())
	red_tab.mouse_entered.connect(func(): show_helper_text("Hotkeys: <- and -> arrow keys"))
	red_tab.mouse_exited.connect(func(): hide_helper_text())

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

	var quicksave_btn := Button.new()
	quicksave_btn.text = "Quicksave (S)"
	quicksave_btn.focus_mode = Control.FOCUS_NONE
	quicksave_btn.pressed.connect(func(): quicksave_pressed.emit())
	reset_container.add_child(quicksave_btn)

	var quickload_btn := Button.new()
	quickload_btn.text = "Quickload"
	quickload_btn.focus_mode = Control.FOCUS_NONE
	quickload_btn.pressed.connect(func(): quickload_pressed.emit())
	reset_container.add_child(quickload_btn)

	# Spawn-area buttons — centered above the board
	var spawn_btn_container := VBoxContainer.new()
	spawn_btn_container.anchor_left = 0.5
	spawn_btn_container.anchor_right = 0.5
	spawn_btn_container.anchor_top = 0.0
	spawn_btn_container.anchor_bottom = 0.0
	spawn_btn_container.offset_left = -65.0
	spawn_btn_container.offset_right = 65.0
	spawn_btn_container.offset_top = 2.0
	spawn_btn_container.offset_bottom = 62.0
	add_child(spawn_btn_container)

	drop_unrefined_btn = Button.new()
	drop_unrefined_btn.text = "Drop Unrefined Orange"
	drop_unrefined_btn.focus_mode = Control.FOCUS_NONE
	drop_unrefined_btn.visible = false
	drop_unrefined_btn.pressed.connect(func(): drop_unrefined_pressed.emit())
	drop_unrefined_btn.mouse_entered.connect(func(): show_helper_text("Hotkey: spacebar"))
	drop_unrefined_btn.mouse_exited.connect(func(): hide_helper_text())
	spawn_btn_container.add_child(drop_unrefined_btn)

	drop_coin_btn = Button.new()
	drop_coin_btn.text = "Drop Coin"
	drop_coin_btn.focus_mode = Control.FOCUS_NONE
	drop_coin_btn.pressed.connect(func(): drop_coin_pressed.emit())
	drop_coin_btn.mouse_entered.connect(func(): show_helper_text("Hotkey: spacebar"))
	drop_coin_btn.mouse_exited.connect(func(): hide_helper_text())
	spawn_btn_container.add_child(drop_coin_btn)

	# Autodropper row (hidden by default)
	autodropper_row = HBoxContainer.new()
	autodropper_row.visible = false
	autodropper_row.alignment = BoxContainer.ALIGNMENT_CENTER

	autodropper_minus_btn = Button.new()
	autodropper_minus_btn.text = "[-]"
	autodropper_minus_btn.focus_mode = Control.FOCUS_NONE
	autodropper_minus_btn.pressed.connect(func(): autodropper_minus_pressed.emit())
	autodropper_minus_btn.mouse_entered.connect(func(): _show_autodropper_hover())
	autodropper_minus_btn.mouse_exited.connect(func(): hide_helper_text())
	autodropper_row.add_child(autodropper_minus_btn)

	autodropper_label = Label.new()
	autodropper_label.text = "Autodroppers: 0"
	autodropper_label.mouse_filter = Control.MOUSE_FILTER_STOP
	autodropper_label.mouse_entered.connect(func(): _show_autodropper_hover())
	autodropper_label.mouse_exited.connect(func(): hide_helper_text())
	autodropper_row.add_child(autodropper_label)

	autodropper_plus_btn = Button.new()
	autodropper_plus_btn.text = "[+]"
	autodropper_plus_btn.focus_mode = Control.FOCUS_NONE
	autodropper_plus_btn.pressed.connect(func(): autodropper_plus_pressed.emit())
	autodropper_plus_btn.mouse_entered.connect(func(): _show_autodropper_hover())
	autodropper_plus_btn.mouse_exited.connect(func(): hide_helper_text())
	autodropper_row.add_child(autodropper_plus_btn)

	spawn_btn_container.add_child(autodropper_row)

	# Helper text panel — bottom-right corner, hidden by default
	helper_text_panel = PanelContainer.new()
	helper_text_panel.anchor_left = 1.0
	helper_text_panel.anchor_right = 1.0
	helper_text_panel.anchor_top = 1.0
	helper_text_panel.anchor_bottom = 1.0
	helper_text_panel.offset_left = -220.0
	helper_text_panel.offset_right = -20.0
	helper_text_panel.offset_top = -80.0
	helper_text_panel.offset_bottom = -20.0
	helper_text_panel.visible = false
	add_child(helper_text_panel)

	helper_text_label = Label.new()
	helper_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	helper_text_panel.add_child(helper_text_label)

	# Hide the old level label in the upgrade panel
	level_label.visible = false

	# "LVL X" label to the left of the progress bar
	level_lvl_label = Label.new()
	level_lvl_label.text = "LVL 0"
	level_lvl_label.anchor_left = 0.0
	level_lvl_label.anchor_right = 0.0
	level_lvl_label.anchor_top = 1.0
	level_lvl_label.anchor_bottom = 1.0
	level_lvl_label.offset_left = 20.0
	level_lvl_label.offset_top = -30.0
	level_lvl_label.offset_right = 75.0
	level_lvl_label.offset_bottom = -10.0
	level_lvl_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(level_lvl_label)

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


func update_coins(total: int, max_coins: int) -> void:
	coin_label.text = "Gold: " + str(total) + "/" + str(max_coins)


func update_unrefined_orange(total: int) -> void:
	unrefined_orange_label.text = "Unrefined: " + str(total)


func update_orange_coins(total: int, max_coins: int) -> void:
	orange_coin_label.text = "Orange: " + str(total) + "/" + str(max_coins)


func update_red_coins(total: int, max_coins: int) -> void:
	red_coin_label.text = "Red: " + str(total) + "/" + str(max_coins)


func update_level_progress(level: int, current: int, next_threshold: int) -> void:
	level_lvl_label.text = "LVL " + str(level)
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


## Updates spawn button visibility based on which board is selected.
## board_type: 0 = GOLD, 1 = ORANGE, 2 = RED
func update_spawn_buttons(board_type: int) -> void:
	match board_type:
		1:  # ORANGE — only show unrefined drop
			drop_coin_btn.visible = false
			drop_unrefined_btn.visible = true
		_:  # GOLD, RED, etc — show drop coin, hide unrefined unless unlocked
			drop_coin_btn.visible = true


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

			var cap_state: String = upgrade.get("cap_state", "too_expensive")
			if cap_state == "available":
				var cap_style := StyleBoxFlat.new()
				cap_style.bg_color = Color(0.3, 0.55, 0.3)
				cap_style.set_corner_radius_all(3)
				cap_btn.add_theme_stylebox_override("normal", cap_style)
				var cap_hover_style := StyleBoxFlat.new()
				cap_hover_style.bg_color = Color(0.35, 0.65, 0.35)
				cap_hover_style.set_corner_radius_all(3)
				cap_btn.add_theme_stylebox_override("hover", cap_hover_style)

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


## Update the visual state of a cap-raise "+" button.
func update_cap_state(cap_action: String, state: String) -> void:
	if not current_entries.has(cap_action):
		return
	var entry: Dictionary = current_entries[cap_action]
	if not entry.has("cap_button") or entry["cap_button"] == null:
		return
	var cap_btn: Button = entry["cap_button"]
	if state == "available":
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.3, 0.55, 0.3)
		style.set_corner_radius_all(3)
		cap_btn.add_theme_stylebox_override("normal", style)
		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = Color(0.35, 0.65, 0.35)
		hover_style.set_corner_radius_all(3)
		cap_btn.add_theme_stylebox_override("hover", hover_style)
	else:
		cap_btn.remove_theme_stylebox_override("normal")
		cap_btn.remove_theme_stylebox_override("hover")


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


func show_helper_text(text: String) -> void:
	helper_text_label.text = text
	helper_text_panel.visible = true


func hide_helper_text() -> void:
	helper_text_panel.visible = false


func _show_autodropper_hover() -> void:
	show_helper_text("You have " + str(_autodropper_free) + "/" + str(_autodropper_total) + " autodroppers free. An autodropper drops 1 coin/second.")


## Updates the autodropper row visibility and label based on the current board.
## board_type: 0 = GOLD, 1 = ORANGE, 2 = RED
func update_autodropper_row(board: Node, gold_assigned: int, orange_assigned: int, total: int) -> void:
	if total <= 0:
		autodropper_row.visible = false
		return

	# Get board_type from the board node
	var board_type: int = board.get("board_type") if board else 0

	# Hide on RED board
	if board_type == 2:
		autodropper_row.visible = false
		return

	autodropper_row.visible = true
	_autodropper_total = total
	var free_pool := total - gold_assigned - orange_assigned

	var assigned: int
	if board_type == 1:  # ORANGE
		assigned = orange_assigned
	else:  # GOLD
		assigned = gold_assigned

	_autodropper_free = free_pool
	autodropper_label.text = "Autodroppers: " + str(assigned)
	autodropper_minus_btn.disabled = (assigned <= 0)
	autodropper_plus_btn.disabled = (free_pool <= 0)
