extends "res://test/test_base.gd"

## Prestige autodropper reward tests — run with:
##   godot --headless --scene res://test/test_prestige_autodropper.tscn
##
## Verifies that gold prestige grants 1 normal autodropper auto-assigned
## to the gold board, that the reward is idempotent, and that all purchased
## autodroppers auto-assign to the default board.


func _run_tests() -> void:
	print("\n=== Prestige Autodropper Reward Tests ===\n")

	test_no_autodropper_without_prestige()
	test_gold_prestige_grants_autodropper()
	test_prestige_reward_does_not_overwrite_existing_pool()
	test_prestige_reward_does_not_overwrite_existing_assignment()
	test_all_normal_autodroppers_auto_assign_to_gold()
	test_all_advanced_autodroppers_auto_assign_to_gold()
	test_prestige_reward_text_includes_autodropper()


func _reset() -> void:
	PrestigeManager.deserialize({})


func _make_board_manager() -> BoardManager:
	var bm := BoardManager.new()
	add_child(bm)
	# setup() would normally create this; tests skip setup() to avoid pulling
	# in a camera + theme. Stub the timer so _on_autodropper_adjust's start/stop
	# logic doesn't NPE.
	bm._autodrop_timer = Timer.new()
	bm.add_child(bm._autodrop_timer)
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
	# Completing gold prestige claims the orange tier (the new tier the player
	# unlocked by prestiging out of gold).
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)

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
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)

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
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)

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


func test_all_normal_autodroppers_auto_assign_to_gold() -> void:
	print("test_all_normal_autodroppers_auto_assign_to_gold")
	_reset()
	var bm := _make_board_manager()
	bm._normal_autodroppers_unlocked = true
	bm._normal_pool = 2
	bm._assignments[StringName("GOLD_NORMAL")] = 2

	# Simulate purchasing a 3rd autodropper
	bm._on_upgrade_purchased(Enums.UpgradeType.AUTODROPPER, Enums.BoardType.GOLD, 3)

	assert_equal(bm._normal_pool, 3,
		"pool should be 3 after third purchase")
	assert_equal(bm._assignments.get(StringName("GOLD_NORMAL"), 0), 3,
		"all 3 should be assigned to GOLD_NORMAL")
	bm.queue_free()


func test_all_advanced_autodroppers_auto_assign_to_gold() -> void:
	print("test_all_advanced_autodroppers_auto_assign_to_gold")
	_reset()
	var bm := _make_board_manager()
	bm._advanced_autodroppers_unlocked = true
	bm._advanced_pool = 1
	bm._assignments[StringName("GOLD_ADVANCED")] = 1

	# Simulate purchasing a 2nd advanced autodropper
	bm._on_upgrade_purchased(Enums.UpgradeType.ADVANCED_AUTODROPPER, Enums.BoardType.ORANGE, 2)

	assert_equal(bm._advanced_pool, 2,
		"advanced pool should be 2 after second purchase")
	assert_equal(bm._assignments.get(StringName("GOLD_ADVANCED"), 0), 2,
		"both should be assigned to GOLD_ADVANCED")
	bm.queue_free()


func test_prestige_reward_text_includes_autodropper() -> void:
	print("test_prestige_reward_text_includes_autodropper")
	var screen := preload("res://entities/prestige_screen/prestige_screen.gd").new()
	# After gold prestige the screen shows orange as the newly-claimed tier;
	# the "permanent autodropper" + "gold challenges" lines key off that.
	screen._board_type = Enums.BoardType.ORANGE
	var text: String = screen._build_rewards_text()
	assert_true(text.contains("permanent autodropper"),
		"gold prestige rewards should mention permanent autodropper")
	assert_true(text.contains("gold challenges"),
		"gold prestige rewards should mention challenge access")
	screen.free()
