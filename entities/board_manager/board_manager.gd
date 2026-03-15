class_name BoardManager
extends Node3D

signal board_switched(board: PlinkoBoard)

const BoardScene: PackedScene = preload("res://entities/plinko_board/plinko_board.tscn")

## Horizontal distance between board centers
@export var board_spacing: float = 12.0
## How long the camera tween takes
@export var camera_tween_duration: float = 0.4

var _boards: Array[PlinkoBoard] = []
var _active_index: int = 0
var _camera: Camera3D

## Minimum Z distance so the camera doesn't get too close on small boards
const MIN_CAMERA_Z := 6.0


func setup(camera: Camera3D) -> void:
	_camera = camera
	# Start with just the gold board
	_spawn_board(Enums.BoardType.GOLD)
	# Frame the camera on the initial board immediately (no tween)
	_snap_camera_to_active_board()
	CurrencyManager.currency_changed.connect(_on_currency_changed)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("drop_coin"):
		get_active_board().request_drop()
	elif event.is_action_pressed("board_left"):
		switch_board(_active_index - 1)
	elif event.is_action_pressed("board_right"):
		switch_board(_active_index + 1)


func get_active_board() -> PlinkoBoard:
	return _boards[_active_index]


## Call this when a new board type is unlocked (e.g. orange, red).
func unlock_board(type: Enums.BoardType) -> void:
	# Don't spawn duplicates
	for board in _boards:
		if board.board_type == type:
			return
	_spawn_board(type)


func switch_board(index: int) -> void:
	if index < 0 or index >= _boards.size():
		return
	if index == _active_index:
		return

	# Hide old board's upgrades, show new board's upgrades
	_boards[_active_index].upgrade_section.visible = false
	_active_index = index
	_boards[_active_index].upgrade_section.visible = true

	_tween_camera_to_active_board()
	board_switched.emit(_boards[_active_index])


func _spawn_board(type: Enums.BoardType) -> void:
	var board: PlinkoBoard = BoardScene.instantiate()
	var board_index := _boards.size()
	board.position = Vector3(board_index * board_spacing, 0, 0)
	add_child(board)
	board.setup(type)

	# Only the active board's upgrades should be visible
	if board_index != _active_index:
		board.upgrade_section.visible = false

	board.board_rebuilt.connect(_on_board_rebuilt.bind(board))
	_boards.append(board)

func is_board_unlocked(type: Enums.BoardType) -> bool:
	for board in _boards:
		if board.board_type == type:
			return true
	return false


func _on_currency_changed(type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
	match type:
		Enums.CurrencyType.RAW_ORANGE:
			unlock_board(Enums.BoardType.ORANGE)
		Enums.CurrencyType.RAW_RED:
			unlock_board(Enums.BoardType.RED)


func _on_board_rebuilt(board: PlinkoBoard) -> void:
	# Only adjust the camera if the rebuilt board is the one we're looking at
	if board == _boards[_active_index]:
		_tween_camera_to_active_board()


func _get_camera_target(board: PlinkoBoard) -> Vector3:
	var bounds := board.get_bounds()
	var center_x := board.position.x + bounds.position.x + bounds.size.x / 2.0
	var center_y := bounds.position.y + bounds.size.y / 2.0
	var z_for_height := bounds.size.y * 0.9
	var z_for_width := bounds.size.x * 0.7
	var z_distance := maxf(MIN_CAMERA_Z, maxf(z_for_height, z_for_width))
	return Vector3(center_x, center_y, z_distance)


func _snap_camera_to_active_board() -> void:
	_camera.position = _get_camera_target(_boards[_active_index])


func _tween_camera_to_active_board() -> void:
	var target := _get_camera_target(_boards[_active_index])
	var tween := create_tween()
	tween.tween_property(_camera, "position", target, camera_tween_duration) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_QUAD)
