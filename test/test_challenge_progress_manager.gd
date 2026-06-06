extends "res://test/test_base.gd"

## ChallengeProgressManager tests — run with:
##   godot --headless --scene res://test/test_challenge_progress_manager.tscn


func _run_tests() -> void:
	print("\n=== ChallengeProgressManager Tests ===\n")

	test_gold_coin_speed_boost_count_starts_at_zero()
	test_gold_coin_speed_boost_count_after_one_grant()
	test_gold_coin_speed_boost_count_stacks_across_challenges()
	test_gold_coin_speed_boost_count_round_trip()
	test_gold_coin_speed_boost_one_time_per_challenge()

	test_queue_rate_bonus_count_starts_at_zero()
	test_queue_rate_bonus_count_after_one_grant()
	test_queue_rate_bonus_count_stacks_across_challenges()
	test_queue_rate_bonus_count_round_trip()
	test_queue_rate_bonus_one_time_per_challenge()
	test_queue_rate_bonus_independent_of_speed_boost()

	test_center_bucket_value_bonus_sums_per_board()
	test_center_bucket_value_bonus_zero_without_grant()
	test_drop_cost_reduction_sums_per_board()
	test_golden_bucket_multiplier_bonus_sums_per_board()
	test_new_board_getters_isolated_from_each_other()


func _reset() -> void:
	ChallengeProgressManager.deserialize({})


func _make_coin_speed_reward() -> ChallengeRewardData:
	var reward := ChallengeRewardData.new()
	reward.type = ChallengeRewardData.RewardType.STARTING_MODIFIER
	reward.modifier_type = ChallengeRewardData.ModifierType.GOLD_COIN_SPEED_BOOST
	return reward


func _make_queue_rate_reward() -> ChallengeRewardData:
	var reward := ChallengeRewardData.new()
	reward.type = ChallengeRewardData.RewardType.STARTING_MODIFIER
	reward.modifier_type = ChallengeRewardData.ModifierType.QUEUE_RATE_BONUS
	return reward


# --- Test Cases ---

func test_gold_coin_speed_boost_count_starts_at_zero() -> void:
	print("test_gold_coin_speed_boost_count_starts_at_zero")
	_reset()
	assert_equal(ChallengeProgressManager.get_gold_coin_speed_boost_count(), 0, "no grants → count 0")


func test_gold_coin_speed_boost_count_after_one_grant() -> void:
	print("test_gold_coin_speed_boost_count_after_one_grant")
	_reset()
	var rewards: Array[ChallengeRewardData] = [_make_coin_speed_reward()]
	ChallengeProgressManager.complete_challenge("test_a", [], rewards)
	assert_equal(ChallengeProgressManager.get_gold_coin_speed_boost_count(), 1, "one grant → count 1")


func test_gold_coin_speed_boost_count_stacks_across_challenges() -> void:
	print("test_gold_coin_speed_boost_count_stacks_across_challenges")
	_reset()
	var rewards_a: Array[ChallengeRewardData] = [_make_coin_speed_reward()]
	var rewards_b: Array[ChallengeRewardData] = [_make_coin_speed_reward()]
	ChallengeProgressManager.complete_challenge("test_a", [], rewards_a)
	ChallengeProgressManager.complete_challenge("test_b", [], rewards_b)
	assert_equal(ChallengeProgressManager.get_gold_coin_speed_boost_count(), 2, "two grants → count 2")


func test_gold_coin_speed_boost_count_round_trip() -> void:
	print("test_gold_coin_speed_boost_count_round_trip")
	_reset()
	var rewards_a: Array[ChallengeRewardData] = [_make_coin_speed_reward()]
	var rewards_b: Array[ChallengeRewardData] = [_make_coin_speed_reward()]
	ChallengeProgressManager.complete_challenge("test_a", [], rewards_a)
	ChallengeProgressManager.complete_challenge("test_b", [], rewards_b)
	var data := ChallengeProgressManager.serialize()
	_reset()
	ChallengeProgressManager.deserialize(data)
	assert_equal(ChallengeProgressManager.get_gold_coin_speed_boost_count(), 2, "count survives save/load")


func test_gold_coin_speed_boost_one_time_per_challenge() -> void:
	print("test_gold_coin_speed_boost_one_time_per_challenge")
	_reset()
	var rewards: Array[ChallengeRewardData] = [_make_coin_speed_reward()]
	ChallengeProgressManager.complete_challenge("test_a", [], rewards)
	ChallengeProgressManager.complete_challenge("test_a", [], rewards)
	assert_equal(ChallengeProgressManager.get_gold_coin_speed_boost_count(), 1, "re-completing same challenge doesn't double-grant")


