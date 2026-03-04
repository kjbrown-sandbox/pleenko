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

# --- Leveling ---
var player_level: int = 0
const LEVEL_THRESHOLDS: Array[int] = [10, 20, 50, 100]

# --- Row upgrade costs (delta formula: cost += delta, delta += 5) ---
var regular_upgrade_cost: int = 5
var regular_upgrade_delta: int = 5
var orange_upgrade_cost: int = 5
var orange_upgrade_delta: int = 2
var red_upgrade_cost: int = 5
var red_upgrade_delta: int = 5

# --- Gold panel upgrades ---
var bucket_value_cost: int = 5
var bucket_value_level: int = 0
var drop_rate_cost: int = 100
var drop_rate_level: int = 0
var autodropper_cost: int = 5

# --- Gold upgrade caps (raised by orange) ---
var gold_row_cap: int = 5
var bucket_value_cap: int = 3
var drop_rate_cap: int = 3
var autodropper_cap: int = 3

# --- Orange panel upgrades ---
var orange_drop_rate_cost: int = 5
var orange_drop_rate_delta: int = 5
var orange_queue_up_cost: int = 10

# --- Orange cap-raise costs (x1.5 scaling) ---
var row_cap_cost: int = 5
var value_cap_cost: int = 5
var rate_cap_cost: int = 5
var auto_cap_cost: int = 5
const UPGRADE_COST_MULTIPLIER := 1.5

# --- Row caps (orange/red boards) ---
var orange_row_cap: int = 5
var red_row_cap: int = 5

# --- Autodropper (gold board auto-drop) ---
var autodropper_level: int = 0
var autodropper_timer: Timer

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
	ui.update_upgrade(regular_upgrade_cost, regular_board.num_rows, gold_row_cap)
	_update_level_label()

	# Connect UI signals
	ui.upgrade_pressed.connect(_buy_regular_upgrade)
	ui.orange_upgrade_pressed.connect(_buy_orange_upgrade)
	ui.red_upgrade_pressed.connect(_buy_red_upgrade)
	ui.autodropper_pressed.connect(_buy_autodropper)
	ui.orange_drop_rate_pressed.connect(_buy_orange_drop_rate)
	ui.orange_queue_up_pressed.connect(_buy_orange_queue_up)
	ui.bucket_value_pressed.connect(_buy_bucket_value)
	ui.drop_rate_pressed.connect(_buy_drop_rate)
	ui.row_cap_pressed.connect(_buy_row_cap)
	ui.value_cap_pressed.connect(_buy_value_cap)
	ui.rate_cap_pressed.connect(_buy_rate_cap)
	ui.auto_cap_pressed.connect(_buy_auto_cap)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("drop_coin"):
		_on_regular_drop_requested()


func _process(_delta: float) -> void:
	# Gold board: hold-to-drop (mouse only)
	if regular_board.holding_drop:
		_on_regular_drop_requested()

	# Orange board auto-drop from queue
	if orange_board_unlocked:
		if orange_queue > 0 and orange_queue_timer.is_stopped():
			if orange_board.drop_coin():
				orange_queue -= 1
				ui.update_orange_queue(orange_queue, orange_queue_max)
				orange_queue_timer.start()

		if not orange_queue_timer.is_stopped():
			var secs := int(ceil(orange_queue_timer.time_left))
			ui.update_orange_countdown(str(secs) + "s")
		else:
			ui.update_orange_countdown("")

	# Red board auto-drop from queue
	if red_board_unlocked:
		if red_queue > 0 and red_queue_timer.is_stopped():
			if red_board.drop_coin():
				red_queue -= 1
				ui.update_red_queue(red_queue, red_queue_max)
				red_queue_timer.start()

		if not red_queue_timer.is_stopped():
			var secs := int(ceil(red_queue_timer.time_left))
			ui.update_red_countdown(str(secs) + "s")
		else:
			ui.update_red_countdown("")


# === Gold board handlers ===

func _on_regular_drop_requested() -> void:
	if gold_drop_cooldown.wait_time > 0.0 and not gold_drop_cooldown.is_stopped():
		return
	if coin_total < 1:
		return
	if regular_board.drop_coin():
		coin_total -= 1
		ui.update_coins(coin_total)
		if gold_drop_cooldown.wait_time > 0.0:
			gold_drop_cooldown.start()
			gold_drop_label.text = "reloading..."


