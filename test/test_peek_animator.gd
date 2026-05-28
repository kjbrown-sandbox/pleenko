extends "res://test/test_base.gd"

## PeekAnimator tests — run with:
##   godot --headless --scene res://test/test_peek_animator.tscn
##
## Tests PeekAnimator's queue/drain/suppression logic with injected Callables
## (no real camera tweens, no async waits). Uses a bare BoardManager so the
## board_unlocked signal can be emitted directly. SaveManager.save_game is a
## no-op here because SaveManager._board_manager is null in tests.

const PeekAnimatorScript := preload("res://entities/main/peek_animator.gd")

var _calls: Array = []  # Records each Callable invocation: ["fn", arg, ...]
var _live_peeks: Array[PeekAnimator] = []  # Tests register here so _reset_world can free zombies


func _run_tests() -> void:
	print("\n=== PeekAnimator Tests ===\n")

	test_board_unlocked_enqueues_and_drains()
	test_gold_unlock_is_ignored()
	test_loading_query_suppresses_enqueue()
	test_already_peeked_board_suppresses_enqueue()
	test_active_challenge_suppresses_enqueue()
	test_two_board_unlocks_drain_sequentially()
	test_is_peeking_true_during_drain_false_after()
	test_is_input_locked_reflects_prestige_phase()
	test_queue_peeks_for_existing_unlocks_enqueues_unpeeked()
	test_queue_peeks_for_existing_unlocks_skips_already_peeked()
	test_queue_peeks_for_existing_unlocks_skips_gold()
	test_queue_peeks_for_existing_unlocks_enqueues_challenges_when_unlocked()
	test_queue_peeks_for_existing_unlocks_skips_challenges_if_already_visited()
	test_input_lock_applied_around_peek()
	test_mark_board_peeked_after_drain()
	test_prestige_phase_change_clears_queue()
	test_board_peek_no_op_when_already_on_target()
	test_drain_deferred_holds_peek_then_releases()
	test_drain_deferred_release_is_noop_when_queue_empty()
	test_peek_linger_hook_replaces_default_wait()
	test_tier_crossing_queues_peek_for_unlocked_board()
	test_tier_crossing_skips_peek_for_already_peeked_board()
	test_tier_crossing_skips_peek_when_board_not_unlocked()
	test_queue_peeks_skips_board_when_current_level_below_tier()


# --- Fixtures ---

func _reset_world() -> void:
	# Free any prior-test PeekAnimators so their signal connections don't pollute _calls
	for prior in _live_peeks:
		if is_instance_valid(prior):
			prior.free()
	_live_peeks.clear()
	_calls = []
	OnboardingProgress.reset()
	ChallengeProgressManager.challenges_ever_visited = false
	ChallengeManager.is_active_challenge = false
	ModeManager.current_mode = ModeManager.Mode.MAIN
	# Default `current_level` to the orange tier start so existing peek tests
	# (which expect orange to be queued by `queue_peeks_for_existing_unlocks`)
	# clear the new "player must have reached this board's tier" gate.
	LevelManager.current_level = LevelManager.LEVELS_PER_TIER
	# PrestigeManager phase should already be NONE; reset_time_scale is the public way.
	PrestigeManager.reset_time_scale()


func _make_bm(types: Array) -> BoardManager:
	var bm := BoardManager.new()
	for t in types:
		var board := PlinkoBoard.new()
		board.board_type = t
		bm._boards.append(board)
	return bm


func _make_peek_animator() -> PeekAnimator:
	var p: PeekAnimator = PeekAnimatorScript.new()
	var timer := Timer.new()
	timer.name = "LingerTimer"
	p.add_child(timer)
	add_child(p)
	# Inject test Callables. delay_fn is instant so awaits resolve immediately.
	p.switch_board_fn = func(idx: int) -> void: _calls.append(["switch_board", idx])
	p.switch_to_challenges_fn = func() -> void: _calls.append(["switch_to_challenges"])
	p.switch_to_main_fn = func() -> void: _calls.append(["switch_to_main"])
	p.apply_input_lock_fn = func(locked: bool) -> void: _calls.append(["lock", locked])
	p.loading_query = func() -> bool: return false
	p.wait_fn = func(_seconds: float) -> void: pass
	_live_peeks.append(p)
	return p


