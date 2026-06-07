extends "res://test/test_base.gd"

## Coverage for the upgrade tuning + tooltip overhaul — run with:
##   godot --headless --scene res://test/test_upgrade_tuning.tscn
##
## Covers:
##  - PlinkoBoard._queue_capacity_for_level (queue is 0 until first level, then level+1)
##  - LevelManager gold unlock order (Autodropper before Queue) + the _set_queue_slot helper
##  - Autodropper / Advanced autodropper escalating cost curves (50/100/175/275/400)
##  - Queue cost curve + cap (15/30/65/120/195/290/405, cap 7)
##  - Every upgrade has a non-empty description (the hover tooltip relies on it)


func _run_tests() -> void:
	print("\n=== Upgrade Tuning Tests ===\n")
	test_queue_capacity_for_level()
	test_gold_unlocks_autodropper_before_queue()
	test_set_queue_slot_helper()
	test_autodropper_cost_curve()
	test_advanced_autodropper_cost_curve()
	test_queue_cost_curve_and_cap()
	test_all_upgrades_have_descriptions()


func test_queue_capacity_for_level() -> void:
	print("test_queue_capacity_for_level")
	# Empty until the first level; first level grants 2, each later level adds 1.
	assert_equal(PlinkoBoard._queue_capacity_for_level(0), 0, "level 0 -> 0 slots")
	assert_equal(PlinkoBoard._queue_capacity_for_level(1), 2, "level 1 -> 2 slots")
	assert_equal(PlinkoBoard._queue_capacity_for_level(2), 3, "level 2 -> 3 slots")
	assert_equal(PlinkoBoard._queue_capacity_for_level(7), 8, "level 7 (cap) -> 8 slots")


func test_gold_unlocks_autodropper_before_queue() -> void:
	print("test_gold_unlocks_autodropper_before_queue")
	LevelManager.rebuild_levels()
	# Gold tier is always levels[0..9]; slots 3 and 4 are swapped vs other boards.
	var slot3: LevelData = LevelManager.levels[3]
	var slot4: LevelData = LevelManager.levels[4]
	assert_true(_rewards_unlock_autodropper(slot3.rewards),
		"gold slot 3 unlocks the autodropper")
	assert_true(_rewards_unlock_upgrade(slot3.rewards, Enums.UpgradeType.AUTODROPPER),
		"gold slot 3 unlocks the autodropper upgrade")
	assert_true(_rewards_unlock_upgrade(slot4.rewards, Enums.UpgradeType.QUEUE),
		"gold slot 4 unlocks queue (pushed after autodropper)")
	# Sanity: queue is NOT at slot 3 anymore on gold.
	assert_false(_rewards_unlock_upgrade(slot3.rewards, Enums.UpgradeType.QUEUE),
		"gold slot 3 is no longer queue")


func test_set_queue_slot_helper() -> void:
	print("test_set_queue_slot_helper")
	# The helper other boards use at slot 3 — must yield a QUEUE upgrade unlock.
	var d := LevelData.new()
	LevelManager._set_queue_slot(d, Enums.BoardType.ORANGE, "Orange")
	assert_true(_rewards_unlock_upgrade(d.rewards, Enums.UpgradeType.QUEUE),
		"_set_queue_slot unlocks the queue upgrade")
	assert_false(d.message.is_empty(), "_set_queue_slot sets a message")


func test_autodropper_cost_curve() -> void:
	print("test_autodropper_cost_curve")
	_assert_cost_curve(Enums.UpgradeType.AUTODROPPER, [50, 100, 175, 275, 400], "autodropper")


func test_advanced_autodropper_cost_curve() -> void:
	print("test_advanced_autodropper_cost_curve")
	# Advanced is bought with the ORANGE board's currency, same curve as normal.
	_assert_cost_curve_for(Enums.BoardType.ORANGE, Enums.UpgradeType.ADVANCED_AUTODROPPER,
		[50, 100, 175, 275, 400], "advanced autodropper")


func test_queue_cost_curve_and_cap() -> void:
	print("test_queue_cost_curve_and_cap")
	_assert_cost_curve(Enums.UpgradeType.QUEUE, [15, 30, 65, 120, 195, 290, 405], "queue")
	UpgradeManager.reset()
	assert_equal(UpgradeManager.get_max_level(Enums.BoardType.GOLD, Enums.UpgradeType.QUEUE), 7,
		"queue cap is 7")


func test_all_upgrades_have_descriptions() -> void:
	print("test_all_upgrades_have_descriptions")
	for upgrade_type in Enums.UpgradeType.values():
		var data: BaseUpgradeData = UpgradeManager.get_upgrade(upgrade_type)
		assert_true(data != null, "%s is registered" % Enums.UpgradeType.keys()[upgrade_type])
		if data != null:
			assert_false(data.description.strip_edges().is_empty(),
				"%s has a tooltip description" % Enums.UpgradeType.keys()[upgrade_type])


# --- helpers ---

func _assert_cost_curve(upgrade_type: Enums.UpgradeType, expected: Array, label: String) -> void:
	_assert_cost_curve_for(Enums.BoardType.GOLD, upgrade_type, expected, label)


## force_apply advances cost without spending currency, so we can walk the curve
## headlessly without seeding balances.
func _assert_cost_curve_for(board: Enums.BoardType, upgrade_type: Enums.UpgradeType,
		expected: Array, label: String) -> void:
	UpgradeManager.reset()
	for i in expected.size():
		assert_equal(UpgradeManager.get_cost(board, upgrade_type), expected[i],
			"%s cost at level %d" % [label, i + 1])
		UpgradeManager.force_apply(board, upgrade_type)


func _rewards_unlock_autodropper(rewards: Array) -> bool:
	for r in rewards:
		if r.type == RewardData.RewardType.UNLOCK_AUTODROPPER:
			return true
	return false


func _rewards_unlock_upgrade(rewards: Array, upgrade_type: Enums.UpgradeType) -> bool:
	for r in rewards:
		if r.type == RewardData.RewardType.UNLOCK_UPGRADE and r.upgrade_type == upgrade_type:
			return true
	return false
