extends "res://test/test_base.gd"

## ChallengeRewardData.display_text() tests — the single source of truth for
## challenge reward text (pre-challenge panel + post-challenge modal). Run with:
##   godot --headless --scene res://test/test_challenge_reward_data.tscn


func _run_tests() -> void:
	print("\n=== ChallengeRewardData.display_text() Tests ===\n")

	test_unlock()
	test_permanent_upgrade()
	test_starting_coins()
	test_multi_drop()
	test_advanced_coin_multiplier()
	test_center_bucket_value()
	test_drop_cost_reduction()
	test_golden_bucket_multiplier()
	test_bucket_value_percent()
	test_starting_autodroppers()
	test_gold_coin_speed_boost_tracks_constant()
	test_queue_rate_bonus_tracks_constant()
	test_no_modifier_returns_empty_string()


func _make(type: ChallengeRewardData.RewardType) -> ChallengeRewardData:
	var reward := ChallengeRewardData.new()
	reward.type = type
	return reward


func _make_modifier(modifier_type: ChallengeRewardData.ModifierType) -> ChallengeRewardData:
	var reward := _make(ChallengeRewardData.RewardType.STARTING_MODIFIER)
	reward.modifier_type = modifier_type
	return reward


# --- Test Cases ---

func test_unlock() -> void:
	print("test_unlock")
	var r := _make(ChallengeRewardData.RewardType.UNLOCK)
	r.unlock_type = ChallengeRewardData.UnlockType.HOLD_TO_DROP
	assert_equal(r.display_text(), "Unlocked: Hold To Drop", "UNLOCK / HOLD_TO_DROP")


func test_permanent_upgrade() -> void:
	print("test_permanent_upgrade")
	var r := _make(ChallengeRewardData.RewardType.PERMANENT_UPGRADE)
	r.upgrade_type = Enums.UpgradeType.BUCKET_VALUE
	r.board_type = Enums.BoardType.GOLD
	r.modifier_amount = 1.0
	assert_equal(r.display_text(), "+1 gold bucket value level", "PERMANENT_UPGRADE bucket value (gold)")


func test_starting_coins() -> void:
	print("test_starting_coins")
	var r := _make_modifier(ChallengeRewardData.ModifierType.STARTING_COINS)
	r.currency_type = Enums.CurrencyType.GOLD_COIN
	r.modifier_amount = 5.0
	assert_equal(r.display_text(), "+5 starting gold", "STARTING_COINS gold")


func test_multi_drop() -> void:
	print("test_multi_drop")
	var r := _make_modifier(ChallengeRewardData.ModifierType.MULTI_DROP)
	r.board_type = Enums.BoardType.GOLD
	r.modifier_amount = 1.0
	assert_equal(r.display_text(), "+1 gold multi-drop", "MULTI_DROP gold")


func test_advanced_coin_multiplier() -> void:
	print("test_advanced_coin_multiplier")
	var r := _make_modifier(ChallengeRewardData.ModifierType.ADVANCED_COIN_MULTIPLIER)
	r.board_type = Enums.BoardType.GOLD
	r.modifier_amount = 0.5
	assert_equal(r.display_text(), "+0.5 raw orange multiplier", "ADVANCED_COIN_MULTIPLIER gold → raw orange")


## New single-currency-redesign modifier rewards.

func test_center_bucket_value() -> void:
	print("test_center_bucket_value")
	var r := _make_modifier(ChallengeRewardData.ModifierType.CENTER_BUCKET_VALUE)
	r.board_type = Enums.BoardType.GOLD
	r.modifier_amount = 3.0
	assert_equal(r.display_text(), "+3 gold middle bucket value", "CENTER_BUCKET_VALUE gold")