func test_queue_rate_bonus_count_starts_at_zero() -> void:
	print("test_queue_rate_bonus_count_starts_at_zero")
	_reset()
	assert_equal(ChallengeProgressManager.get_queue_rate_bonus_count(), 0, "no grants → count 0")


func test_queue_rate_bonus_count_after_one_grant() -> void:
	print("test_queue_rate_bonus_count_after_one_grant")
	_reset()
	var rewards: Array[ChallengeRewardData] = [_make_queue_rate_reward()]
	ChallengeProgressManager.complete_challenge("test_a", [], rewards)
	assert_equal(ChallengeProgressManager.get_queue_rate_bonus_count(), 1, "one grant → count 1")


func test_queue_rate_bonus_count_stacks_across_challenges() -> void:
	print("test_queue_rate_bonus_count_stacks_across_challenges")
	_reset()
	var rewards_a: Array[ChallengeRewardData] = [_make_queue_rate_reward()]
	var rewards_b: Array[ChallengeRewardData] = [_make_queue_rate_reward()]
	ChallengeProgressManager.complete_challenge("test_a", [], rewards_a)
	ChallengeProgressManager.complete_challenge("test_b", [], rewards_b)
	assert_equal(ChallengeProgressManager.get_queue_rate_bonus_count(), 2, "two grants → count 2")


func test_queue_rate_bonus_count_round_trip() -> void:
	print("test_queue_rate_bonus_count_round_trip")
	_reset()
	var rewards_a: Array[ChallengeRewardData] = [_make_queue_rate_reward()]
	var rewards_b: Array[ChallengeRewardData] = [_make_queue_rate_reward()]
	ChallengeProgressManager.complete_challenge("test_a", [], rewards_a)
	ChallengeProgressManager.complete_challenge("test_b", [], rewards_b)
	var data := ChallengeProgressManager.serialize()
	_reset()
	ChallengeProgressManager.deserialize(data)
	assert_equal(ChallengeProgressManager.get_queue_rate_bonus_count(), 2, "count survives save/load")


func test_queue_rate_bonus_one_time_per_challenge() -> void:
	print("test_queue_rate_bonus_one_time_per_challenge")
	_reset()
	var rewards: Array[ChallengeRewardData] = [_make_queue_rate_reward()]
	ChallengeProgressManager.complete_challenge("test_a", [], rewards)
	ChallengeProgressManager.complete_challenge("test_a", [], rewards)
	assert_equal(ChallengeProgressManager.get_queue_rate_bonus_count(), 1, "re-completing same challenge doesn't double-grant")


## The two stackable modifier counters must not bleed into each other — they
## share _starting_modifiers and are distinguished only by modifier_type.
func test_queue_rate_bonus_independent_of_speed_boost() -> void:
	print("test_queue_rate_bonus_independent_of_speed_boost")
	_reset()
	var rewards: Array[ChallengeRewardData] = [_make_coin_speed_reward()]
	ChallengeProgressManager.complete_challenge("test_a", [], rewards)
	assert_equal(ChallengeProgressManager.get_queue_rate_bonus_count(), 0, "speed-boost grant doesn't count as queue-rate")
	assert_equal(ChallengeProgressManager.get_gold_coin_speed_boost_count(), 1, "speed-boost still counted")


# --- New board-scoped getters (single-currency redesign) ---

## Board-scoped modifier reward (CENTER_BUCKET_VALUE / DROP_COST_REDUCTION /
## GOLDEN_BUCKET_MULTIPLIER), with an explicit amount + target board.
func _make_board_modifier(modifier_type: ChallengeRewardData.ModifierType,
		board: Enums.BoardType, amount: float) -> ChallengeRewardData:
	var reward := ChallengeRewardData.new()
	reward.type = ChallengeRewardData.RewardType.STARTING_MODIFIER
	reward.modifier_type = modifier_type
	reward.board_type = board
	reward.modifier_amount = amount
	return reward


