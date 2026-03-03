extends Node3D

@onready var ui: CanvasLayer = $UI
@onready var camera: Camera3D = $Camera3D

var board_scene: PackedScene = preload("res://scenes/plinko_board.tscn")

var coin_total: int = 1
var orange_coin_total: int = 0
var orange_board_unlocked: bool = false

var regular_upgrade_cost: int = 10
var orange_upgrade_cost: int = 10
const UPGRADE_COST_MULTIPLIER := 1.5
const BOARD_GAP := 3.0

var regular_board: PlinkoBoard
var orange_board: PlinkoBoard


func _ready() -> void:
	# Create regular board with 2 rows
	regular_board = board_scene.instantiate() as PlinkoBoard
	add_child(regular_board)

	# Connect signals before building so board_rebuilt triggers camera adjustment
	regular_board.drop_requested.connect(_on_regular_drop_requested)
	regular_board.coin_landed.connect(_on_regular_coin_landed)
	regular_board.board_rebuilt.connect(_adjust_camera)

	regular_board.num_rows = 2
	regular_board._build_board()

	ui.update_coins(coin_total)
	ui.update_upgrade(regular_upgrade_cost)
	ui.upgrade_pressed.connect(_buy_regular_upgrade)
	ui.orange_upgrade_pressed.connect(_buy_orange_upgrade)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("drop_coin"):
		_on_regular_drop_requested()


# --- Regular board handlers ---

func _on_regular_drop_requested() -> void:
	if coin_total < 1:
		return
	if regular_board.drop_coin():
		coin_total -= 1
		ui.update_coins(coin_total)


func _on_regular_coin_landed(value: int, is_orange: bool) -> void:
	if is_orange:
		orange_coin_total += 1
		ui.update_orange_coins(orange_coin_total)
		_check_unlock_orange_board()
	else:
		coin_total += value
		ui.update_coins(coin_total)


func _buy_regular_upgrade() -> void:
	if coin_total < regular_upgrade_cost:
		return

	coin_total -= regular_upgrade_cost
	regular_board.add_row()

	regular_upgrade_cost = int(regular_upgrade_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_coins(coin_total)
	ui.update_upgrade(regular_upgrade_cost)


# --- Orange board lifecycle ---

func _check_unlock_orange_board() -> void:
	if orange_board_unlocked:
		return
	if orange_coin_total < 1:
		return

	orange_board_unlocked = true

	orange_board = board_scene.instantiate() as PlinkoBoard
	orange_board.is_orange_board = true
	add_child(orange_board)

	# Connect signals before building so board_rebuilt triggers camera adjustment
	orange_board.drop_requested.connect(_on_orange_drop_requested)
	orange_board.coin_landed.connect(_on_orange_coin_landed)
	orange_board.board_rebuilt.connect(_adjust_camera)

	orange_board.num_rows = 2
	orange_board._build_board()
	ui.show_orange_panel()
	ui.update_orange_coins(orange_coin_total)
	ui.update_orange_upgrade(orange_upgrade_cost)


# --- Orange board handlers ---

func _on_orange_drop_requested() -> void:
	if orange_coin_total < 1:
		return
	if orange_board.drop_coin():
		orange_coin_total -= 1
		ui.update_orange_coins(orange_coin_total)


func _on_orange_coin_landed(value: int, _is_orange: bool) -> void:
	orange_coin_total += value
	ui.update_orange_coins(orange_coin_total)


func _buy_orange_upgrade() -> void:
	if orange_coin_total < orange_upgrade_cost:
		return

	orange_coin_total -= orange_upgrade_cost
	orange_board.add_row()

	orange_upgrade_cost = int(orange_upgrade_cost * UPGRADE_COST_MULTIPLIER)
	ui.update_orange_coins(orange_coin_total)
	ui.update_orange_upgrade(orange_upgrade_cost)


# --- Board positioning and camera ---

func _position_boards() -> void:
	if not orange_board_unlocked:
		regular_board.position = Vector3.ZERO
		return

	# Get widths of each board to position them side by side
	var reg_bounds := regular_board.get_bounds()
	var org_bounds := orange_board.get_bounds()

	var reg_half_width := reg_bounds.size.x / 2.0
	var org_half_width := org_bounds.size.x / 2.0

	# Center the pair: regular on the left, orange on the right
	var total_width := reg_bounds.size.x + BOARD_GAP + org_bounds.size.x
	var left_start := -total_width / 2.0

	regular_board.position.x = left_start + reg_half_width
	orange_board.position.x = left_start + reg_bounds.size.x + BOARD_GAP + org_half_width


func _adjust_camera() -> void:
	_position_boards()

	var bounds := regular_board.get_bounds()
	if orange_board_unlocked and orange_board:
		var ob := orange_board.get_bounds()
		bounds = bounds.merge(ob)

	var center_x := bounds.position.x + bounds.size.x / 2.0
	var center_y := bounds.position.y + bounds.size.y / 2.0
	var board_height := bounds.size.y
	var board_width := bounds.size.x

	# Distance based on whichever dimension is larger (accounting for aspect ratio)
	var z_for_height := board_height * 0.9
	var z_for_width := board_width * 0.7
	var z_distance := maxf(6.0, maxf(z_for_height, z_for_width))

	camera.position = Vector3(center_x, center_y, z_distance)
