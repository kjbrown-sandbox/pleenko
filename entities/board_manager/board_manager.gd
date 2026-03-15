class_name BoardManager
extends Node3D

signal board_switched(board: PlinkoBoard)

const BoardScene: PackedScene = preload("res://entities/plinko_board/plinko_board.tscn")

## Horizontal distance between board centers
@export var board_spacing: float = 7.0
## How long the camera tween takes
@export var camera_tween_duration: float = 0.4

var _boards: Array[PlinkoBoard] = []
var _active_index: int = 0
var _camera: Camera3D
var _autodroppers_unlocked: bool = false
var _assignments: Dictionary = {}  # StringName -> int (button_id → assigned count)
var _autodrop_timer: Timer

## Minimum Z distance so the camera doesn't get too close on small boards
const MIN_CAMERA_Z := 6.0


func setup(camera: Camera3D) -> void:
	_camera = camera
	# Start with just the gold board
	_spawn_board(Enums.BoardType.GOLD)
	# Frame the camera on the initial board immediately (no tween)
	_snap_camera_to_active_board()
	CurrencyManager.currency_changed.connect(_on_currency_changed)

	# Autodropper timer (1 tick per second, starts paused)
	_autodrop_timer = Timer.new()
	_autodrop_timer.wait_time = 1.0
	_autodrop_timer.autostart = false
	_autodrop_timer.timeout.connect(_on_autodrop_tick)
	add_child(_autodrop_timer)

	UpgradeManager.autodropper_unlocked.connect(_on_autodropper_unlocked)
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("board_left"):
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

	# Hide old board's UI, show new board's UI
	_boards[_active_index].upgrade_section.visible = false
	_boards[_active_index].drop_section.visible = false
	_active_index = index
	_boards[_active_index].upgrade_section.visible = true
	_boards[_active_index].drop_section.visible = true

	_tween_camera_to_active_board()
	board_switched.emit(_boards[_active_index])


func _spawn_board(type: Enums.BoardType) -> void:
	var board: PlinkoBoard = BoardScene.instantiate()
	var board_index := _boards.size()
	board.position = Vector3(board_index * board_spacing, 0, 0)
	add_child(board)
	board.setup(type)

	# Only the active board's UI should be visible
	if board_index != _active_index:
		board.upgrade_section.visible = false
		board.drop_section.visible = false

	board.board_rebuilt.connect(_on_board_rebuilt.bind(board))
	board.autodropper_adjust_requested.connect(_on_autodropper_adjust)
	if _autodroppers_unlocked:
		board.set_autodroppers_visible(true)
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


# --- Autodropper ---

func get_autodropper_pool() -> int:
	return UpgradeManager.get_level(Enums.BoardType.ORANGE, Enums.UpgradeType.AUTODROPPER)


func get_total_assigned() -> int:
	var total := 0
	for count in _assignments.values():
		total += count
	return total


func get_free_autodroppers() -> int:
	return get_autodropper_pool() - get_total_assigned()


func _on_autodropper_unlocked() -> void:
	_autodroppers_unlocked = true
	for board in _boards:
		board.set_autodroppers_visible(true)


func _on_autodropper_adjust(button_id: StringName, delta: int) -> void:
	var current: int = _assignments.get(button_id, 0)
	var new_count: int = current + delta

	if new_count < 0:
		return
	if delta > 0 and get_free_autodroppers() <= 0:
		return

	_assignments[button_id] = new_count
	_update_all_button_displays()

	# Start or stop the timer based on whether any autodroppers are assigned
	if get_total_assigned() > 0 and _autodrop_timer.is_stopped():
		_autodrop_timer.start()
	elif get_total_assigned() == 0 and not _autodrop_timer.is_stopped():
		_autodrop_timer.stop()


func _on_autodrop_tick() -> void:
	for button_id in _assignments:
		var count: int = _assignments[button_id]
		if count <= 0:
			continue
		var board := _find_board_for_button(button_id)
		if not board:
			continue
		var is_advanced: bool = (button_id as String).ends_with("_ADVANCED")
		for i in count:
			board.try_autodrop(is_advanced)


func _on_upgrade_purchased(upgrade_type: Enums.UpgradeType, _board_type: Enums.BoardType, _new_level: int) -> void:
	if upgrade_type == Enums.UpgradeType.AUTODROPPER:
		_update_all_button_displays()


func _find_board_for_button(button_id: StringName) -> PlinkoBoard:
	for board in _boards:
		if board.get_drop_button(button_id):
			return board
	return null


func _update_all_button_displays() -> void:
	var free_count := get_free_autodroppers()
	for board in _boards:
		for bid in board._drop_buttons:
			var button: DropButton = board._drop_buttons[bid]
			var assigned: int = _assignments.get(bid, 0)
			button.update_autodropper_state(assigned, free_count)