func test_center_bucket_value_bonus_sums_per_board() -> void:
	print("test_center_bucket_value_bonus_sums_per_board")
	_reset()
	var a: Array[ChallengeRewardData] = [_make_board_modifier(
		ChallengeRewardData.ModifierType.CENTER_BUCKET_VALUE, Enums.BoardType.GOLD, 3.0)]
	var b: Array[ChallengeRewardData] = [_make_board_modifier(
		ChallengeRewardData.ModifierType.CENTER_BUCKET_VALUE, Enums.BoardType.GOLD, 2.0)]
	var c: Array[ChallengeRewardData] = [_make_board_modifier(
		ChallengeRewardData.ModifierType.CENTER_BUCKET_VALUE, Enums.BoardType.ORANGE, 5.0)]
	ChallengeProgressManager.complete_challenge("a", [], a)
	ChallengeProgressManager.complete_challenge("b", [], b)
	ChallengeProgressManager.complete_challenge("c", [], c)
	assert_equal(ChallengeProgressManager.get_center_bucket_value_bonus(Enums.BoardType.GOLD), 5,
		"gold center bonus sums (3 + 2)")
	assert_equal(ChallengeProgressManager.get_center_bucket_value_bonus(Enums.BoardType.ORANGE), 5,
		"orange center bonus is isolated to its own board")


func test_center_bucket_value_bonus_zero_without_grant() -> void:
	print("test_center_bucket_value_bonus_zero_without_grant")
	_reset()
	assert_equal(ChallengeProgressManager.get_center_bucket_value_bonus(Enums.BoardType.GOLD), 0,
		"no grant → 0")


func test_drop_cost_reduction_sums_per_board() -> void:
	print("test_drop_cost_reduction_sums_per_board")
	_reset()
	var a: Array[ChallengeRewardData] = [_make_board_modifier(
		ChallengeRewardData.ModifierType.DROP_COST_REDUCTION, Enums.BoardType.ORANGE, 10.0)]
	var b: Array[ChallengeRewardData] = [_make_board_modifier(
		ChallengeRewardData.ModifierType.DROP_COST_REDUCTION, Enums.BoardType.ORANGE, 15.0)]
	ChallengeProgressManager.complete_challenge("a", [], a)
	ChallengeProgressManager.complete_challenge("b", [], b)
	assert_equal(ChallengeProgressManager.get_drop_cost_reduction(Enums.BoardType.ORANGE), 25,
		"orange drop-cost reduction sums (10 + 15)")
	assert_equal(ChallengeProgressManager.get_drop_cost_reduction(Enums.BoardType.GOLD), 0,
		"gold has no reduction grant")


func test_golden_bucket_multiplier_bonus_sums_per_board() -> void:
	print("test_golden_bucket_multiplier_bonus_sums_per_board")
	_reset()
	var a: Array[ChallengeRewardData] = [_make_board_modifier(
		ChallengeRewardData.ModifierType.GOLDEN_BUCKET_MULTIPLIER, Enums.BoardType.GOLD, 0.5)]
	var b: Array[ChallengeRewardData] = [_make_board_modifier(
		ChallengeRewardData.ModifierType.GOLDEN_BUCKET_MULTIPLIER, Enums.BoardType.GOLD, 1.5)]
	ChallengeProgressManager.complete_challenge("a", [], a)
	ChallengeProgressManager.complete_challenge("b", [], b)
	assert_near(ChallengeProgressManager.get_golden_bucket_multiplier_bonus(Enums.BoardType.GOLD), 2.0, 0.001,
		"gold golden-bucket multiplier bonus sums (0.5 + 1.5)")
	assert_near(ChallengeProgressManager.get_golden_bucket_multiplier_bonus(Enums.BoardType.ORANGE), 0.0, 0.001,
		"orange has no golden-bucket grant")


## The three new getters share _starting_modifiers and are distinguished only by
## modifier_type — a grant of one must never leak into the others.
func test_new_board_getters_isolated_from_each_other() -> void:
	print("test_new_board_getters_isolated_from_each_other")
	_reset()
	var rewards: Array[ChallengeRewardData] = [_make_board_modifier(
		ChallengeRewardData.ModifierType.CENTER_BUCKET_VALUE, Enums.BoardType.GOLD, 4.0)]
	ChallengeProgressManager.complete_challenge("a", [], rewards)
	assert_equal(ChallengeProgressManager.get_center_bucket_value_bonus(Enums.BoardType.GOLD), 4,
		"center bucket value counted")
	assert_equal(ChallengeProgressManager.get_drop_cost_reduction(Enums.BoardType.GOLD), 0,
		"center grant does not count as drop-cost reduction")
	assert_near(ChallengeProgressManager.get_golden_bucket_multiplier_bonus(Enums.BoardType.GOLD), 0.0, 0.001,
		"center grant does not count as golden-bucket multiplier")
