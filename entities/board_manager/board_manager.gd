class_name BoardManager
extends Node3D

signal board_switched(board: PlinkoBoard)
signal board_unlocked(board_type: Enums.BoardType)
signal assignments_changed(assignments: Dictionary)
signal first_autodropper_purchased
## Fired once, on the player's very first Deflector purchase (main mode only;
## suppressed in challenges). DeflectorIntroAnimator listens.
signal first_deflector_purchased

const BoardScene: PackedScene = preload("res://entities/plinko_board/plinko_board.tscn")

var board_spacing: float
var camera_tween_duration: float

var _boards: Array[PlinkoBoard] = []
var _active_index: int = 0
var _camera: Camera3D
var _normal_autodroppers_unlocked: bool = false
var _advanced_autodroppers_unlocked: bool = false
var _normal_pool: int = 0
var _advanced_pool: int = 0
var _assignments: Dictionary = {}  # StringName -> int (button_id → assigned count)
var _autodrop_timer: Timer
var _last_tick_msec: float = 0.0
var _camera_tween: Tween
## True while an add-rows glissando is driving the camera. Set by
## `row_upgrade_starting` (emitted *before* build_board, so _on_board_rebuilt
## sees it in time and skips its default fit-tween) and cleared at the end of
## the sweep tween.
var _row_upgrade_camera_active: bool = false
## True while a transient non-prestige cinematic (the cap-raise reveal) has
## borrowed the camera via begin_cinematic_camera(). Suppresses the default
## board_rebuilt fit-tween, exactly like the row-upgrade flag above.
var _cinematic_camera_active: bool = false

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

	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	ChallengeManager.challenge_state_changed.connect(_on_challenge_state_changed_for_targets)


func _process(_delta: float) -> void:
	if _autodrop_timer.is_stopped():
		return
	var progress := get_fill_progress()
	for board in _boards:
		var counts := get_assigned_counts_for_board(board.board_type)
		board.update_queue_fill(progress, counts.advanced, counts.normal)


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


func get_active_index() -> int:
	return _active_index


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
	_update_deflector_editors()
	board_switched.emit(_boards[_active_index])


func _spawn_board(type: Enums.BoardType) -> void:
	var board: PlinkoBoard = BoardScene.instantiate()
	add_child(board)
	board.setup(type)
	# Deflector is a universal upgrade — the slot cap is global, so each board
	# checks the total placed across every board.
	board.deflector_total_query = get_total_deflectors

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
	board.row_upgrade_starting.connect(_on_row_upgrade_starting.bind(board))
	board.row_upgrade_sweep_started.connect(_on_row_upgrade_sweep_started.bind(board))
	board.autodropper_adjust_requested.connect(_on_autodropper_adjust)
	# Queue count changes shift the effective drop delay — refresh subtext.
	board.coin_queue.count_changed.connect(_on_board_queue_count_changed)
	if _normal_autodroppers_unlocked:
		board.set_normal_autodroppers_visible(true)
	if _advanced_autodroppers_unlocked:
		board.set_advanced_autodroppers_visible(true)
	_update_deflector_editors()


## Only the active board's deflector editor consumes mouse input — off-screen
## boards must not raycast or eat clicks.
func _update_deflector_editors() -> void:
	for i in _boards.size():
		_boards[i].set_deflector_input_active(i == _active_index)


## Total deflectors placed across every board (the universal slot pool is
## global). Injected into each PlinkoBoard as deflector_total_query.
func get_total_deflectors() -> int:
	var total := 0
	for board in _boards:
		total += board.deflector_count()
	return total


func is_board_unlocked(type: Enums.BoardType) -> bool:
	for board in _boards:
		if board.board_type == type:
			return true
	return false


