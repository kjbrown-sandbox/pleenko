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

## The initial camera offset from board position (captured at startup)
var _camera_offset: Vector3


func setup(camera: Camera3D) -> void:
	_camera = camera
	# Capture the camera's starting offset relative to origin (the first board)
	_camera_offset = camera.position
	# Start with just the gold board
	_spawn_board(Enums.BoardType.GOLD)


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

	_boards.append(board)


func _tween_camera_to_active_board() -> void:
	var board_pos := _boards[_active_index].position
	var target := Vector3(
		board_pos.x + _camera_offset.x,
		_camera_offset.y,
		_camera_offset.z,
	)
	var tween := create_tween()
	tween.tween_property(_camera, "position", target, camera_tween_duration) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_QUAD)
