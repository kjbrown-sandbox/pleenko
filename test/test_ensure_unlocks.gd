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
	test_level_4_unlocks_autodropper()
	test_level_5_unlocks_queue()
	test_all_gold_upgrades_unlocked_at_level_5()
	test_idempotent_when_already_unlocked()
	test_partial_unlocks_repaired()
	test_advanced_buckets_never_reconciled()
	test_drop_coins_not_replayed()
	test_deflector_unlocks_on_orange_only()
	test_advanced_autodropper_moved_to_red()


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


func test_level_4_unlocks_autodropper() -> void:
	print("test_level_4_unlocks_autodropper")
	_reset_state()
	LevelManager.current_level = 4
	LevelManager.ensure_state_for_level()
	# Gold swaps slots 3/4: Autodropper now unlocks at level 4 (was Queue).
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.AUTODROPPER),
		"AUTODROPPER should be unlocked at level 4 on gold")
	assert_false(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.QUEUE),
		"QUEUE should NOT be unlocked yet at level 4 on gold")


func test_level_5_unlocks_queue() -> void:
	print("test_level_5_unlocks_queue")
	_reset_state()
	LevelManager.current_level = 5
	LevelManager.ensure_state_for_level()
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.QUEUE),
		"QUEUE should be unlocked at level 5 on gold (pushed after autodropper)")


func test_all_gold_upgrades_unlocked_at_level_5() -> void:
	print("test_all_gold_upgrades_unlocked_at_level_5")
	_reset_state()
	LevelManager.current_level = 5
	LevelManager.ensure_state_for_level()
	# Gold slots 0-4: ADD_ROW, BUCKET_VALUE, DROP_RATE, AUTODROPPER, QUEUE
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
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.AUTODROPPER),
		"AUTODROPPER unlocked")
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


## Single-currency redesign removed advanced (raw-currency edge) buckets from the
## level table — slot 9 is now an empty "complete the board" milestone. This is
## the regression guard that no UNLOCK_ADVANCED_BUCKET reward is ever reconciled,
## at any level (it used to fire once at gold level 10).
func test_advanced_buckets_never_reconciled() -> void:
	print("test_advanced_buckets_never_reconciled")
	_reset_state()
	LevelManager.current_level = 10  # well past every gold milestone slot

	var caught: Array[RewardData] = []
	var probe := func(reward: RewardData):
		if reward.type == RewardData.RewardType.UNLOCK_ADVANCED_BUCKET:
			caught.append(reward)
	LevelManager.reconcile_reward.connect(probe)

	LevelManager.ensure_state_for_level()

	LevelManager.reconcile_reward.disconnect(probe)

	assert_equal(caught.size(), 0,
		"single-currency model: UNLOCK_ADVANCED_BUCKET is never reconciled")


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


# The orange/red special-slot swap is built by _set_special_slot. The full
# level table only contains a tier once it's prestige-unlocked, so test the
# builder directly per board (deterministic, no prestige state needed).

func test_deflector_unlocks_on_orange_only() -> void:
	print("test_deflector_unlocks_on_orange_only")
	var data := LevelData.new()
	LevelManager._set_special_slot(data, Enums.BoardType.ORANGE,
		TierRegistry.get_next_tier(Enums.BoardType.ORANGE))
	var has_deflector := false
	for r in data.rewards:
		if r.type == RewardData.RewardType.UNLOCK_UPGRADE \
				and r.upgrade_type == Enums.UpgradeType.PEG_DEFLECTOR:
			has_deflector = true
			assert_equal(r.board_type, Enums.BoardType.ORANGE,
				"deflector unlock targets the orange board")
		assert_false(
			r.type == RewardData.RewardType.UNLOCK_ADVANCED_AUTODROPPER,
			"orange slot 4 no longer grants Advanced Autodropper")
	assert_true(has_deflector, "orange slot 4 unlocks PEG_DEFLECTOR")


func test_advanced_autodropper_moved_to_red() -> void:
	print("test_advanced_autodropper_moved_to_red")
	var data := LevelData.new()
	LevelManager._set_special_slot(data, Enums.BoardType.RED,
		TierRegistry.get_next_tier(Enums.BoardType.RED))
	var has_adv := false
	for r in data.rewards:
		if r.type == RewardData.RewardType.UNLOCK_UPGRADE \
				and r.upgrade_type == Enums.UpgradeType.ADVANCED_AUTODROPPER:
			has_adv = true
			assert_equal(r.board_type, Enums.BoardType.RED,
				"Advanced Autodropper unlock now targets the red board")
	assert_true(has_adv, "red slot 4 unlocks ADVANCED_AUTODROPPER")


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