func test_drop_cost_reduction() -> void:
	print("test_drop_cost_reduction")
	# Orange's fuel is the previous tier's primary currency (gold).
	var r := _make_modifier(ChallengeRewardData.ModifierType.DROP_COST_REDUCTION)
	r.board_type = Enums.BoardType.ORANGE
	r.modifier_amount = 10.0
	assert_equal(r.display_text(), "Orange coins cost 10 less gold", "DROP_COST_REDUCTION orange → gold fuel")


func test_golden_bucket_multiplier() -> void:
	print("test_golden_bucket_multiplier")
	var r := _make_modifier(ChallengeRewardData.ModifierType.GOLDEN_BUCKET_MULTIPLIER)
	r.board_type = Enums.BoardType.GOLD
	r.modifier_amount = 0.5
	assert_equal(r.display_text(), "+0.5 gold golden bucket multiplier", "GOLDEN_BUCKET_MULTIPLIER gold")


func test_bucket_value_percent() -> void:
	print("test_bucket_value_percent")
	var r := _make_modifier(ChallengeRewardData.ModifierType.BUCKET_VALUE_PERCENT)
	r.board_type = Enums.BoardType.GOLD
	r.modifier_amount = 1.0
	assert_equal(r.display_text(), "+100% gold bucket value", "BUCKET_VALUE_PERCENT gold")


func test_starting_autodroppers() -> void:
	print("test_starting_autodroppers")
	var r := _make_modifier(ChallengeRewardData.ModifierType.STARTING_AUTODROPPERS)
	r.board_type = Enums.BoardType.GOLD
	r.modifier_amount = 2.0
	assert_equal(r.display_text(), "+2 starting gold autodroppers", "STARTING_AUTODROPPERS gold")


## The displayed magnitude must track the gameplay constant, not a literal —
## that's the whole point of generating it live.
func test_gold_coin_speed_boost_tracks_constant() -> void:
	print("test_gold_coin_speed_boost_tracks_constant")
	var r := _make_modifier(ChallengeRewardData.ModifierType.GOLD_COIN_SPEED_BOOST)
	var expected := "+%d%% gold coin fall speed" % int(Coin.COIN_SPEED_BOOST_PER_UNLOCK * 100)
	assert_equal(r.display_text(), expected, "GOLD_COIN_SPEED_BOOST tracks Coin constant")


## QUEUE_RATE_BONUS had NO post-challenge case before this refactor — it
## rendered as "". This is the regression test for that bug.
func test_queue_rate_bonus_tracks_constant() -> void:
	print("test_queue_rate_bonus_tracks_constant")
	var r := _make_modifier(ChallengeRewardData.ModifierType.QUEUE_RATE_BONUS)
	var expected := "+%d%% gold queue bonus" % int(PlinkoBoard.QUEUE_RATE_BONUS_PER_UNLOCK * 100)
	assert_equal(r.display_text(), expected, "QUEUE_RATE_BONUS tracks PlinkoBoard constant")


## Guards the append-only ModifierType enum: every reward kind must produce
## non-empty text. A future appended modifier (or reordered enum) fails here
## until display_text() handles it — exactly the gap that hid the QUEUE bug.
func test_no_modifier_returns_empty_string() -> void:
	print("test_no_modifier_returns_empty_string")
	for mt: int in ChallengeRewardData.ModifierType.values():
		var r := _make_modifier(mt as ChallengeRewardData.ModifierType)
		assert_true(r.display_text() != "", "STARTING_MODIFIER %d non-empty" % mt)

	var unlock := _make(ChallengeRewardData.RewardType.UNLOCK)
	unlock.unlock_type = ChallengeRewardData.UnlockType.HOLD_TO_DROP
	assert_true(unlock.display_text() != "", "UNLOCK non-empty")

	var perm := _make(ChallengeRewardData.RewardType.PERMANENT_UPGRADE)
	perm.upgrade_type = Enums.UpgradeType.BUCKET_VALUE
	perm.board_type = Enums.BoardType.GOLD
	assert_true(perm.display_text() != "", "PERMANENT_UPGRADE non-empty")
