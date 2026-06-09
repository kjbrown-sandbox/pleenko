extends "res://test/test_base.gd"

## Survive-challenge regression tests.
##   1. The WAITING buildup must emit ChallengeManager.tick so the challenge
##      audio sequencer (AudioManager._on_challenge_tick) and the countdown
##      clock run during the buildup, not just while SURVIVING.
##   2. activate_survive_autodroppers must only call BoardManager methods that
##      exist — it previously called a deleted _on_autodropper_unlocked() and
##      crashed at the WAITING->SURVIVING transition.
## Run with: godot --headless --scene res://test/test_survive_challenge.tscn


func _run_tests() -> void:
	print("\n=== Survive Challenge Tests ===\n")
	test_survive_emits_tick_during_waiting()
	test_board_manager_exposes_survive_autodropper_api()


# ── Helpers ─────────────────────────────────────────────────────────

func _survive_challenge(start_delay: float) -> ChallengeData:
	var survive := Survive.new()
	survive.board_type = Enums.BoardType.GOLD
	survive.start_delay = start_delay
	survive.survive_duration = 30.0
	var challenge := ChallengeData.new()
	challenge.time_limit_seconds = 135.0
	var objs: Array[ChallengeObjective] = [survive]
	challenge.objectives = objs
	return challenge


# ── Tests ───────────────────────────────────────────────────────────

func test_survive_emits_tick_during_waiting() -> void:
	print("test_survive_emits_tick_during_waiting")
	# 5s WAITING buildup, kept short so we never cross into SURVIVING here.
	var tracker := ChallengeTracker.new()
	tracker.setup(_survive_challenge(5.0), null)

	var ticks: Array[int] = []
	var recorder := func(seconds: int) -> void: ticks.append(seconds)
	ChallengeManager.tick.connect(recorder)

	# Advance one second at a time through the WAITING phase.
	tracker._process_survive(1.0)  # remaining 4.0 -> ceil 4
	tracker._process_survive(1.0)  # remaining 3.0 -> ceil 3

	ChallengeManager.tick.disconnect(recorder)

	assert_equal(ticks.size(), 2, "tick emitted each second during WAITING")
	assert_equal(ticks[0], 4, "first WAITING tick reports ceil(remaining)")
	assert_equal(ticks[1], 3, "second WAITING tick decrements")
	tracker.free()


func test_board_manager_exposes_survive_autodropper_api() -> void:
	print("test_board_manager_exposes_survive_autodropper_api")
	# Guards the crash class: activate_survive_autodroppers drives the board
	# through these methods. If any is renamed/removed (as _on_autodropper_unlocked
	# once was), update the caller too — otherwise the survive transition crashes.
	var bm := BoardManager.new()
	assert_true(bm.has_method("reveal_autodropper_controls"), "BoardManager.reveal_autodropper_controls exists")
	assert_true(bm.has_method("get_free_autodroppers"), "BoardManager.get_free_autodroppers exists")
	assert_true(bm.has_method("_on_autodropper_adjust"), "BoardManager._on_autodropper_adjust exists")
	assert_false(bm.has_method("_on_autodropper_unlocked"), "deleted method must stay gone")
	bm.free()