func _on_currency_changed(type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
	if _new_balance <= 0:
		if type == Enums.CurrencyType.GOLD_COIN:
			check_and_rescue_gold_soft_lock()
		return
	# When a raw currency is earned, unlock the board if already prestiged.
	# First-time prestige is handled exclusively by the PrestigeAnimator
	# (via PlinkoBoard.prestige_coin_landed) to ensure the animation plays.
	for i in range(1, TierRegistry.get_tier_count()):
		var tier := TierRegistry.get_tier_by_index(i)
		if tier.raw_currency == type:
			if PrestigeManager.is_board_unlocked_permanently(tier.board_type):
				unlock_board(tier.board_type)
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
	# Only adjust the camera if the rebuilt board is the one we're looking at —
	# and not when an add-rows glissando is driving it, since that owns the
	# camera for the whole sweep + settle. Button displays always refresh.
	if board == _boards[_active_index] and not _row_upgrade_camera_active \
			and not _cinematic_camera_active:
		_tween_camera_to_active_board()
	_update_all_button_displays()


## Add-rows glissando is about to begin on this board. Setting the flag here —
## *before* build_board() emits board_rebuilt — is what keeps the default
## fit-tween from racing the sweep camera in _on_board_rebuilt above.
func _on_row_upgrade_starting(board: PlinkoBoard) -> void:
	if board == _boards[_active_index]:
		_row_upgrade_camera_active = true


## Drive the camera through three phases: push in toward the start of the new
## bucket row, track horizontally with the glissando wavefront, then pull back
## out to frame the now-bigger board. Sequential single _camera_tween (kills any
## prior tween, same pattern as _tween_camera_to_active_board) so nothing fights
## it; the final callback clears the suppress flag.
##
## Args (forwarded from `PlinkoBoard.row_upgrade_sweep_started` + `.bind(board)`):
## - `start_local_x`, `end_local_x`: board-local X of bucket 0 and bucket N-1.
## - `focus_local_y`: board-local Y of the bucket row (camera dips to this Y
##   during the track phase for an intimate "watch the keys" framing).
## - `sweep_duration`: total wavefront travel time (= (N-1) * glissando_interval).
## - `board`: bound by .connect — used to compute the world-space settle target.
func _on_row_upgrade_sweep_started(start_local_x: float, end_local_x: float,
		focus_local_y: float, sweep_duration: float, board: PlinkoBoard) -> void:
	if board != _boards[_active_index]:
		# Defensive: `_on_row_upgrade_starting` only sets the flag when the
		# emitting board is active, so this clear should be unreachable.
		# Keeping it for paranoia in case a future caller emits from a
		# different board than the one currently active.
		_row_upgrade_camera_active = false
		return
	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()

	var t: VisualTheme = ThemeProvider.theme
	var zoom_factor: float = t.row_upgrade_camera_zoom_factor
	var zoom_in_duration: float = t.row_upgrade_camera_zoom_in_duration
	var zoom_out_duration: float = t.row_upgrade_camera_zoom_out_duration
	var settle_lead: float = t.row_upgrade_camera_settle_lead
	var pre_drop_delay: float = t.row_upgrade_pre_drop_delay
	var min_track_duration: float = t.row_upgrade_camera_min_track_duration
	var track_extension: float = t.row_upgrade_camera_track_extension
	# Cap the lead to 40% of the sweep so small boards don't end up with a
	# tiny track_duration that whips the camera across well above the
	# wavefront's natural speed (world-units / second = space_between_pegs /
	# glissando_interval = 1.0 / 0.125 = 8 u/s). A 5-bucket board without
	# this cap was hitting 20 u/s — 2.5× the wavefront — and felt whippy.
	# On large boards this is a no-op: the full 0.3s lead still applies.
	var effective_settle_lead: float = minf(settle_lead, sweep_duration * 0.4)
	# If the bucket pre-drop pause is longer than the camera pan-in, the
	# camera should hold at the start position for the remainder so it begins
	# tracking the wavefront exactly when bucket 0 starts dropping. (When the
	# pan-in is the longer of the two, no extra wait is needed; the camera
	# just finishes panning in slightly after buckets start.)
	var post_zoom_hold: float = maxf(0.0, pre_drop_delay - zoom_in_duration)

	var pre_size: float = _camera.size
	var cam_z: float = _camera.position.z
	var start_pos: Vector3 = Vector3(board.position.x + start_local_x,
		board.position.y + focus_local_y, cam_z)
	var end_x: float = board.position.x + end_local_x
	var settle_pos: Vector3 = _get_camera_target(board)
	var settle_size: float = _get_camera_size_for_board(board)
	# Floor at min_track_duration so the smallest boards (first-purchase 5-bucket
	# case) feel no whippier than mid-sized boards. On boards big enough that
	# the natural track is already ≥ this floor, no change. Then extend by
	# track_extension so the camera doesn't snap back to centre the instant
	# the wavefront finishes — it lingers on the right side of the row.
	var track_duration: float = maxf(min_track_duration, sweep_duration - effective_settle_lead) + track_extension

	_camera_tween = create_tween()
	# Phase 1 — push in toward the left edge of the new row. TRANS_QUINT gives a
	# pronounced slow-start / slow-end so the camera glides in instead of
	# snapping; the track phase below uses the gentler CUBIC since it's a
	# steady linear pan.
	_camera_tween.tween_property(_camera, "position", start_pos, zoom_in_duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUINT)
	_camera_tween.parallel().tween_property(_camera, "size", pre_size * zoom_factor, zoom_in_duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUINT)
	# Optional hold so tracking starts in lockstep with the first bucket drop.
	if post_zoom_hold > 0.0:
		_camera_tween.tween_interval(post_zoom_hold)
	# Phase 2 — track the wavefront, holding the zoomed-in framing.
	_camera_tween.tween_property(_camera, "position:x", end_x, track_duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	# Phase 3 — pull back to fit the bigger board. Same TRANS_QUINT softness as
	# the zoom-in, on its own longer duration so the resolve breathes.
	_camera_tween.tween_property(_camera, "position", settle_pos, zoom_out_duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUINT)
	_camera_tween.parallel().tween_property(_camera, "size", settle_size, zoom_out_duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUINT)
	_camera_tween.tween_callback(_clear_row_upgrade_camera_flag)


## Called from the final tween_callback at the end of the add-rows camera
## sweep; method ref over an inline lambda matches the codebase convention
## for non-tween-internal callbacks.
func _clear_row_upgrade_camera_flag() -> void:
	_row_upgrade_camera_active = false


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


## Hand the camera to a transient cinematic (the cap-raise reveal). Kills any
## in-flight camera tween and raises the suppress flag so a board_rebuilt
## fit-tween can't race the cinematic. The caller writes the camera transform
## directly while held, and MUST pair this with end_cinematic_camera().
func begin_cinematic_camera() -> void:
	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()
	_cinematic_camera_active = true


## Return the camera after a cinematic, easing it back to frame the active board.
func end_cinematic_camera() -> void:
	_cinematic_camera_active = false
	_tween_camera_to_active_board()


func _snap_camera_to_active_board() -> void:
	_camera.position = _get_camera_target(_boards[_active_index])


func _tween_camera_to_active_board() -> void:
	# Kill any in-flight camera tween so rapid switches (e.g. peek out-and-back)
	# don't end up with two tweens fighting over the camera.
	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()
	var target := _get_camera_target(_boards[_active_index])
	_camera_tween = create_tween()
	_camera_tween.tween_property(_camera, "position", target, camera_tween_duration) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)
	_camera_tween.parallel().tween_property(_camera, "size", _get_camera_size_for_board(_boards[_active_index]), camera_tween_duration) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)


