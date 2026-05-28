class_name PeekAnimator
extends Node

## Drives a brief auto-pan to a newly-unlocked navigation target (new board or
## challenges-first-unlocked), then returns to the player's prior view. Input
## is locked during the peek (and during the prestige sequence — wired through
## Main's apply_input_lock_fn).

## Callables — set by Main before setup() if production wiring needed;
## tests inject their own no-op or recording variants.
var loading_query: Callable
var switch_board_fn: Callable
var switch_to_challenges_fn: Callable
var switch_to_main_fn: Callable
var apply_input_lock_fn: Callable
var wait_fn: Callable  # (seconds: float) -> void awaitable
## Optional hook run in place of the linger wait during a board peek. When set,
## `_run_board_peek` awaits this instead of `wait_fn(peek_linger_duration)`, so
## the camera holds on the peeked board for as long as the hook takes. Used by
## `Main` to play the milestone-bar spawn-in animation during the peek. Board-
## only — challenges peek is unaffected.
var peek_linger_hook: Callable

var _queue: Array[PeekRequest] = []
var _is_peeking: bool = false
## Set true by CapRaiseRevealAnimator so a newly-unlocked-board peek waits until
## its reveal cinematic finishes; the peek stays queued, just not drained.
var _drain_deferred: bool = false
var _board_manager: BoardManager
var _challenge_grouping_manager: ChallengeGroupingManager
## Tracked so we can detect when `current_level` advances forward across a tier
## boundary (e.g. crossing gold's final milestone into the orange tier). On
## post-prestige replays the next-tier board is already spawned, so
## `board_unlocked` never re-fires — the tier crossing IS the trigger.
var _last_tier_seen: int = -1

@onready var _linger_timer: Timer = $LingerTimer


func setup(board_manager: BoardManager, challenge_grouping_manager: ChallengeGroupingManager = null) -> void:
	_board_manager = board_manager
	_challenge_grouping_manager = challenge_grouping_manager

	# Fill in any Callables not pre-injected by Main/tests with production defaults.
	if not switch_board_fn.is_valid():
		switch_board_fn = func(idx: int) -> void: board_manager.switch_board(idx)
	if not switch_to_challenges_fn.is_valid():
		switch_to_challenges_fn = func() -> void: ModeManager.switch_to_challenges()
	if not switch_to_main_fn.is_valid():
		switch_to_main_fn = func() -> void: ModeManager.switch_to_main()
	if not wait_fn.is_valid():
		wait_fn = _default_wait
	if not loading_query.is_valid():
		loading_query = func() -> bool: return false
	if not apply_input_lock_fn.is_valid():
		apply_input_lock_fn = func(_locked: bool) -> void: pass

	board_manager.board_unlocked.connect(_on_board_unlocked)
	PrestigeManager.prestige_phase_changed.connect(_on_prestige_phase_changed)
	LevelManager.level_changed.connect(_on_level_changed)
	_last_tier_seen = LevelManager.current_level / LevelManager.LEVELS_PER_TIER


func is_peeking() -> bool:
	return _is_peeking


func is_input_locked() -> bool:
	return _is_peeking or PrestigeManager.current_phase != PrestigeManager.PrestigePhase.NONE


## Called by Main once after SaveManager.load_game(). Detects any unlocked
## navigation targets the player hasn't been peeked at yet and enqueues them.
## Only queues board peeks when the player has actually crossed into that
## board's tier — otherwise the post-prestige reload would peek an empty
## next-tier board before the player even started gold-tier progression.
func queue_peeks_for_existing_unlocks() -> void:
	if not is_instance_valid(_board_manager):
		return
	for board in _board_manager.get_boards():
		if board.board_type == Enums.BoardType.GOLD:
			continue
		if OnboardingProgress.has_peeked_board(board.board_type):
			continue
		var board_tier_idx: int = TierRegistry.get_tier_index(board.board_type)
		var board_tier_start: int = board_tier_idx * LevelManager.LEVELS_PER_TIER
		if LevelManager.current_level < board_tier_start:
			continue
		_queue.append(PeekRequest.for_board(board.board_type))

	if ModeManager.are_challenges_unlocked() \
		and not OnboardingProgress.has_peeked_challenges() \
		and not ChallengeProgressManager.challenges_ever_visited:
		_queue.append(PeekRequest.for_challenges())

	_try_drain()


