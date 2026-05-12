extends "res://test/test_base.gd"

## Prestige autodropper reward tests — run with:
##   godot --headless --scene res://test/test_prestige_autodropper.tscn
##
## Verifies that gold prestige grants 1 normal autodropper auto-assigned
## to the gold board, and that the reward is idempotent.


func _run_tests() -> void:
	print("\n=== Prestige Autodropper Reward Tests ===\n")

	test_no_autodropper_without_prestige()
	test_gold_prestige_grants_autodropper()
	test_prestige_reward_does_not_overwrite_existing_pool()
	test_prestige_reward_does_not_overwrite_existing_assignment()


func _reset() -> void:
	PrestigeManager.deserialize({})


func _make_board_manager() -> BoardManager:
	var bm := BoardManager.new()
	var gold_board := PlinkoBoard.new()
	gold_board.board_type = Enums.BoardType.GOLD
	gold_board.coin_queue = CoinQueue.new()
	bm._boards.append(gold_board)
	return bm


# --- Test Cases ---

func test_no_autodropper_without_prestige() -> void:
	print("test_no_autodropper_without_prestige")
	_reset()
	var bm := _make_board_manager()

	bm._apply_prestige_rewards()

	assert_false(bm._normal_autodroppers_unlocked,
		"autodroppers should NOT be unlocked without gold prestige")
	assert_equal(bm._normal_pool, 0,
		"pool should remain 0 without gold prestige")
	assert_equal(bm._assignments.get(StringName("GOLD_NORMAL"), 0), 0,
		"no assignment without gold prestige")
	bm.queue_free()


func test_gold_prestige_grants_autodropper() -> void:
	print("test_gold_prestige_grants_autodropper")
	_reset()
	PrestigeManager.trigger_prestige(Enums.BoardType.GOLD)

	var bm := _make_board_manager()

	bm._apply_prestige_rewards()

	assert_true(bm._normal_autodroppers_unlocked,
		"autodroppers should be unlocked after gold prestige")
	assert_equal(bm._normal_pool, 1,
		"pool should be 1 after gold prestige")
	assert_equal(bm._assignments.get(StringName("GOLD_NORMAL"), 0), 1,
		"1 autodropper should be assigned to GOLD_NORMAL")
	bm.queue_free()


func test_prestige_reward_does_not_overwrite_existing_pool() -> void:
	print("test_prestige_reward_does_not_overwrite_existing_pool")
	_reset()
	PrestigeManager.trigger_prestige(Enums.BoardType.GOLD)

	var bm := _make_board_manager()
	bm._normal_autodroppers_unlocked = true
	bm._normal_pool = 5
	bm._assignments[StringName("GOLD_NORMAL")] = 3

	bm._apply_prestige_rewards()

	assert_equal(bm._normal_pool, 5,
		"pool should stay at 5 (not reduced to 1)")
	assert_equal(bm._assignments.get(StringName("GOLD_NORMAL"), 0), 3,
		"assignment should stay at 3 (not reduced to 1)")
	bm.queue_free()


func test_prestige_reward_does_not_overwrite_existing_assignment() -> void:
	print("test_prestige_reward_does_not_overwrite_existing_assignment")
	_reset()
	PrestigeManager.trigger_prestige(Enums.BoardType.GOLD)

	var bm := _make_board_manager()
	bm._normal_autodroppers_unlocked = true
	bm._normal_pool = 2
	# Autodroppers assigned elsewhere, none on gold
	bm._assignments[StringName("ORANGE_NORMAL")] = 2

	bm._apply_prestige_rewards()

	assert_equal(bm._assignments.get(StringName("GOLD_NORMAL"), 0), 1,
		"gold should get 1 assignment when it had 0")
	assert_equal(bm._assignments.get(StringName("ORANGE_NORMAL"), 0), 2,
		"orange assignment should be untouched")
	bm.queue_free()