func _on_gold_cooldown_finished() -> void:
	gold_drop_label.text = "ready to drop"


func _on_regular_coin_landed(value: int, bucket_type: PlinkoBoard.BucketType) -> void:
	match bucket_type:
		PlinkoBoard.BucketType.GOLD:
			coin_total += value
			ui.update_coins(coin_total)
			_check_level_up()
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

	regular_upgrade_cost += regular_upgrade_delta
	regular_upgrade_delta += 5
	ui.update_coins(coin_total)
	ui.update_upgrade(regular_upgrade_cost, regular_board.num_rows, gold_row_cap)


# === Bucket Value +1 (gold currency, gold panel, capped) ===

func _buy_bucket_value() -> void:
	if coin_total < bucket_value_cost:
		return
	if bucket_value_level >= bucket_value_cap:
		return

	coin_total -= bucket_value_cost
	bucket_value_level += 1

	regular_board.value_bonus = bucket_value_level
	regular_board._build_board()

	bucket_value_cost *= 2
	ui.update_coins(coin_total)
	ui.update_bucket_value(bucket_value_cost, bucket_value_level, bucket_value_cap)


# === Drop Rate (gold currency, gold panel, capped) ===

func _buy_drop_rate() -> void:
	if coin_total < drop_rate_cost:
		return
	if drop_rate_level >= drop_rate_cap:
		return

	coin_total -= drop_rate_cost
	drop_rate_level += 1

	gold_drop_cooldown.wait_time *= 0.9

	drop_rate_cost = 100 * (drop_rate_level + 1)
	ui.update_coins(coin_total)
	ui.update_drop_rate(drop_rate_cost, gold_drop_cooldown.wait_time, drop_rate_level, drop_rate_cap)


# === Autodropper (gold currency, gold panel, capped) ===

func _buy_autodropper() -> void:
	if coin_total < autodropper_cost:
		return
	if autodropper_level >= autodropper_cap:
		return

	coin_total -= autodropper_cost
	autodropper_level += 1

	autodropper_cost = int(autodropper_cost * UPGRADE_COST_MULTIPLIER)
	autodropper_timer.wait_time = 1.0 / autodropper_level
	autodropper_timer.start()

	ui.update_coins(coin_total)
	ui.update_autodropper(autodropper_cost, autodropper_level, autodropper_cap)


func _on_autodropper_timeout() -> void:
	# Auto-drop a gold coin (independent of manual cooldown)
	if coin_total < 1:
		return
	if regular_board.drop_coin():
		coin_total -= 1
		ui.update_coins(coin_total)


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
	ui.update_orange_drop_rate(orange_drop_rate_cost, orange_queue_timer.wait_time)
	ui.update_orange_queue_up(orange_queue_up_cost, orange_queue_max)
	ui.update_row_cap(row_cap_cost, gold_row_cap)
	ui.update_value_cap(value_cap_cost, bucket_value_cap)
	ui.update_rate_cap(rate_cap_cost, drop_rate_cap)
	ui.update_auto_cap(auto_cap_cost, autodropper_cap)


# === Orange board handlers ===

func _on_orange_coin_landed(value: int, _bucket_type: PlinkoBoard.BucketType) -> void:
	orange_coin_total += value
	ui.update_orange_coins(orange_coin_total)


# === Orange board upgrade (Add Row) ===

func _buy_orange_upgrade() -> void:
	if orange_coin_total < orange_upgrade_cost:
		return

	orange_coin_total -= orange_upgrade_cost
	orange_board.add_row()

	orange_upgrade_cost += orange_upgrade_delta
	orange_upgrade_delta += 2
	ui.update_orange_coins(orange_coin_total)
	ui.update_orange_upgrade(orange_upgrade_cost)


# === Orange Drop Rate (orange currency, reduces queue timer) ===

func _buy_orange_drop_rate() -> void:
	if orange_coin_total < orange_drop_rate_cost:
		return

	orange_coin_total -= orange_drop_rate_cost
	orange_queue_timer.wait_time *= 0.9

	orange_drop_rate_cost += orange_drop_rate_delta
	orange_drop_rate_delta += 5
	ui.update_orange_coins(orange_coin_total)
	ui.update_orange_drop_rate(orange_drop_rate_cost, orange_queue_timer.wait_time)