# --- Autodropper ---

func _is_advanced_button(button_id: StringName) -> bool:
	return (button_id as String).ends_with("_ADVANCED")


func get_normal_pool() -> int:
	return _normal_pool


func get_advanced_pool() -> int:
	return _advanced_pool


func is_normal_autodroppers_unlocked() -> bool:
	return _normal_autodroppers_unlocked


func is_advanced_autodroppers_unlocked() -> bool:
	return _advanced_autodroppers_unlocked


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


func get_fill_progress() -> float:
	if _autodrop_timer.is_stopped():
		return 0.0
	var elapsed := (Time.get_ticks_msec() - _last_tick_msec) / 1000.0
	return clampf(elapsed / _autodrop_timer.wait_time, 0.0, 1.0)


func get_assigned_counts_for_board(bt: Enums.BoardType) -> Dictionary:
	var normal := 0
	var advanced := 0
	for bid in _assignments:
		var count: int = _assignments[bid]
		if count <= 0:
			continue
		var board := _find_board_for_button(bid)
		if not board or board.board_type != bt:
			continue
		if _is_advanced_button(bid):
			advanced += count
		else:
			normal += count
	return { "normal": normal, "advanced": advanced }


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

	# When removing autodroppers, immediately remove FILLING coins
	if delta < 0:
		var board: PlinkoBoard = _find_board_for_button(button_id)
		if board and new_count <= 0:
			board.coin_queue.remove_filling_coins_of_type(is_adv)

	# Start or stop the timer based on whether any autodroppers are assigned
	var total_assigned := _get_assigned_for_pool(false) + _get_assigned_for_pool(true)
	if total_assigned > 0 and _autodrop_timer.is_stopped():
		_autodrop_timer.start()
	elif total_assigned == 0 and not _autodrop_timer.is_stopped():
		_autodrop_timer.stop()

	assignments_changed.emit(_assignments)