func _setup_peek(p: PeekAnimator, bm: BoardManager) -> void:
	p.setup(bm)


func _count_calls(fn_name: String) -> int:
	var c := 0
	for entry in _calls:
		if entry[0] == fn_name:
			c += 1
	return c


## Wait for the drain loop to settle. Each peek's injected delay_fn awaits one
## idle frame, so we need at least one frame per queued peek, plus one for
## final cleanup. Caps at 10 frames to avoid infinite loops in broken tests.
func _wait_for_drain(p: PeekAnimator) -> void:
	for i in 10:
		await get_tree().process_frame
		if not p.is_peeking() and p._queue.is_empty():
			return


# --- Test Cases ---

func test_board_unlocked_enqueues_and_drains() -> void:
	print("test_board_unlocked_enqueues_and_drains")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	bm._active_index = 0
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	bm.board_unlocked.emit(Enums.BoardType.ORANGE)
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	# One switch out (to orange) + one switch back (to gold) = 2 calls
	assert_equal(_count_calls("switch_board"), 2, "switch_board called twice (out + back)")
	assert_true(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "orange marked peeked")
	bm.queue_free()
	p.queue_free()


func test_gold_unlock_is_ignored() -> void:
	print("test_gold_unlock_is_ignored")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD])
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	bm.board_unlocked.emit(Enums.BoardType.GOLD)
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	assert_equal(_count_calls("switch_board"), 0, "gold should not trigger a peek")
	bm.queue_free()
	p.queue_free()


func test_loading_query_suppresses_enqueue() -> void:
	print("test_loading_query_suppresses_enqueue")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	var p := _make_peek_animator()
	p.loading_query = func() -> bool: return true
	_setup_peek(p, bm)

	bm.board_unlocked.emit(Enums.BoardType.ORANGE)
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	assert_equal(_count_calls("switch_board"), 0, "loading suppresses enqueue")
	assert_false(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "orange NOT marked peeked")
	bm.queue_free()
	p.queue_free()


func test_already_peeked_board_suppresses_enqueue() -> void:
	print("test_already_peeked_board_suppresses_enqueue")
	_reset_world()
	OnboardingProgress.mark_board_peeked(Enums.BoardType.ORANGE)
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	bm.board_unlocked.emit(Enums.BoardType.ORANGE)
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	assert_equal(_count_calls("switch_board"), 0, "already-peeked board not re-peeked")
	bm.queue_free()
	p.queue_free()


func test_active_challenge_suppresses_enqueue() -> void:
	print("test_active_challenge_suppresses_enqueue")
	_reset_world()
	ChallengeManager.is_active_challenge = true
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	bm.board_unlocked.emit(Enums.BoardType.ORANGE)
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	assert_equal(_count_calls("switch_board"), 0, "active challenge suppresses enqueue")
	ChallengeManager.is_active_challenge = false  # cleanup
	bm.queue_free()
	p.queue_free()


func test_two_board_unlocks_drain_sequentially() -> void:
	print("test_two_board_unlocks_drain_sequentially")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE, Enums.BoardType.RED])
	bm._active_index = 0
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	bm.board_unlocked.emit(Enums.BoardType.ORANGE)
	bm.board_unlocked.emit(Enums.BoardType.RED)
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	# Two peeks: orange out+back, red out+back = 4 switch_board calls
	assert_equal(_count_calls("switch_board"), 4, "two peeks drain sequentially (4 switches)")
	assert_true(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "orange marked peeked")
	assert_true(OnboardingProgress.has_peeked_board(Enums.BoardType.RED), "red marked peeked")
	bm.queue_free()
	p.queue_free()


