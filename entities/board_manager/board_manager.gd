class_name BoardManager
extends Node3D

signal board_switched(board: PlinkoBoard)
signal board_unlocked(board_type: Enums.BoardType)

const BoardScene: PackedScene = preload("res://entities/plinko_board/plinko_board.tscn")

var board_spacing: float
var camera_tween_duration: float

var _boards: Array[PlinkoBoard] = []
var _active_index: int = 0
var _camera: Camera3D
var _normal_autodroppers_unlocked: bool = false
var _advanced_autodroppers_unlocked: bool = false
var _assignments: Dictionary = {}  # StringName -> int (button_id → assigned count)
var _autodrop_timer: Timer

## Optional gate callable: Callable(board_type: Enums.BoardType) -> bool
## Set by ChallengeManager to restrict boards during challenges.
var board_gate: Callable

## Minimum Z distance so the camera doesn't get too close on small boards
const MIN_CAMERA_Z := 6.0


func setup(camera: Camera3D) -> void:
	_camera = camera
	board_spacing = ThemeProvider.theme.board_spacing
	camera_tween_duration = ThemeProvider.theme.camera_tween_duration
	# Start with the first tier's board
	_spawn_board(TierRegistry.get_tier_by_index(0).board_type)
	# Frame the camera on the initial board immediately (no tween)
	_snap_camera_to_active_board()
	CurrencyManager.currency_changed.connect(_on_currency_changed)
	LevelManager.rewards_claimed.connect(_on_rewards_claimed)

	# Autodropper timer (1 tick per second, starts paused)
	_autodrop_timer = Timer.new()
	_autodrop_timer.wait_time = 1.5
	_autodrop_timer.autostart = false
	_autodrop_timer.timeout.connect(_on_autodrop_tick)
	add_child(_autodrop_timer)

	UpgradeManager.autodropper_unlocked.connect(_on_autodropper_unlocked)
	UpgradeManager.advanced_autodropper_unlocked.connect(_on_advanced_autodropper_unlocked)
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)


func _input(event: InputEvent) -> void:
	if ModeManager.is_challenges():
		return
	if event.is_action_pressed("board_left"):
		switch_board(_active_index - 1)
	elif event.is_action_pressed("board_right"):
		switch_board(_active_index + 1)


func set_active_board_ui_visible(visible: bool) -> void:
	_boards[_active_index].upgrade_section.visible = visible
	_boards[_active_index].drop_section.visible = visible


func get_active_board() -> PlinkoBoard:
	return _boards[_active_index]


func get_boards() -> Array[PlinkoBoard]:
	return _boards


## Call this when a new board type is unlocked (e.g. orange, red).
func unlock_board(type: Enums.BoardType) -> void:
	if board_gate.is_valid() and not board_gate.call(type):
		return
	# Don't spawn duplicates
	for board in _boards:
		if board.board_type == type:
			return
	_spawn_board(type)
	board_unlocked.emit(type)


func switch_board(index: int) -> void:
	if index < 0 or index >= _boards.size():
		return
	if index == _active_index:
		return

	# Hide old board's UI + coins, show new board's UI + coins
	_boards[_active_index].upgrade_section.visible = false
	_boards[_active_index].drop_section.visible = false
	_boards[_active_index].set_coins_visible(false)
	_active_index = index
	_boards[_active_index].upgrade_section.visible = true
	_boards[_active_index].drop_section.visible = true
	_boards[_active_index].set_coins_visible(true)

	AudioManager.set_active_board(_boards[_active_index].board_type)
	_tween_camera_to_active_board()
	board_switched.emit(_boards[_active_index])


func _spawn_board(type: Enums.BoardType) -> void:
	var board: PlinkoBoard = BoardScene.instantiate()
	add_child(board)
	board.setup(type)

	# Insert at correct tier position so board order always matches tier order
	var tier_index := TierRegistry.get_tier_index(type)
	var insert_at := _boards.size()
	for i in _boards.size():
		if TierRegistry.get_tier_index(_boards[i].board_type) > tier_index:
			insert_at = i
			break
	_boards.insert(insert_at, board)

	# Reposition all boards to reflect new order
	for i in _boards.size():
		_boards[i].position = Vector3(i * board_spacing, 0, 0)

	# Only the active board's UI + coins should be visible
	if insert_at != _active_index:
		board.upgrade_section.visible = false
		board.drop_section.visible = false
		board.set_coins_visible(false)

	board.board_rebuilt.connect(_on_board_rebuilt.bind(board))
	board.autodropper_adjust_requested.connect(_on_autodropper_adjust)
	if _normal_autodroppers_unlocked:
		board.set_normal_autodroppers_visible(true)
	if _advanced_autodroppers_unlocked:
		board.set_advanced_autodroppers_visible(true)

func is_board_unlocked(type: Enums.BoardType) -> bool:
	for board in _boards:
		if board.board_type == type:
			return true
	return false


