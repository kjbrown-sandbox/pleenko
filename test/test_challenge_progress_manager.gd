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


func _reset() -> void:
	ChallengeProgressManager.deserialize({})


func _make_coin_speed_reward() -> ChallengeRewardData:
	var reward := ChallengeRewardData.new()
	reward.type = ChallengeRewardData.RewardType.STARTING_MODIFIER
	reward.modifier_type = ChallengeRewardData.ModifierType.GOLD_COIN_SPEED_BOOST
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
