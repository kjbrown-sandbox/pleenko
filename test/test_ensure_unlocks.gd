extends "res://test/test_base.gd"

## ensure_unlocks_for_level() tests — run with:
##   godot --headless --scene res://test/test_ensure_unlocks.tscn
##
## Tests the failsafe that reconciles upgrade unlocks against the level table.
## Uses autoloads (LevelManager, UpgradeManager) which are available in headless mode.


func _run_tests() -> void:
	print("\n=== ensure_unlocks_for_level Tests ===\n")

	test_no_unlocks_at_level_zero()
	test_level_1_unlocks_add_row()
	test_level_2_unlocks_bucket_value()
	test_level_4_unlocks_drop_rate()
	test_level_5_unlocks_queue()
	test_all_gold_upgrades_unlocked_at_level_5()
	test_idempotent_when_already_unlocked()
	test_partial_unlocks_repaired()


func _reset_state() -> void:
	LevelManager.reset()
	LevelManager.rebuild_levels()
	UpgradeManager.reset()


# --- Test Cases ---

func test_no_unlocks_at_level_zero() -> void:
	print("test_no_unlocks_at_level_zero")
	_reset_state()
	LevelManager.current_level = 0
	LevelManager.ensure_unlocks_for_level()
	assert_false(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"ADD_ROW should NOT be unlocked at level 0")


func test_level_1_unlocks_add_row() -> void:
	print("test_level_1_unlocks_add_row")
	_reset_state()
	LevelManager.current_level = 1
	LevelManager.ensure_unlocks_for_level()
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"ADD_ROW should be unlocked at level 1")


func test_level_2_unlocks_bucket_value() -> void:
	print("test_level_2_unlocks_bucket_value")
	_reset_state()
	LevelManager.current_level = 2
	LevelManager.ensure_unlocks_for_level()
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE),
		"BUCKET_VALUE should be unlocked at level 2")


func test_level_4_unlocks_drop_rate() -> void:
	print("test_level_4_unlocks_drop_rate")
	_reset_state()
	LevelManager.current_level = 4
	LevelManager.ensure_unlocks_for_level()
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.DROP_RATE),
		"DROP_RATE should be unlocked at level 4")


func test_level_5_unlocks_queue() -> void:
	print("test_level_5_unlocks_queue")
	_reset_state()
	LevelManager.current_level = 5
	LevelManager.ensure_unlocks_for_level()
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.QUEUE),
		"QUEUE should be unlocked at level 5")


func test_all_gold_upgrades_unlocked_at_level_5() -> void:
	print("test_all_gold_upgrades_unlocked_at_level_5")
	_reset_state()
	LevelManager.current_level = 5
	LevelManager.ensure_unlocks_for_level()
	# Levels 0-4: ADD_ROW, BUCKET_VALUE, (coin drop), DROP_RATE, QUEUE
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
	LevelManager.ensure_unlocks_for_level()
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"ADD_ROW still unlocked")
	assert_true(
		UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE),
		"BUCKET_VALUE still unlocked")


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
	LevelManager.ensure_unlocks_for_level()
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
