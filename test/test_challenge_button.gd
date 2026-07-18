extends "res://test/test_base.gd"

## ChallengeButton._should_pulse() tests — run with:
##   godot --headless --scene res://test/test_challenge_button.tscn
##
## Pure-predicate tests over the pulse-gating logic. Bare ChallengeButton.new()
## instances are never added to the tree, so @onready children stay unresolved
## and _ready()/tween machinery never fire — we set _state / _hovered directly
## and assert the gate. Only UNLOCKED-and-not-hovered should pulse (the
## available-but-incomplete state worth flagging to the player).

const LOCKED := ChallengeProgressManager.ChallengeState.LOCKED
const UNLOCKED := ChallengeProgressManager.ChallengeState.UNLOCKED
const COMPLETED := ChallengeProgressManager.ChallengeState.COMPLETED


func _run_tests() -> void:
	print("\n=== ChallengeButton._should_pulse Tests ===\n")
	test_unlocked_not_hovered_pulses()
	test_unlocked_hovered_does_not_pulse()
	test_locked_does_not_pulse()
	test_completed_does_not_pulse()


func _make_button(state: int, hovered: bool) -> ChallengeButton:
	var btn := ChallengeButton.new()
	btn._state = state
	btn._hovered = hovered
	return btn


func test_unlocked_not_hovered_pulses() -> void:
	print("test_unlocked_not_hovered_pulses")
	var btn := _make_button(UNLOCKED, false)
	assert_true(btn._should_pulse(), "available + not hovered pulses")
	btn.free()


func test_unlocked_hovered_does_not_pulse() -> void:
	print("test_unlocked_hovered_does_not_pulse")
	# Hover owns the scale (the pop), so the pulse must yield while hovered.
	var btn := _make_button(UNLOCKED, true)
	assert_false(btn._should_pulse(), "available but hovered does not pulse")
	btn.free()


func test_locked_does_not_pulse() -> void:
	print("test_locked_does_not_pulse")
	var btn := _make_button(LOCKED, false)
	assert_false(btn._should_pulse(), "locked does not pulse")
	btn.free()


func test_completed_does_not_pulse() -> void:
	print("test_completed_does_not_pulse")
	var btn := _make_button(COMPLETED, false)
	assert_false(btn._should_pulse(), "completed does not pulse")
	btn.free()
