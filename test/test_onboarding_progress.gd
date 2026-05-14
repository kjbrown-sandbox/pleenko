extends "res://test/test_base.gd"

## OnboardingProgress autoload tests — run with:
##   godot --headless --scene res://test/test_onboarding_progress.tscn


func _run_tests() -> void:
	print("\n=== OnboardingProgress Tests ===\n")

	test_initial_state_is_empty()
	test_mark_board_peeked_round_trip()
	test_mark_challenges_peeked_round_trip()
	test_multiple_boards_peeked()
	test_reset_clears_all()
	test_deserialize_missing_keys_defaults()


func _reset() -> void:
	OnboardingProgress.reset()


# --- Test Cases ---

func test_initial_state_is_empty() -> void:
	print("test_initial_state_is_empty")
	_reset()
	assert_false(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "orange not peeked initially")
	assert_false(OnboardingProgress.has_peeked_challenges(), "challenges not peeked initially")


func test_mark_board_peeked_round_trip() -> void:
	print("test_mark_board_peeked_round_trip")
	_reset()
	OnboardingProgress.mark_board_peeked(Enums.BoardType.ORANGE)
	var data := OnboardingProgress.serialize()
	_reset()
	OnboardingProgress.deserialize(data)
	assert_true(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "orange should round-trip as peeked")
	assert_false(OnboardingProgress.has_peeked_board(Enums.BoardType.RED), "red should still be unpeeked")


func test_mark_challenges_peeked_round_trip() -> void:
	print("test_mark_challenges_peeked_round_trip")
	_reset()
	OnboardingProgress.mark_challenges_peeked()
	var data := OnboardingProgress.serialize()
	_reset()
	OnboardingProgress.deserialize(data)
	assert_true(OnboardingProgress.has_peeked_challenges(), "challenges should round-trip as peeked")


func test_multiple_boards_peeked() -> void:
	print("test_multiple_boards_peeked")
	_reset()
	OnboardingProgress.mark_board_peeked(Enums.BoardType.ORANGE)
	OnboardingProgress.mark_board_peeked(Enums.BoardType.RED)
	var data := OnboardingProgress.serialize()
	_reset()
	OnboardingProgress.deserialize(data)
	assert_true(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "orange peeked")
	assert_true(OnboardingProgress.has_peeked_board(Enums.BoardType.RED), "red peeked")
	assert_false(OnboardingProgress.has_peeked_board(Enums.BoardType.VIOLET), "violet not peeked")


func test_reset_clears_all() -> void:
	print("test_reset_clears_all")
	OnboardingProgress.mark_board_peeked(Enums.BoardType.ORANGE)
	OnboardingProgress.mark_challenges_peeked()
	OnboardingProgress.reset()
	assert_false(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "orange cleared by reset")
	assert_false(OnboardingProgress.has_peeked_challenges(), "challenges cleared by reset")


func test_deserialize_missing_keys_defaults() -> void:
	print("test_deserialize_missing_keys_defaults")
	OnboardingProgress.mark_board_peeked(Enums.BoardType.ORANGE)
	OnboardingProgress.mark_challenges_peeked()
	OnboardingProgress.deserialize({})  # Empty dict — both fields default
	assert_false(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE), "orange defaults to false from empty dict")
	assert_false(OnboardingProgress.has_peeked_challenges(), "challenges defaults to false from empty dict")