func test_is_peeking_true_during_drain_false_after() -> void:
	print("test_is_peeking_true_during_drain_false_after")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	var p := _make_peek_animator()
	# Inject a wait that records is_peeking state mid-flight
	var saw_peeking := [false]
	p.wait_fn = func(_seconds: float) -> void:
		saw_peeking[0] = p.is_peeking()
	_setup_peek(p, bm)

	bm.board_unlocked.emit(Enums.BoardType.ORANGE)
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	assert_true(saw_peeking[0], "is_peeking() true during delay")
	assert_false(p.is_peeking(), "is_peeking() false after drain")
	bm.queue_free()
	p.queue_free()


func test_is_input_locked_reflects_prestige_phase() -> void:
	print("test_is_input_locked_reflects_prestige_phase")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD])
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	assert_false(p.is_input_locked(), "unlocked when idle + prestige NONE")
	PrestigeManager.current_phase = PrestigeManager.PrestigePhase.SLOW_MO
	assert_true(p.is_input_locked(), "locked when prestige non-NONE")
	PrestigeManager.reset_time_scale()
	assert_false(p.is_input_locked(), "unlocked after prestige NONE")
	bm.queue_free()
	p.queue_free()


func test_queue_peeks_for_existing_unlocks_enqueues_unpeeked() -> void:
	print("test_queue_peeks_for_existing_unlocks_enqueues_unpeeked")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	bm._active_index = 0
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	p.queue_peeks_for_existing_unlocks()
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	assert_equal(_count_calls("switch_board"), 2, "unpeeked orange peeked once on initial scan")
	assert_true(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "orange now peeked")
	bm.queue_free()
	p.queue_free()


func test_queue_peeks_for_existing_unlocks_skips_already_peeked() -> void:
	print("test_queue_peeks_for_existing_unlocks_skips_already_peeked")
	_reset_world()
	OnboardingProgress.mark_board_peeked(Enums.BoardType.ORANGE)
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	p.queue_peeks_for_existing_unlocks()
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	assert_equal(_count_calls("switch_board"), 0, "already-peeked orange skipped on initial scan")
	bm.queue_free()
	p.queue_free()


func test_queue_peeks_for_existing_unlocks_skips_gold() -> void:
	print("test_queue_peeks_for_existing_unlocks_skips_gold")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD])
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	p.queue_peeks_for_existing_unlocks()
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	assert_equal(_count_calls("switch_board"), 0, "gold alone produces no peek")
	bm.queue_free()
	p.queue_free()


func test_queue_peeks_for_existing_unlocks_enqueues_challenges_when_unlocked() -> void:
	print("test_queue_peeks_for_existing_unlocks_enqueues_challenges_when_unlocked")
	_reset_world()
	# Simulate first prestige having happened so challenges are unlocked.
	PrestigeManager._prestige_counts[Enums.BoardType.GOLD] = 1
	var bm := _make_bm([Enums.BoardType.GOLD])
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	p.queue_peeks_for_existing_unlocks()
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	assert_equal(_count_calls("switch_to_challenges"), 1, "switch to challenges once")
	assert_equal(_count_calls("switch_to_main"), 1, "switch back to main once")
	assert_true(OnboardingProgress.has_peeked_challenges(), "challenges marked peeked")
	# cleanup
	PrestigeManager._prestige_counts.clear()
	bm.queue_free()
	p.queue_free()


func test_queue_peeks_for_existing_unlocks_skips_challenges_if_already_visited() -> void:
	print("test_queue_peeks_for_existing_unlocks_skips_challenges_if_already_visited")
	_reset_world()
	PrestigeManager._prestige_counts[Enums.BoardType.GOLD] = 1
	ChallengeProgressManager.challenges_ever_visited = true
	var bm := _make_bm([Enums.BoardType.GOLD])
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	p.queue_peeks_for_existing_unlocks()
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	assert_equal(_count_calls("switch_to_challenges"), 0, "no peek when challenges already manually visited")
	PrestigeManager._prestige_counts.clear()
	ChallengeProgressManager.challenges_ever_visited = false
	bm.queue_free()
	p.queue_free()


