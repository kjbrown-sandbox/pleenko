extends Node3D

@onready var ui: CanvasLayer = $UI
@onready var camera: Camera3D = $Camera3D

var board_scene: PackedScene = preload("res://scenes/plinko_board.tscn")

# --- Currency ---
var coin_total: int = 1
var orange_coin_total: int = 0
var red_coin_total: int = 0

# --- Unlock state ---
var orange_board_unlocked: bool = false
var red_board_unlocked: bool = false

# --- Upgrade costs (all scale by x1.5) ---
var regular_upgrade_cost: int = 10
var orange_upgrade_cost: int = 10
var red_upgrade_cost: int = 10
var autodropper_cost: int = 5
var gold_bonus_cost: int = 5
var gold_row_cap_cost: int = 5
var orange_row_cap_cost: int = 5
var auto_cap_cost: int = 5
var orange_queue_cap_cost: int = 5
var red_queue_cap_cost: int = 5
const UPGRADE_COST_MULTIPLIER := 1.5

# --- Row caps ---
var gold_row_cap: int = 10
var orange_row_cap: int = 5
var red_row_cap: int = 5

# --- Autodropper (gold board auto-drop) ---
var autodropper_level: int = 0
var autodropper_cap: int = 10
var autodropper_timer: Timer

# --- Gold bonus ---
var gold_bonus_level: int = 0

# --- Gold drop cooldown ---
var gold_drop_cooldown: Timer
var gold_drop_label: Label3D

# --- Orange queue (auto-drop on orange board) ---
var orange_queue: int = 0
var orange_queue_max: int = 1
const QUEUE_DROP_INTERVAL := 10.0
var orange_queue_timer: Timer

# --- Red queue (auto-drop on red board) ---
var red_queue: int = 0
var red_queue_max: int = 1
var red_queue_timer: Timer

# --- Boards ---
const BOARD_GAP := 3.0
var regular_board: PlinkoBoard
var orange_board: PlinkoBoard
var red_board: PlinkoBoard


func _ready() -> void:
	# Create regular (gold) board with 2 rows
	regular_board = board_scene.instantiate() as PlinkoBoard
	add_child(regular_board)

	regular_board.drop_requested.connect(_on_regular_drop_requested)
	regular_board.coin_landed.connect(_on_regular_coin_landed)
	regular_board.board_rebuilt.connect(_adjust_camera)

	regular_board.num_rows = 2
	regular_board._build_board()

	# Gold drop cooldown (1s between manual drops)
	gold_drop_cooldown = Timer.new()
	gold_drop_cooldown.one_shot = true
	gold_drop_cooldown.wait_time = 1.0
	gold_drop_cooldown.timeout.connect(_on_gold_cooldown_finished)
	add_child(gold_drop_cooldown)

	# "ready to drop" / "reloading..." label above gold board
	gold_drop_label = Label3D.new()
	gold_drop_label.font_size = 48
	gold_drop_label.text = "ready to drop"
	gold_drop_label.position = Vector3(0.0, PlinkoBoard.TOP_Y + 1.8, 0.0)
	regular_board.add_child(gold_drop_label)

	# Autodropper timer (gold board auto-drops, independent of manual cooldown)
	autodropper_timer = Timer.new()
	autodropper_timer.one_shot = false
	autodropper_timer.autostart = false
	autodropper_timer.timeout.connect(_on_autodropper_timeout)
	add_child(autodropper_timer)

	# Orange queue timer (cooldown between orange board auto-drops)
	orange_queue_timer = Timer.new()
	orange_queue_timer.one_shot = true
	orange_queue_timer.wait_time = QUEUE_DROP_INTERVAL
	add_child(orange_queue_timer)

	# Red queue timer (cooldown between red board auto-drops)
	red_queue_timer = Timer.new()
	red_queue_timer.one_shot = true
	red_queue_timer.wait_time = QUEUE_DROP_INTERVAL
	add_child(red_queue_timer)

	# UI init
	ui.update_coins(coin_total)
	ui.update_upgrade(regular_upgrade_cost)

	# Connect UI signals
	ui.upgrade_pressed.connect(_buy_regular_upgrade)
	ui.orange_upgrade_pressed.connect(_buy_orange_upgrade)
	ui.red_upgrade_pressed.connect(_buy_red_upgrade)
	ui.autodropper_pressed.connect(_buy_autodropper)
	ui.gold_bonus_pressed.connect(_buy_gold_bonus)
	ui.gold_row_cap_pressed.connect(_buy_gold_row_cap)
	ui.orange_row_cap_pressed.connect(_buy_orange_row_cap)
	ui.auto_cap_pressed.connect(_buy_auto_cap)
	ui.orange_queue_cap_pressed.connect(_buy_orange_queue_cap)
	ui.red_queue_cap_pressed.connect(_buy_red_queue_cap)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("drop_coin"):
		_on_regular_drop_requested()