func _on_currency_changed(type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
	if _new_balance <= 0:
		return
	# When a raw currency is earned, unlock or prestige the board it belongs to.
	for i in range(1, TierRegistry.get_tier_count()):
		var tier := TierRegistry.get_tier_by_index(i)
		if tier.raw_currency == type:
			if PrestigeManager.is_board_unlocked_permanently(tier.board_type):
				unlock_board(tier.board_type)
			elif PrestigeManager.can_prestige(tier.board_type):
				PrestigeManager.trigger_prestige(tier.board_type)
			break


func _on_rewards_claimed(_level: int, rewards: Array[RewardData]) -> void:
	for reward in rewards:
		if reward.type != RewardData.RewardType.DROP_COINS:
			continue
		# Don't yank the camera to a different board for advanced/raw coin drops —
		# the player should stay on whatever they're looking at.
		if TierRegistry.is_raw_currency(reward.coin_type):
			continue
		if reward.target_board != _boards[_active_index].board_type:
			_switch_to_board_type(reward.target_board)
			return


func _switch_to_board_type(type: Enums.BoardType) -> void:
	for i in _boards.size():
		if _boards[i].board_type == type:
			switch_board(i)
			return


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

func _get_camera_size_for_board(board: PlinkoBoard) -> float:
	var bounds := board.get_bounds()
	var height := bounds.size.y + 5.0  # Add some padding so the top row isn't cut off
	var width := bounds.size.x
	return max(height, width)


func _snap_camera_to_active_board() -> void:
	_camera.position = _get_camera_target(_boards[_active_index])


func _tween_camera_to_active_board() -> void:
	var target := _get_camera_target(_boards[_active_index])
	var tween := create_tween()
	tween.tween_property(_camera, "position", target, camera_tween_duration) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(_camera, "size", _get_camera_size_for_board(_boards[_active_index]), camera_tween_duration) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)


# --- Autodropper ---

func _is_advanced_button(button_id: StringName) -> bool:
	return (button_id as String).ends_with("_ADVANCED")


func get_normal_pool() -> int:
	return UpgradeManager.get_level(Enums.BoardType.ORANGE, Enums.UpgradeType.AUTODROPPER)


func get_advanced_pool() -> int:
	return UpgradeManager.get_level(Enums.BoardType.RED, Enums.UpgradeType.ADVANCED_AUTODROPPER)


func _get_assigned_for_pool(advanced: bool) -> int:
	var total := 0
	for bid in _assignments:
		if _is_advanced_button(bid) == advanced:
			total += _assignments[bid]
	return total


func get_free_autodroppers() -> int:
	return get_normal_pool() - _get_assigned_for_pool(false)


func get_free_advanced_autodroppers() -> int:
	return get_advanced_pool() - _get_assigned_for_pool(true)


func _on_autodropper_unlocked() -> void:
	_normal_autodroppers_unlocked = true
	for board in _boards:
		board.set_normal_autodroppers_visible(true)


func _on_advanced_autodropper_unlocked() -> void:
	_advanced_autodroppers_unlocked = true
	for board in _boards:
		board.set_advanced_autodroppers_visible(true)


func _on_autodropper_adjust(button_id: StringName, delta: int, from_player: bool = true) -> void:
	# During an active challenge the player isn't allowed to add or remove
	# autodroppers — only the challenge itself (via from_player = false) can.
	if from_player and ChallengeManager.is_active_challenge:
		return

	var current: int = _assignments.get(button_id, 0)
	var new_count: int = current + delta

	if new_count < 0:
		return

	var is_adv := _is_advanced_button(button_id)
	var free: int = get_free_advanced_autodroppers() if is_adv else get_free_autodroppers()
	if delta > 0 and free <= 0:
		return

	_assignments[button_id] = new_count
	_update_all_button_displays()

	# Start or stop the timer based on whether any autodroppers are assigned
	var total_assigned := _get_assigned_for_pool(false) + _get_assigned_for_pool(true)
	if total_assigned > 0 and _autodrop_timer.is_stopped():
		_autodrop_timer.start()
	elif total_assigned == 0 and not _autodrop_timer.is_stopped():
		_autodrop_timer.stop()


func _on_autodrop_tick() -> void:
	# Track which boards have at least one normal / advanced autodropper
	# assigned so we can fire one drum per board per kind (rather than one
	# per assigned count — the drum beat is fixed regardless of pool size).
	var boards_with_normal: Dictionary = {}
	var boards_with_advanced: Dictionary = {}

	for button_id in _assignments:
		var count: int = _assignments[button_id]
		if count <= 0:
			continue
		var board := _find_board_for_button(button_id)
		if not board:
			continue
		var is_advanced: bool = (button_id as String).ends_with("_ADVANCED")
		if is_advanced:
			boards_with_advanced[board.board_type] = true
		else:
			boards_with_normal[board.board_type] = true
		for i in count:
			board.try_autodrop(is_advanced)

	# One drum hit per board per kind. AudioManager gates against the active
	# board internally, so only the viewed board contributes to the groove.
	for board_type in boards_with_normal:
		AudioManager.play_autodropper_drum(board_type, false)
	for board_type in boards_with_advanced:
		AudioManager.play_autodropper_drum(board_type, true)