func _on_autodrop_tick() -> void:
	_last_tick_msec = Time.get_ticks_msec()
	AudioManager.notify_autodropper_beat(_autodrop_timer.wait_time)

	# Track which boards have at least one normal / advanced autodropper
	# assigned so we can fire one drum per board per kind (rather than one
	# per assigned count — the drum beat is fixed regardless of pool size).
	var boards_with_normal: Dictionary = {}
	var boards_with_advanced: Dictionary = {}

	# Process advanced autodroppers FIRST so they claim queue slots before normal.
	for button_id in _assignments:
		var count: int = _assignments[button_id]
		if count <= 0:
			continue
		if not (button_id as String).ends_with("_ADVANCED"):
			continue
		var board := _find_board_for_button(button_id)
		if not board:
			continue
		boards_with_advanced[board.board_type] = true
		for i in count:
			board.try_autodrop(true)

	# Then process normal autodroppers.
	for button_id in _assignments:
		var count: int = _assignments[button_id]
		if count <= 0:
			continue
		if (button_id as String).ends_with("_ADVANCED"):
			continue
		var board := _find_board_for_button(button_id)
		if not board:
			continue
		boards_with_normal[board.board_type] = true
		for i in count:
			board.try_autodrop(false)

	# One drum hit per board per kind. AudioManager gates against the active
	# board internally, so only the viewed board contributes to the groove.
	for board_type in boards_with_normal:
		AudioManager.play_autodropper_drum(board_type, false)
	for board_type in boards_with_advanced:
		AudioManager.play_autodropper_drum(board_type, true)


func _on_upgrade_purchased(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType, _new_level: int) -> void:
	if upgrade_type == Enums.UpgradeType.AUTODROPPER:
		_normal_pool += 1
		if not _normal_autodroppers_unlocked:
			_normal_autodroppers_unlocked = true
			# Skip the intro in challenge mode — the animator only lives in
			# main scene setup, so the signal would fire into the void and
			# the player would never see the animation.
			if not OnboardingProgress.has_seen_autodropper_intro() \
					and not ChallengeManager.is_active_challenge:
				# First-ever autodropper: fire the intro animation instead of
				# auto-assigning. AutodropperIntroAnimator calls
				# reveal_autodropper_controls() when particles land.
				first_autodropper_purchased.emit()
				_update_all_button_displays()
				return
			for board in _boards:
				board.set_normal_autodroppers_visible(true)
		# New autodroppers stay in the free pool; the player assigns them
		# manually. They are never auto-assigned to gold.
		_update_all_button_displays()
	elif upgrade_type == Enums.UpgradeType.ADVANCED_AUTODROPPER:
		_advanced_pool += 1
		if not _advanced_autodroppers_unlocked:
			_advanced_autodroppers_unlocked = true
			for board in _boards:
				board.set_advanced_autodroppers_visible(true)
		# New advanced autodroppers stay in the free pool; the player assigns
		# them manually. They are never auto-assigned to gold.
		_update_all_button_displays()
	elif upgrade_type == Enums.UpgradeType.PEG_DEFLECTOR:
		# First-ever deflector: play the intro once. The animator only lives in
		# main-scene setup, so suppress in challenges (signal would fire into the
		# void). has_seen_deflector_intro() gates replays; the animator marks it.
		if not OnboardingProgress.has_seen_deflector_intro() \
				and not ChallengeManager.is_active_challenge:
			first_deflector_purchased.emit()
	if board_type == Enums.BoardType.GOLD:
		check_and_rescue_gold_soft_lock()