# === Orange Queue +1 (orange currency) ===

func _buy_orange_queue_up() -> void:
	if orange_coin_total < orange_queue_up_cost:
		return

	orange_coin_total -= orange_queue_up_cost
	orange_queue_max += 1

	orange_queue_up_cost += 5
	ui.update_orange_coins(orange_coin_total)
	ui.update_orange_queue_up(orange_queue_up_cost, orange_queue_max)
	ui.update_orange_queue(orange_queue, orange_queue_max)


# === Orange cap-raise upgrades (orange currency, raise gold caps) ===

func _buy_row_cap() -> void:
	if orange_coin_total < row_cap_cost:
		return

	orange_coin_total -= row_cap_cost
	gold_row_cap += 2

	row_cap_cost = int(row_cap_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_orange_coins(orange_coin_total)
	ui.update_row_cap(row_cap_cost, gold_row_cap)
	ui.update_upgrade(regular_upgrade_cost, regular_board.num_rows, gold_row_cap)


func _buy_value_cap() -> void:
	if orange_coin_total < value_cap_cost:
		return

	orange_coin_total -= value_cap_cost
	bucket_value_cap += 1

	value_cap_cost = int(value_cap_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_orange_coins(orange_coin_total)
	ui.update_value_cap(value_cap_cost, bucket_value_cap)
	ui.update_bucket_value(bucket_value_cost, bucket_value_level, bucket_value_cap)


func _buy_rate_cap() -> void:
	if orange_coin_total < rate_cap_cost:
		return

	orange_coin_total -= rate_cap_cost
	drop_rate_cap += 1

	rate_cap_cost = int(rate_cap_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_orange_coins(orange_coin_total)
	ui.update_rate_cap(rate_cap_cost, drop_rate_cap)
	ui.update_drop_rate(drop_rate_cost, gold_drop_cooldown.wait_time, drop_rate_level, drop_rate_cap)


func _buy_auto_cap() -> void:
	if orange_coin_total < auto_cap_cost:
		return

	orange_coin_total -= auto_cap_cost
	autodropper_cap += 1

	auto_cap_cost = int(auto_cap_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_orange_coins(orange_coin_total)
	ui.update_auto_cap(auto_cap_cost, autodropper_cap)
	ui.update_autodropper(autodropper_cost, autodropper_level, autodropper_cap)


# === Leveling system ===

func _check_level_up() -> void:
	while player_level < LEVEL_THRESHOLDS.size() and coin_total >= LEVEL_THRESHOLDS[player_level]:
		player_level += 1
		_on_level_up(player_level)
	_update_level_label()


func _on_level_up(level: int) -> void:
	match level:
		1:
			ui.show_bucket_value()
			ui.update_bucket_value(bucket_value_cost, bucket_value_level, bucket_value_cap)
		2:
			ui.show_add_row()
			ui.update_upgrade(regular_upgrade_cost, regular_board.num_rows, gold_row_cap)
		3:
			ui.show_drop_rate()
			ui.update_drop_rate(drop_rate_cost, gold_drop_cooldown.wait_time, drop_rate_level, drop_rate_cap)
		4:
			ui.show_autodropper()
			ui.update_autodropper(autodropper_cost, autodropper_level, autodropper_cap)


func _update_level_label() -> void:
	if player_level < LEVEL_THRESHOLDS.size():
		var next_threshold := LEVEL_THRESHOLDS[player_level]
		ui.update_level(player_level, next_threshold)
		ui.update_level_progress(coin_total, next_threshold)
	else:
		ui.update_level(player_level, 0)
		ui.update_level_progress(coin_total, 0)


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


# === Red board handlers ===

func _on_red_coin_landed(value: int, _bucket_type: PlinkoBoard.BucketType) -> void:
	red_coin_total += value
	ui.update_red_coins(red_coin_total)


# === Red board upgrade (Add Row) ===

func _buy_red_upgrade() -> void:
	if red_coin_total < red_upgrade_cost:
		return

	red_coin_total -= red_upgrade_cost
	red_board.add_row()

	red_upgrade_cost += red_upgrade_delta
	red_upgrade_delta += 5
	ui.update_red_coins(red_coin_total)
	ui.update_red_upgrade(red_upgrade_cost)


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