func _on_board_unlocked(board_type: Enums.BoardType) -> void:
	if board_type == Enums.BoardType.GOLD:
		return
	if loading_query.call():
		return
	if OnboardingProgress.has_peeked_board(board_type):
		return
	if ChallengeManager.is_active_challenge:
		return
	_queue.append(PeekRequest.for_board(board_type))
	_try_drain()


## Fires every `level_changed` and queues a peek if `current_level` just
## advanced into a higher tier. On the first prestige cycle the board's
## `unlock_board` fires `board_unlocked` and that path queues the peek; on
## later cycles the next-tier board is already in `_boards` (so unlock_board
## short-circuits) and the tier-crossing IS the only available trigger.
## `_last_tier_seen` advances only after the TRANSIENT guards (loading,
## challenge) pass — otherwise a crossing that happened to fire during a
## challenge would be silently lost forever, never re-attempting once the
## guard clears.
func _on_level_changed(new_level: int) -> void:
	var new_tier: int = new_level / LevelManager.LEVELS_PER_TIER
	if new_tier <= _last_tier_seen:
		# Backward (prestige reset) or same tier — sync and bail.
		_last_tier_seen = new_tier
		return
	# Transient guards: don't advance `_last_tier_seen`, so the next
	# level_changed (after the guard clears) will re-detect the crossing.
	if loading_query.call():
		return
	if ChallengeManager.is_active_challenge:
		return
	# Past the transient guards — claim this tier as seen so future fires
	# don't re-attempt regardless of what happens below.
	_last_tier_seen = new_tier
	if not is_instance_valid(_board_manager):
		return
	if new_tier >= TierRegistry.get_tier_count():
		return
	var tier: TierData = TierRegistry.get_tier_by_index(new_tier)
	if tier == null or not _board_manager.is_board_unlocked(tier.board_type):
		return
	if OnboardingProgress.has_peeked_board(tier.board_type):
		return
	for req in _queue:
		if req.kind == Enums.PeekKind.BOARD and req.board_type == tier.board_type:
			return
	_queue.append(PeekRequest.for_board(tier.board_type))
	_try_drain()


func _on_prestige_phase_changed(phase: PrestigeManager.PrestigePhase) -> void:
	if phase != PrestigeManager.PrestigePhase.NONE:
		_queue.clear()
		if is_instance_valid(_linger_timer) and not _linger_timer.is_stopped():
			_linger_timer.stop()
		_is_peeking = false
		apply_input_lock_fn.call(true)
	else:
		apply_input_lock_fn.call(_is_peeking)
		_try_drain()


## Hold (or release) the peek queue. CapRaiseRevealAnimator defers the
## new-board peek until its reveal cinematic is done; releasing drains whatever
## queued up in the meantime.
func set_drain_deferred(deferred: bool) -> void:
	_drain_deferred = deferred
	if not deferred:
		_try_drain()


func _try_drain() -> void:
	if _is_peeking:
		return
	if _drain_deferred:
		return
	if _queue.is_empty():
		return
	if PrestigeManager.current_phase != PrestigeManager.PrestigePhase.NONE:
		return
	if ChallengeManager.is_active_challenge:
		return
	_drain_loop()


func _drain_loop() -> void:
	_is_peeking = true
	apply_input_lock_fn.call(true)

	while not _queue.is_empty():
		if PrestigeManager.current_phase != PrestigeManager.PrestigePhase.NONE:
			break
		var request: PeekRequest = _queue.pop_front()
		await _run_peek(request)

	_is_peeking = false
	apply_input_lock_fn.call(PrestigeManager.current_phase != PrestigeManager.PrestigePhase.NONE)