func test_input_lock_applied_around_peek() -> void:
	print("test_input_lock_applied_around_peek")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	bm.board_unlocked.emit(Enums.BoardType.ORANGE)
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	# First lock call should be true (peek started); last should be false (peek ended).
	var lock_calls := []
	for entry in _calls:
		if entry[0] == "lock":
			lock_calls.append(entry[1])
	assert_true(lock_calls.size() >= 2, "at least two lock calls (on and off)")
	assert_true(lock_calls[0], "first lock call locks input")
	assert_false(lock_calls[-1], "last lock call unlocks input")
	bm.queue_free()
	p.queue_free()


func test_mark_board_peeked_after_drain() -> void:
	print("test_mark_board_peeked_after_drain")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	assert_false(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "before: orange not peeked")
	bm.board_unlocked.emit(Enums.BoardType.ORANGE)
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	assert_true(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "after: orange marked peeked")
	bm.queue_free()
	p.queue_free()


func test_prestige_phase_change_clears_queue() -> void:
	print("test_prestige_phase_change_clears_queue")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE, Enums.BoardType.RED])
	var p := _make_peek_animator()
	# Inject a wait that triggers a prestige phase change mid-peek
	p.wait_fn = func(_seconds: float) -> void:
		PrestigeManager.current_phase = PrestigeManager.PrestigePhase.SLOW_MO
		PrestigeManager.prestige_phase_changed.emit(PrestigeManager.PrestigePhase.SLOW_MO)
	_setup_peek(p, bm)

	bm.board_unlocked.emit(Enums.BoardType.ORANGE)
	bm.board_unlocked.emit(Enums.BoardType.RED)
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	# Orange was running when prestige started — its switch-back should NOT have happened.
	# Red was queued — should be cleared.
	assert_false(p.is_peeking(), "is_peeking false after prestige interrupt")
	assert_false(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "orange NOT marked peeked (interrupted)")
	assert_false(OnboardingProgress.has_peeked_board(Enums.BoardType.RED), "red NOT marked peeked (cleared from queue)")
	PrestigeManager.reset_time_scale()
	bm.queue_free()
	p.queue_free()


func test_board_peek_no_op_when_already_on_target() -> void:
	print("test_board_peek_no_op_when_already_on_target")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	bm._active_index = 1  # Player is on ORANGE already
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	bm.board_unlocked.emit(Enums.BoardType.ORANGE)
	# delay_fn is sync (returns null), so the entire peek flow ran on the signal-emit call.

	# Already on target — no switch needed
	assert_equal(_count_calls("switch_board"), 0, "no switch when already on target")
	assert_true(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "orange still marked peeked")
	bm.queue_free()
	p.queue_free()


# --- set_drain_deferred (CapRaiseRevealAnimator holds the new-board peek) ---

func test_drain_deferred_holds_peek_then_releases() -> void:
	print("test_drain_deferred_holds_peek_then_releases")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	bm._active_index = 0
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	p.set_drain_deferred(true)
	bm.board_unlocked.emit(Enums.BoardType.ORANGE)
	assert_equal(_count_calls("switch_board"), 0, "deferred: the peek does not drain yet")
	assert_equal(p._queue.size(), 1, "deferred: the peek stays queued")

	p.set_drain_deferred(false)
	assert_equal(_count_calls("switch_board"), 2, "released: the queued peek drains (out + back)")
	bm.queue_free()
	p.queue_free()


func test_drain_deferred_release_is_noop_when_queue_empty() -> void:
	print("test_drain_deferred_release_is_noop_when_queue_empty")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	bm._active_index = 0
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	p.set_drain_deferred(true)
	p.set_drain_deferred(false)  # nothing queued — must be a clean no-op
	assert_equal(_count_calls("switch_board"), 0, "releasing an empty queue does nothing")
	bm.queue_free()
	p.queue_free()