func _process(_delta: float) -> void:
	# Orange board auto-drop from queue
	if orange_board_unlocked:
		if orange_queue > 0 and coin_total >= 1 and orange_queue_timer.is_stopped():
			if orange_board.drop_coin():
				coin_total -= 1
				orange_queue -= 1
				ui.update_coins(coin_total)
				ui.update_orange_queue(orange_queue, orange_queue_max)
				orange_queue_timer.start()

		if not orange_queue_timer.is_stopped():
			var secs := int(ceil(orange_queue_timer.time_left))
			ui.update_orange_countdown(str(secs) + "s")
		else:
			ui.update_orange_countdown("")

	# Red board auto-drop from queue
	if red_board_unlocked:
		if red_queue > 0 and coin_total >= 1 and red_queue_timer.is_stopped():
			if red_board.drop_coin():
				coin_total -= 1
				red_queue -= 1
				ui.update_coins(coin_total)
				ui.update_red_queue(red_queue, red_queue_max)
				red_queue_timer.start()

		if not red_queue_timer.is_stopped():
			var secs := int(ceil(red_queue_timer.time_left))
			ui.update_red_countdown(str(secs) + "s")
		else:
			ui.update_red_countdown("")


# === Gold board handlers ===

func _on_regular_drop_requested() -> void:
	if not gold_drop_cooldown.is_stopped():
		return
	if coin_total < 1:
		return
	if regular_board.drop_coin():
		coin_total -= 1
		ui.update_coins(coin_total)
		gold_drop_cooldown.start()
		gold_drop_label.text = "reloading..."


func _on_gold_cooldown_finished() -> void:
	gold_drop_label.text = "ready to drop"


func _on_regular_coin_landed(value: int, bucket_type: PlinkoBoard.BucketType) -> void:
	match bucket_type:
		PlinkoBoard.BucketType.GOLD:
			coin_total += value
			ui.update_coins(coin_total)
		PlinkoBoard.BucketType.ORANGE:
			_add_to_orange_queue(value)
			_check_unlock_orange_board()
		PlinkoBoard.BucketType.RED:
			_add_to_red_queue(value)
			_check_unlock_red_board()


# === Gold board upgrade (Add Row) ===

