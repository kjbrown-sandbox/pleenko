extends "res://test/test_base.gd"

## ensure_state_for_level() tests — run with:
##   godot --headless --scene res://test/test_ensure_unlocks.tscn
##
## Tests the failsafe that reconciles game state against the level table.
## Uses autoloads (LevelManager, UpgradeManager) which are available in headless mode.


func _run_tests() -> void:
	print("\n=== ensure_state_for_level Tests ===\n")

	test_no_unlocks_at_level_zero()
	test_level_1_unlocks_add_row()
	test_level_2_unlocks_bucket_value()
	test_level_3_unlocks_drop_rate()
	test_level_4_unlocks_queue()
	test_all_gold_upgrades_unlocked_at_level_4()
	test_idempotent_when_already_unlocked()
	test_partial_unlocks_repaired()
	test_advanced_bucket_reconcile_at_level_10()
	test_no_advanced_bucket_reconcile_below_level_10()
	test_drop_coins_not_replayed()


func _reset_state() -> void:
	LevelManager.reset()
	LevelManager.rebuild_levels()
	UpgradeManager.reset()


# --- Test Cases ---

func test_no_unlocks_at_level_zero() -> void:
	print("test_no_unlocks_at_level_zero")
	_reset_state()
	LevelManager.current_level = 0
	LevelManager.ensure_state_for_level()
	assert_false(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"ADD_ROW should NOT be unlocked at level 0")


func test_level_1_unlocks_add_row() -> void:
	print("test_level_1_unlocks_add_row")
	_reset_state()
	LevelManager.current_level = 1
	LevelManager.ensure_state_for_level()
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"ADD_ROW should be unlocked at level 1")


func test_level_2_unlocks_bucket_value() -> void:
	print("test_level_2_unlocks_bucket_value")
	_reset_state()
	LevelManager.current_level = 2
	LevelManager.ensure_state_for_level()
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE),
		"BUCKET_VALUE should be unlocked at level 2")


func test_level_3_unlocks_drop_rate() -> void:
	print("test_level_3_unlocks_drop_rate")
	_reset_state()
	LevelManager.current_level = 3
	LevelManager.ensure_state_for_level()
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.DROP_RATE),
		"DROP_RATE should be unlocked at level 3")


func test_level_4_unlocks_queue() -> void:
	print("test_level_4_unlocks_queue")
	_reset_state()
	LevelManager.current_level = 4
	LevelManager.ensure_state_for_level()
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.QUEUE),
		"QUEUE should be unlocked at level 4")


func test_all_gold_upgrades_unlocked_at_level_4() -> void:
	print("test_all_gold_upgrades_unlocked_at_level_4")
	_reset_state()
	LevelManager.current_level = 4
	LevelManager.ensure_state_for_level()
	# Levels 0-3: ADD_ROW, BUCKET_VALUE, DROP_RATE, QUEUE
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"ADD_ROW unlocked")
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE),
		"BUCKET_VALUE unlocked")
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.DROP_RATE),
		"DROP_RATE unlocked")
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.QUEUE),
		"QUEUE unlocked")


func test_idempotent_when_already_unlocked() -> void:
	print("test_idempotent_when_already_unlocked")
	_reset_state()
	LevelManager.current_level = 2
	# Manually unlock first
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE)
	# Calling again should be a no-op (no errors, no duplicate signals)
	LevelManager.ensure_state_for_level()
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"ADD_ROW still unlocked")
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE),
		"BUCKET_VALUE still unlocked")


func test_advanced_bucket_reconcile_at_level_10() -> void:
	print("test_advanced_bucket_reconcile_at_level_10")
	_reset_state()
	LevelManager.current_level = 10  # past gold slot 9 (UNLOCK_ADVANCED_BUCKET)

	var caught: Array[RewardData] = []
	var probe := func(reward: RewardData):
		if reward.type == RewardData.RewardType.UNLOCK_ADVANCED_BUCKET:
			caught.append(reward)
	LevelManager.reconcile_reward.connect(probe)

	LevelManager.ensure_state_for_level()

	LevelManager.reconcile_reward.disconnect(probe)

	assert_equal(caught.size(), 1, "exactly one UNLOCK_ADVANCED_BUCKET reconcile fired")
	if caught.size() == 1:
		assert_equal(caught[0].target_board, Enums.BoardType.GOLD,
			"reconcile target_board is GOLD")


func test_no_advanced_bucket_reconcile_below_level_10() -> void:
	print("test_no_advanced_bucket_reconcile_below_level_10")
	_reset_state()
	LevelManager.current_level = 9  # one short of the unlock

	var caught: Array[RewardData] = []
	var probe := func(reward: RewardData):
		if reward.type == RewardData.RewardType.UNLOCK_ADVANCED_BUCKET:
			caught.append(reward)
	LevelManager.reconcile_reward.connect(probe)

	LevelManager.ensure_state_for_level()

	LevelManager.reconcile_reward.disconnect(probe)

	assert_equal(caught.size(), 0, "no UNLOCK_ADVANCED_BUCKET reconcile below level 10")


func test_drop_coins_not_replayed() -> void:
	print("test_drop_coins_not_replayed")
	_reset_state()
	LevelManager.current_level = 10  # past several DROP_COINS levels (slots 5, 6, 7, 8)

	var caught: Array[RewardData] = []
	var probe := func(reward: RewardData):
		if reward.type == RewardData.RewardType.DROP_COINS:
			caught.append(reward)
	LevelManager.reconcile_reward.connect(probe)

	LevelManager.ensure_state_for_level()

	LevelManager.reconcile_reward.disconnect(probe)

	assert_equal(caught.size(), 0, "DROP_COINS rewards must NOT be reconciled (would dupe coins)")


func test_partial_unlocks_repaired() -> void:
	print("test_partial_unlocks_repaired")
	_reset_state()
	LevelManager.current_level = 5
	# Only unlock ADD_ROW — simulate the bug where other unlocks were lost
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	assert_false(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE),
		"BUCKET_VALUE should NOT be unlocked yet (simulating bug)")
	assert_false(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.DROP_RATE),
		"DROP_RATE should NOT be unlocked yet (simulating bug)")

	# Failsafe repairs the missing unlocks
	LevelManager.ensure_state_for_level()
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"ADD_ROW still unlocked")
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE),
		"BUCKET_VALUE repaired")
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.DROP_RATE),
		"DROP_RATE repaired")
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.QUEUE),
		"QUEUE repaired")
