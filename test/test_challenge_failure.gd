extends "res://test/test_base.gd"

## Coverage for the challenge failure-screen feature:
##  - ChallengeManager.get_survive_board_type() (the shared query behind the
##    per-board autodropper gating and the failure-screen board focus)
##  - the standardized first-drop timer gate for Survive challenges
##  - the autodrop failure reason string + single-emit guard

var _fail_reasons: Array[String] = []


func _run_tests() -> void:
	print("--- Challenge failure / survive-gate tests ---")
	test_survive_board_type_returns_objective_board()
	test_survive_board_type_none_when_no_survive()
	test_survive_board_type_none_when_inactive()
	test_survive_timer_waits_for_first_drop()
	test_autodrop_failure_reason_and_guard()


func _make_survive(board_type: int) -> Survive:
	var survive := Survive.new()
	survive.board_type = board_type
	survive.start_delay = 10.0
	survive.survive_duration = 5.0
	return survive


func _make_challenge(objectives: Array[ChallengeObjective]) -> ChallengeData:
	var challenge := ChallengeData.new()
	challenge.objectives = objectives
	return challenge


func test_survive_board_type_returns_objective_board() -> void:
	# Survive is NOT first in the list — guards the loop, not just objectives[0].
	var objs: Array[ChallengeObjective] = [CoinGoal.new(), _make_survive(Enums.BoardType.ORANGE)]
	ChallengeManager.set_challenge(_make_challenge(objs))
	assert_equal(ChallengeManager.get_survive_board_type(), Enums.BoardType.ORANGE,
		"get_survive_board_type returns the Survive objective's board")


func test_survive_board_type_none_when_no_survive() -> void:
	var objs: Array[ChallengeObjective] = [CoinGoal.new()]
	ChallengeManager.set_challenge(_make_challenge(objs))
	assert_equal(ChallengeManager.get_survive_board_type(), -1,
		"get_survive_board_type returns -1 when the challenge has no Survive objective")


func test_survive_board_type_none_when_inactive() -> void:
	# Directly clear the active flag (no scene deps) rather than clear_challenge().
	ChallengeManager.is_active_challenge = false
	assert_equal(ChallengeManager.get_survive_board_type(), -1,
		"get_survive_board_type returns -1 when no challenge is active")


func test_survive_timer_waits_for_first_drop() -> void:
	var objs: Array[ChallengeObjective] = [_make_survive(Enums.BoardType.GOLD)]
	var tracker := ChallengeTracker.new()
	tracker.setup(_make_challenge(objs), null)

	var before: float = tracker._survive_phase_remaining
	tracker._process(1.0)
	assert_equal(tracker._survive_phase_remaining, before,
		"Survive countdown does not start before the first coin drop")

	tracker._on_coin_dropped()
	tracker._process(1.0)
	assert_near(tracker._survive_phase_remaining, before - 1.0, 0.001,
		"Survive countdown advances after the first coin drop")
	tracker.free()


func test_autodrop_failure_reason_and_guard() -> void:
	_fail_reasons.clear()
	var objs: Array[ChallengeObjective] = [_make_survive(Enums.BoardType.ORANGE)]
	var tracker := ChallengeTracker.new()
	tracker.setup(_make_challenge(objs), null)
	tracker.failed.connect(_record_fail)

	tracker._on_autodrop_failed(Enums.BoardType.ORANGE)
	tracker._on_autodrop_failed(Enums.BoardType.ORANGE)  # second call must not re-emit

	assert_equal(_fail_reasons.size(), 1,
		"Autodrop failure emits exactly once (guarded by _has_failed)")
	if _fail_reasons.size() > 0:
		assert_equal(_fail_reasons[0], "Auto dropper could not drop: insufficient funds.",
			"Autodrop failure emits the expected reason string")
	tracker.free()


func _record_fail(reason: String) -> void:
	_fail_reasons.append(reason)