## Called by AutodropperIntroAnimator after the intro particles land. Shows
## +/– controls on all boards and refreshes button state without auto-assigning.
func reveal_autodropper_controls() -> void:
	for board in _boards:
		board.set_normal_autodroppers_visible(true)
	_update_all_button_displays()


## If the player has 0 gold and no coins are mid-flight or queued on the gold
## board, grant 1 gold so they can always make a drop. Called after upgrade
## purchases, after any currency-changed event that zeroes gold, and on load.
func check_and_rescue_gold_soft_lock() -> void:
	if CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN) >= 1:
		return
	var gold_board: PlinkoBoard = _find_board(Enums.BoardType.GOLD)
	if gold_board == null:
		return
	if gold_board.has_in_flight_coins():
		return
	if not gold_board.coin_queue.is_empty():
		return
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 1)
	print("[BoardManager] Soft-lock rescue: granted 1 gold.")


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
		# Update drop rate subtext (reflects queue bonus)
		var effective: float = board.get_effective_drop_delay()
		var delay_str: String
		if effective == int(effective):
			delay_str = str(int(effective)) + "s"
		else:
			delay_str = "%.1fs" % effective
		for bid in board.get_drop_button_ids():
			var is_adv := _is_advanced_button(bid)
			var autodrop_unlocked: bool = (_advanced_autodroppers_unlocked if is_adv else _normal_autodroppers_unlocked)
			if autodrop_unlocked:
				var assigned: int = _assignments.get(bid, 0)
				board.set_drop_subtext(bid, "auto %d · %s" % [assigned, delay_str])
			else:
				board.set_drop_subtext(bid, delay_str)


func _on_board_queue_count_changed(_new_count: int) -> void:
	_update_all_button_displays()