# --- peek_linger_hook (milestone-bar spawn-in during peek) ---

func test_peek_linger_hook_replaces_default_wait() -> void:
	print("test_peek_linger_hook_replaces_default_wait")
	_reset_world()
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	bm._active_index = 0
	var p := _make_peek_animator()
	var hook_called := [false]
	p.peek_linger_hook = func() -> void:
		hook_called[0] = true
		_calls.append(["hook"])
	_setup_peek(p, bm)

	bm.board_unlocked.emit(Enums.BoardType.ORANGE)

	assert_true(hook_called[0], "peek_linger_hook fires in place of the linger wait")
	# Hook should be invoked exactly once per peek (between camera-out and camera-back)
	assert_equal(_count_calls("hook"), 1, "hook called exactly once per peek")
	bm.queue_free()
	p.queue_free()


# --- _on_level_changed (post-prestige re-cross trigger) ---

func test_tier_crossing_queues_peek_for_unlocked_board() -> void:
	print("test_tier_crossing_queues_peek_for_unlocked_board")
	_reset_world()
	# Start with current_level in gold tier so the listener has a baseline.
	LevelManager.current_level = 0
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	bm._active_index = 0
	var p := _make_peek_animator()
	_setup_peek(p, bm)
	# Now simulate the gold-final crossing — current_level advances into orange tier.
	LevelManager.current_level = LevelManager.LEVELS_PER_TIER
	LevelManager.level_changed.emit(LevelManager.current_level)

	assert_equal(_count_calls("switch_board"), 2, "tier crossing queues + drains orange peek")
	assert_true(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "orange marked peeked")
	bm.queue_free()
	p.queue_free()


func test_tier_crossing_skips_peek_for_already_peeked_board() -> void:
	print("test_tier_crossing_skips_peek_for_already_peeked_board")
	_reset_world()
	OnboardingProgress.mark_board_peeked(Enums.BoardType.ORANGE)
	LevelManager.current_level = 0
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	bm._active_index = 0
	var p := _make_peek_animator()
	_setup_peek(p, bm)
	LevelManager.current_level = LevelManager.LEVELS_PER_TIER
	LevelManager.level_changed.emit(LevelManager.current_level)

	assert_equal(_count_calls("switch_board"), 0, "already-peeked board skipped on tier crossing")
	bm.queue_free()
	p.queue_free()


func test_tier_crossing_skips_peek_when_board_not_unlocked() -> void:
	print("test_tier_crossing_skips_peek_when_board_not_unlocked")
	_reset_world()
	LevelManager.current_level = 0
	# Gold only — orange is NOT in _boards yet (pre-prestige scenario).
	var bm := _make_bm([Enums.BoardType.GOLD])
	bm._active_index = 0
	var p := _make_peek_animator()
	_setup_peek(p, bm)
	LevelManager.current_level = LevelManager.LEVELS_PER_TIER
	LevelManager.level_changed.emit(LevelManager.current_level)

	assert_equal(_count_calls("switch_board"), 0, "tier crossing waits for board_unlocked when board not in _boards yet")
	bm.queue_free()
	p.queue_free()


func test_queue_peeks_skips_board_when_current_level_below_tier() -> void:
	print("test_queue_peeks_skips_board_when_current_level_below_tier")
	_reset_world()
	# Player saved on gold tier (current_level = 0), orange already in _boards
	# from a prior prestige cycle. queue_peeks should NOT pull the camera to
	# orange until the player crosses into orange tier.
	LevelManager.current_level = 0
	var bm := _make_bm([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	bm._active_index = 0
	var p := _make_peek_animator()
	_setup_peek(p, bm)

	p.queue_peeks_for_existing_unlocks()

	assert_equal(_count_calls("switch_board"), 0, "current_level below orange tier-start: no session-start peek")
	bm.queue_free()
	p.queue_free()