func _buy_regular_upgrade() -> void:
	if coin_total < regular_upgrade_cost:
		return
	if regular_board.num_rows >= gold_row_cap:
		return

	coin_total -= regular_upgrade_cost
	regular_board.add_row()

	regular_upgrade_cost = int(regular_upgrade_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_coins(coin_total)
	ui.update_upgrade(regular_upgrade_cost)


# === Orange queue ===

func _add_to_orange_queue(count: int) -> void:
	orange_queue = mini(orange_queue + count, orange_queue_max)
	if orange_board_unlocked:
		ui.update_orange_queue(orange_queue, orange_queue_max)


func _add_to_red_queue(count: int) -> void:
	red_queue = mini(red_queue + count, red_queue_max)
	if red_board_unlocked:
		ui.update_red_queue(red_queue, red_queue_max)


# === Orange board lifecycle ===

func _check_unlock_orange_board() -> void:
	if orange_board_unlocked:
		return

	orange_board_unlocked = true

	orange_board = board_scene.instantiate() as PlinkoBoard
	orange_board.board_type = PlinkoBoard.BoardType.ORANGE
	add_child(orange_board)

	# No click-to-drop — orange board uses auto-drop queue
	orange_board.coin_landed.connect(_on_orange_coin_landed)
	orange_board.board_rebuilt.connect(_adjust_camera)

	orange_board.num_rows = 2
	orange_board._build_board()

	ui.show_orange_panel()
	ui.update_orange_coins(orange_coin_total)
	ui.update_orange_queue(orange_queue, orange_queue_max)
	ui.update_orange_upgrade(orange_upgrade_cost)
	ui.update_autodropper(autodropper_cost, autodropper_level, autodropper_cap)
	ui.update_gold_bonus(gold_bonus_cost, gold_bonus_level)


# === Orange board handlers ===

func _on_orange_coin_landed(value: int, _bucket_type: PlinkoBoard.BucketType) -> void:
	orange_coin_total += value
	ui.update_orange_coins(orange_coin_total)


# === Orange board upgrade (Add Row) ===

func _buy_orange_upgrade() -> void:
	if orange_coin_total < orange_upgrade_cost:
		return
	if orange_board.num_rows >= orange_row_cap:
		return

	orange_coin_total -= orange_upgrade_cost
	orange_board.add_row()

	orange_upgrade_cost = int(orange_upgrade_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_orange_coins(orange_coin_total)
	ui.update_orange_upgrade(orange_upgrade_cost)


# === Autodropper (orange currency, drops on gold board) ===

func _buy_autodropper() -> void:
	if autodropper_level >= autodropper_cap:
		return
	if orange_coin_total < autodropper_cost:
		return

	orange_coin_total -= autodropper_cost
	autodropper_level += 1

	autodropper_cost = int(autodropper_cost * UPGRADE_COST_MULTIPLIER)
	autodropper_timer.wait_time = 1.0 / autodropper_level
	autodropper_timer.start()

	ui.update_orange_coins(orange_coin_total)
	ui.update_autodropper(autodropper_cost, autodropper_level, autodropper_cap)


func _on_autodropper_timeout() -> void:
	# Auto-drop a gold coin (independent of manual cooldown)
	if coin_total < 1:
		return
	if regular_board.drop_coin():
		coin_total -= 1
		ui.update_coins(coin_total)


# === Gold bonus (orange currency) ===

func _buy_gold_bonus() -> void:
	if orange_coin_total < gold_bonus_cost:
		return

	orange_coin_total -= gold_bonus_cost
	gold_bonus_level += 1

	gold_bonus_cost = int(gold_bonus_cost * UPGRADE_COST_MULTIPLIER)
	regular_board.value_bonus = gold_bonus_level
	regular_board._build_board()

	ui.update_orange_coins(orange_coin_total)
	ui.update_gold_bonus(gold_bonus_cost, gold_bonus_level)


# === Red board lifecycle ===

func _check_unlock_red_board() -> void:
	if red_board_unlocked:
		return

	red_board_unlocked = true

	red_board = board_scene.instantiate() as PlinkoBoard
	red_board.board_type = PlinkoBoard.BoardType.RED
	add_child(red_board)

	# No click-to-drop — red board uses auto-drop queue
	red_board.coin_landed.connect(_on_red_coin_landed)
	red_board.board_rebuilt.connect(_adjust_camera)

	red_board.num_rows = 2
	red_board._build_board()

	ui.show_red_panel()
	ui.update_red_coins(red_coin_total)
	ui.update_red_queue(red_queue, red_queue_max)
	ui.update_red_upgrade(red_upgrade_cost)
	ui.update_gold_row_cap(gold_row_cap_cost, gold_row_cap)
	ui.update_orange_row_cap(orange_row_cap_cost, orange_row_cap)
	ui.update_auto_cap(auto_cap_cost, autodropper_cap)
	ui.update_orange_queue_cap(orange_queue_cap_cost, orange_queue_max)
	ui.update_red_queue_cap(red_queue_cap_cost, red_queue_max)


# === Red board handlers ===

func _on_red_coin_landed(value: int, _bucket_type: PlinkoBoard.BucketType) -> void:
	red_coin_total += value
	ui.update_red_coins(red_coin_total)


# === Red board upgrade (Add Row) ===

func _buy_red_upgrade() -> void:
	if red_coin_total < red_upgrade_cost:
		return
	if red_board.num_rows >= red_row_cap:
		return

	red_coin_total -= red_upgrade_cost
	red_board.add_row()

	red_upgrade_cost = int(red_upgrade_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_red_coins(red_coin_total)
	ui.update_red_upgrade(red_upgrade_cost)


# === Red cap upgrades (red currency) ===

func _buy_gold_row_cap() -> void:
	if red_coin_total < gold_row_cap_cost:
		return

	red_coin_total -= gold_row_cap_cost
	gold_row_cap += 2

	gold_row_cap_cost = int(gold_row_cap_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_red_coins(red_coin_total)
	ui.update_gold_row_cap(gold_row_cap_cost, gold_row_cap)


func _buy_orange_row_cap() -> void:
	if red_coin_total < orange_row_cap_cost:
		return

	red_coin_total -= orange_row_cap_cost
	orange_row_cap += 2

	orange_row_cap_cost = int(orange_row_cap_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_red_coins(red_coin_total)
	ui.update_orange_row_cap(orange_row_cap_cost, orange_row_cap)


func _buy_auto_cap() -> void:
	if red_coin_total < auto_cap_cost:
		return

	red_coin_total -= auto_cap_cost
	autodropper_cap += 2

	auto_cap_cost = int(auto_cap_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_red_coins(red_coin_total)
	ui.update_auto_cap(auto_cap_cost, autodropper_cap)
	ui.update_autodropper(autodropper_cost, autodropper_level, autodropper_cap)


func _buy_orange_queue_cap() -> void:
	if red_coin_total < orange_queue_cap_cost:
		return

	red_coin_total -= orange_queue_cap_cost
	orange_queue_max += 1

	orange_queue_cap_cost = int(orange_queue_cap_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_red_coins(red_coin_total)
	ui.update_orange_queue_cap(orange_queue_cap_cost, orange_queue_max)
	ui.update_orange_queue(orange_queue, orange_queue_max)


func _buy_red_queue_cap() -> void:
	if red_coin_total < red_queue_cap_cost:
		return

	red_coin_total -= red_queue_cap_cost
	red_queue_max += 1

	red_queue_cap_cost = int(red_queue_cap_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_red_coins(red_coin_total)
	ui.update_red_queue_cap(red_queue_cap_cost, red_queue_max)
	ui.update_red_queue(red_queue, red_queue_max)


# === Board positioning and camera ===

func _position_boards() -> void:
	var boards: Array[PlinkoBoard] = [regular_board]
	if orange_board_unlocked and orange_board:
		boards.append(orange_board)
	if red_board_unlocked and red_board:
		boards.append(red_board)

	if boards.size() == 1:
		boards[0].position = Vector3.ZERO
		return

	# Calculate total width
	var widths: Array[float] = []
	var total_width := 0.0
	for b in boards:
		var w := b.get_bounds().size.x
		widths.append(w)
		total_width += w
	total_width += BOARD_GAP * (boards.size() - 1)

	# Position left-to-right, centered around x=0
	var x := -total_width / 2.0
	for i in range(boards.size()):
		var half_w := widths[i] / 2.0
		boards[i].position.x = x + half_w
		x += widths[i] + BOARD_GAP


func _adjust_camera() -> void:
	_position_boards()

	var bounds := regular_board.get_bounds()
	if orange_board_unlocked and orange_board:
		bounds = bounds.merge(orange_board.get_bounds())
	if red_board_unlocked and red_board:
		bounds = bounds.merge(red_board.get_bounds())

	var center_x := bounds.position.x + bounds.size.x / 2.0
	var center_y := bounds.position.y + bounds.size.y / 2.0
	var board_height := bounds.size.y
	var board_width := bounds.size.x

	# Distance based on whichever dimension is larger (accounting for aspect ratio)
	var z_for_height := board_height * 0.9
	var z_for_width := board_width * 0.7
	var z_distance := maxf(6.0, maxf(z_for_height, z_for_width))

	camera.position = Vector3(center_x, center_y, z_distance)