func serialize() -> Dictionary:
	var data := {}
	data["normal_autodroppers_unlocked"] = _normal_autodroppers_unlocked
	data["advanced_autodroppers_unlocked"] = _advanced_autodroppers_unlocked
	data["normal_pool"] = _normal_pool
	data["advanced_pool"] = _advanced_pool

	# Which boards are spawned
	var board_types: Array[int] = []
	for board in _boards:
		board_types.append(board.board_type)
	data["board_types"] = board_types

	# Which boards have advanced buckets visible / advanced drop bar shown
	var advanced_buckets := {}
	var advanced_drops := {}
	for board in _boards:
		var key: String = Enums.BoardType.keys()[board.board_type]
		advanced_buckets[key] = board.should_show_advanced_buckets
		advanced_drops[key] = board._has_advanced_drop
	data["advanced_buckets"] = advanced_buckets
	data["advanced_drops"] = advanced_drops

	# Per-board computed state (read by OfflineCalculator)
	var board_state := {}
	for board in _boards:
		var key: String = Enums.BoardType.keys()[board.board_type]
		var acm_bonus: float = ChallengeProgressManager.get_advanced_coin_multiplier_bonus(board.board_type)
		board_state[key] = {
			"num_rows": board.num_rows,
			"drop_delay": board.drop_delay,
			"bucket_value_multiplier": board.bucket_value_multiplier,
			"advanced_coin_multiplier": board.advanced_coin_multiplier - acm_bonus,
			"distance_for_advanced_buckets": board.distance_for_advanced_buckets,
			"multi_drop_count": board.multi_drop_count,
			"deflectors": board.serialize_deflectors(),
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
	var advanced_drops: Dictionary = data.get("advanced_drops", {})
	var board_state: Dictionary = data.get("board_state", {})
	for board in _boards:
		var board_key: String = Enums.BoardType.keys()[board.board_type]
		var bs: Dictionary = board_state.get(board_key, {})
		var upgrade_state := {}
		for upgrade_type in Enums.UpgradeType.values():
			var upgrade_key: String = Enums.UpgradeType.keys()[upgrade_type]
			upgrade_state[upgrade_key] = UpgradeManager.get_level(board.board_type, upgrade_type)
		upgrade_state["show_advanced_buckets"] = advanced_buckets.get(board_key, false)
		# Old saves lack advanced_drops. Fall back to checking whether the player
		# actually has the raw currency — if balance is 0 the bar shouldn't show.
		# _on_currency_changed (fired by CurrencyManager.deserialize before this
		# runs) already shows the bar when balance > 0, so false is safe here.
		upgrade_state["has_advanced_drop"] = advanced_drops.get(board_key, false)
		upgrade_state["advanced_coin_multiplier"] = bs.get("advanced_coin_multiplier", 2)
		# Old saves lack "deflectors" — defaults to none (graceful, no migration).
		upgrade_state["deflectors"] = bs.get("deflectors", [])
		board.apply_saved_state(upgrade_state)

	# Restore autodropper state
	_normal_autodroppers_unlocked = data.get("normal_autodroppers_unlocked",
		data.get("autodroppers_unlocked", false))  # backward compat
	_advanced_autodroppers_unlocked = data.get("advanced_autodroppers_unlocked", false)

	# Pool counters — backward compat: old saves derive from per-board upgrade levels.
	if data.has("normal_pool"):
		_normal_pool = data["normal_pool"]
		_advanced_pool = data.get("advanced_pool", 0)
	else:
		for board_type in Enums.BoardType.values():
			_normal_pool += UpgradeManager.get_level(board_type, Enums.UpgradeType.AUTODROPPER)
			_advanced_pool += UpgradeManager.get_level(board_type, Enums.UpgradeType.ADVANCED_AUTODROPPER)
	if _normal_autodroppers_unlocked:
		for board in _boards:
			board.set_normal_autodroppers_visible(true)
	if _advanced_autodroppers_unlocked:
		for board in _boards:
			board.set_advanced_autodroppers_visible(true)

	var assignments_data: Dictionary = data.get("assignments", {})
	for key in assignments_data:
		_assignments[StringName(key)] = assignments_data[key]

	_apply_prestige_rewards()

	var total_assigned := _get_assigned_for_pool(false) + _get_assigned_for_pool(true)
	if total_assigned > 0:
		_autodrop_timer.start()
	_update_all_button_displays()
	assignments_changed.emit(_assignments)

	# Re-frame camera on active board
	_snap_camera_to_active_board()
	_update_deflector_editors()


## Apply one-time prestige rewards. Called at the end of deserialize so the
## bonus is present on every load (fresh prestige reset or normal save).
func _apply_prestige_rewards() -> void:
	# Gold prestige reward: guarantee 1 normal autodropper on gold board.
	# Orange being unlocked permanently means the player completed gold prestige.
	if PrestigeManager.is_board_unlocked_permanently(Enums.BoardType.ORANGE):
		if not _normal_autodroppers_unlocked:
			_normal_autodroppers_unlocked = true
			for board in _boards:
				board.set_normal_autodroppers_visible(true)
		if _normal_pool < 1:
			_normal_pool = 1
		if _assignments.get(StringName("GOLD_NORMAL"), 0) < 1:
			_assignments[StringName("GOLD_NORMAL")] = 1

	# Orange-board prestige reward: one permanent peg deflector, auto-placed
	# once on the gold board's first peg. The flag (persisted, survives resets)
	# means we never re-seed — the player is free to move or remove it after.
	if PrestigeManager.get_permanent_deflector_count() > 0 \
			and not OnboardingProgress.has_seeded_prestige_deflector():
		var gold: PlinkoBoard = _find_board(Enums.BoardType.GOLD)
		if gold:
			gold.seed_first_peg_deflector()
			OnboardingProgress.mark_prestige_deflector_seeded()


func _exit_tree() -> void:
	if ChallengeManager.challenge_state_changed.is_connected(_on_challenge_state_changed_for_targets):
		ChallengeManager.challenge_state_changed.disconnect(_on_challenge_state_changed_for_targets)


func _on_challenge_state_changed_for_targets() -> void:
	# 2x bonus bucket is main-mode only — disabled for every challenge.
	var enabled := not ChallengeManager.is_active_challenge
	for board in _boards:
		board.set_gameplay_target_enabled(enabled)