func _run_peek(request: PeekRequest) -> void:
	# Temporarily borrow BoardManager + ChallengeGroupingManager's camera_tween_duration
	# for the duration of the peek so each transition feels gentle, then restore.
	# Owners are unaware their state was borrowed — keep all early-returns inside
	# this function so the restore at the bottom always runs.
	var theme: VisualTheme = ThemeProvider.theme
	var bm_original: float = 0.0
	var cgm_original: float = 0.0
	if is_instance_valid(_board_manager):
		bm_original = _board_manager.camera_tween_duration
		_board_manager.camera_tween_duration = theme.peek_camera_tween_duration
	if is_instance_valid(_challenge_grouping_manager):
		cgm_original = _challenge_grouping_manager.camera_tween_duration
		_challenge_grouping_manager.camera_tween_duration = theme.peek_camera_tween_duration

	if request.kind == Enums.PeekKind.BOARD:
		await _run_board_peek(request.board_type)
	else:
		await _run_challenges_peek()

	if is_instance_valid(_board_manager):
		_board_manager.camera_tween_duration = bm_original
	if is_instance_valid(_challenge_grouping_manager):
		_challenge_grouping_manager.camera_tween_duration = cgm_original


func _run_board_peek(target_type: Enums.BoardType) -> void:
	if not is_instance_valid(_board_manager):
		return

	var theme: VisualTheme = ThemeProvider.theme
	var saved_index: int = _board_manager.get_active_index()
	var saved_was_main: bool = ModeManager.is_main()

	if not saved_was_main:
		switch_to_main_fn.call()
		await wait_fn.call(theme.peek_camera_tween_duration)

	var target_index := -1
	var boards := _board_manager.get_boards()
	for i in boards.size():
		if boards[i].board_type == target_type:
			target_index = i
			break
	if target_index == -1:
		return
	if target_index == saved_index:
		# Player is already looking at the just-unlocked board — no camera move needed,
		# just record it as peeked so we don't re-attempt next session.
		OnboardingProgress.mark_board_peeked(target_type)
		SaveManager.save_game()
		return

	switch_board_fn.call(target_index)
	await wait_fn.call(theme.peek_camera_tween_duration)  # tween out
	if not is_instance_valid(_board_manager):
		return
	if PrestigeManager.current_phase != PrestigeManager.PrestigePhase.NONE:
		return

	if peek_linger_hook.is_valid():
		await peek_linger_hook.call()
	else:
		await wait_fn.call(theme.peek_linger_duration)  # hold
	if not is_instance_valid(_board_manager):
		return
	if PrestigeManager.current_phase != PrestigeManager.PrestigePhase.NONE:
		return

	switch_board_fn.call(saved_index)
	await wait_fn.call(theme.peek_camera_tween_duration)  # tween back
	if PrestigeManager.current_phase != PrestigeManager.PrestigePhase.NONE:
		return

	if not saved_was_main:
		switch_to_challenges_fn.call()
		await wait_fn.call(theme.peek_camera_tween_duration)

	OnboardingProgress.mark_board_peeked(target_type)
	SaveManager.save_game()


func _run_challenges_peek() -> void:
	var theme: VisualTheme = ThemeProvider.theme
	var was_main: bool = ModeManager.is_main()

	# If the player is already in challenges mode (e.g. they jumped there in the
	# session before the peek queue drained), there's nothing to peek to — just
	# linger and mark it done. The was_main branches below all skip in that case.
	# Pre-pause: let the player register their normal view before the peek pulls them away.
	if was_main:
		await wait_fn.call(theme.peek_pre_challenges_pause)
		if PrestigeManager.current_phase != PrestigeManager.PrestigePhase.NONE:
			return
		switch_to_challenges_fn.call()
		await wait_fn.call(theme.peek_camera_tween_duration)  # tween out
		if PrestigeManager.current_phase != PrestigeManager.PrestigePhase.NONE:
			return

	await wait_fn.call(theme.peek_linger_duration)  # hold
	if PrestigeManager.current_phase != PrestigeManager.PrestigePhase.NONE:
		return

	if was_main:
		switch_to_main_fn.call()
		await wait_fn.call(theme.peek_camera_tween_duration)  # tween back
		if PrestigeManager.current_phase != PrestigeManager.PrestigePhase.NONE:
			return

	OnboardingProgress.mark_challenges_peeked()
	SaveManager.save_game()


func _default_wait(seconds: float) -> void:
	if not is_instance_valid(_linger_timer):
		return
	_linger_timer.wait_time = seconds
	_linger_timer.start()
	await _linger_timer.timeout