func _on_upgrade_purchased(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType, _new_level: int) -> void:
	if upgrade_type == Enums.UpgradeType.AUTODROPPER or upgrade_type == Enums.UpgradeType.ADVANCED_AUTODROPPER:
		_update_all_button_displays()
	if board_type == Enums.BoardType.GOLD:
		_check_and_rescue_gold_soft_lock()


## After a gold-board upgrade purchase, verify the player can still produce
## gold or raw orange. Gold and raw orange are the only "source" currencies —
## only the gold board generates them — so if both are zero and no coins are
## mid-flight or queued there, the player is soft-locked. Grant 1 gold to
## unstick them.
func _check_and_rescue_gold_soft_lock() -> void:
	if CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN) >= 1:
		return
	if CurrencyManager.get_balance(Enums.CurrencyType.RAW_ORANGE) >= 1:
		return
	var gold_board: PlinkoBoard = _find_board(Enums.BoardType.GOLD)
	if gold_board == null:
		return
	if gold_board.has_in_flight_coins():
		return
	if not gold_board.coin_queue.is_empty():
		return
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 1)
	print("[BoardManager] Soft-lock detected after gold upgrade purchase; granted 1 gold.")


func _find_board(type: Enums.BoardType) -> PlinkoBoard:
	for board in _boards:
		if board.board_type == type:
			return board
	return null


func _find_board_for_button(button_id: StringName) -> PlinkoBoard:
	for board in _boards:
		if board.get_drop_button(button_id):
			return board
	return null


func _update_all_button_displays() -> void:
	var normal_free := get_free_autodroppers()
	var advanced_free := get_free_advanced_autodroppers()
	for board in _boards:
		board.update_autodropper_buttons(_assignments, normal_free, advanced_free)


func serialize() -> Dictionary:
	var data := {}
	data["normal_autodroppers_unlocked"] = _normal_autodroppers_unlocked
	data["advanced_autodroppers_unlocked"] = _advanced_autodroppers_unlocked

	# Which boards are spawned
	var board_types: Array[int] = []
	for board in _boards:
		board_types.append(board.board_type)
	data["board_types"] = board_types

	# Which boards have advanced buckets visible
	var advanced_buckets := {}
	for board in _boards:
		var key: String = Enums.BoardType.keys()[board.board_type]
		advanced_buckets[key] = board.should_show_advanced_buckets
	data["advanced_buckets"] = advanced_buckets

	# Per-board computed state (read by OfflineCalculator)
	var board_state := {}
	for board in _boards:
		var key: String = Enums.BoardType.keys()[board.board_type]
		board_state[key] = {
			"num_rows": board.num_rows,
			"drop_delay": board.drop_delay,
			"bucket_value_multiplier": board.bucket_value_multiplier,
			"advanced_coin_multiplier": board.advanced_coin_multiplier,
			"distance_for_advanced_buckets": board.distance_for_advanced_buckets,
			"multi_drop_count": board.multi_drop_count,
		}
	data["board_state"] = board_state

	# Autodropper assignments (StringName -> int)
	var assignments_data := {}
	for button_id in _assignments:
		assignments_data[String(button_id)] = _assignments[button_id]
	data["assignments"] = assignments_data

	return data


func deserialize(data: Dictionary) -> void:
	# Spawn any boards beyond gold
	var board_types: Array = data.get("board_types", [0])
	for board_type_int in board_types:
		var board_type: Enums.BoardType = board_type_int as Enums.BoardType
		unlock_board(board_type)

	# Build per-board upgrade state for apply_saved_state
	var advanced_buckets: Dictionary = data.get("advanced_buckets", {})
	var board_state: Dictionary = data.get("board_state", {})
	for board in _boards:
		var board_key: String = Enums.BoardType.keys()[board.board_type]
		var bs: Dictionary = board_state.get(board_key, {})
		var upgrade_state := {}
		for upgrade_type in Enums.UpgradeType.values():
			var upgrade_key: String = Enums.UpgradeType.keys()[upgrade_type]
			upgrade_state[upgrade_key] = UpgradeManager.get_level(board.board_type, upgrade_type)
		upgrade_state["show_advanced_buckets"] = advanced_buckets.get(board_key, false)
		upgrade_state["advanced_coin_multiplier"] = bs.get("advanced_coin_multiplier", 2)
		board.apply_saved_state(upgrade_state)

	# Restore autodropper state
	_normal_autodroppers_unlocked = data.get("normal_autodroppers_unlocked",
		data.get("autodroppers_unlocked", false))  # backward compat
	_advanced_autodroppers_unlocked = data.get("advanced_autodroppers_unlocked", false)
	if _normal_autodroppers_unlocked:
		for board in _boards:
			board.set_normal_autodroppers_visible(true)
	if _advanced_autodroppers_unlocked:
		for board in _boards:
			board.set_advanced_autodroppers_visible(true)

	var assignments_data: Dictionary = data.get("assignments", {})
	for key in assignments_data:
		_assignments[StringName(key)] = assignments_data[key]

	var total_assigned := _get_assigned_for_pool(false) + _get_assigned_for_pool(true)
	if total_assigned > 0:
		_autodrop_timer.start()
	_update_all_button_displays()

	# Re-frame camera on active board
	_snap_camera_to_active_board()
