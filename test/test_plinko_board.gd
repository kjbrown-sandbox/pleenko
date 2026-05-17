extends "res://test/test_base.gd"

## PlinkoBoard tests — run with:
##   godot --headless --scene res://test/test_plinko_board.tscn
##
## Tests pure-logic functions on a bare PlinkoBoard instance (no scene tree,
## no @onready nodes). We set member vars directly and call the functions.


func _run_tests() -> void:
	print("\n=== PlinkoBoard Tests ===\n")

	test_bucket_value_basic()
	test_bucket_value_with_multiplier()
	test_bucket_value_advanced_offset()
	test_bucket_value_below_advanced_threshold()
	test_bucket_position_key_positive()
	test_bucket_position_key_negative()
	test_bucket_position_key_zero()
	test_get_bounds_geometry()
	test_has_in_flight_coins_empty()
	test_hold_drop_first_press_fires_immediately()
	test_hold_drop_rate_limited_to_interval()
	test_hold_drop_release_resets_accumulator()
	test_hold_drop_advanced_uses_same_accumulator()
	test_reconcile_reward_ignores_wrong_type()
	test_reconcile_reward_ignores_wrong_board()
	test_reconcile_reward_ignores_already_set()
	test_queue_rate_bonus_gold_zero_grants_is_base()
	test_queue_rate_bonus_gold_applies_grant_count()
	test_queue_rate_bonus_non_gold_stays_base()


# --- Helper ---

## Creates a bare PlinkoBoard with no scene tree. Only member vars are
## available — @onready fields are null. Sufficient for pure-logic tests.
func _make_board(overrides: Dictionary = {}) -> PlinkoBoard:
	var board := PlinkoBoard.new()
	board.board_type = overrides.get("board_type", Enums.BoardType.GOLD)
	board.num_rows = overrides.get("num_rows", 4)
	board.bucket_value_multiplier = overrides.get("bucket_value_multiplier", 1)
	board.distance_for_advanced_buckets = overrides.get("distance_for_advanced_buckets", 3)
	board.should_show_advanced_buckets = overrides.get("should_show_advanced_buckets", false)
	board.space_between_pegs = overrides.get("space_between_pegs", 1.0)
	board.vertical_spacing = overrides.get("vertical_spacing", 1.0)
	return board


# --- Bucket value tests ---

func test_bucket_value_basic() -> void:
	print("test_bucket_value_basic")
	# multiplier=1, distance=2, no advanced buckets
	# val = 1 + 2 * 1 = 3
	var board := _make_board()
	assert_equal(board._bucket_value_for_distance(2), 3, "1 + 2*1 = 3")
	board.free()


func test_bucket_value_with_multiplier() -> void:
	print("test_bucket_value_with_multiplier")
	# multiplier=3, distance=2
	# val = 1 + 2 * 3 = 7
	var board := _make_board({"bucket_value_multiplier": 3})
	assert_equal(board._bucket_value_for_distance(2), 7, "1 + 2*3 = 7")
	board.free()


func test_bucket_value_advanced_offset() -> void:
	print("test_bucket_value_advanced_offset")
	# distance=4, advanced_distance=3, show_advanced=true, multiplier=1
	# effective_distance = 4 - 3 = 1, val = 1 + 1*1 = 2
	var board := _make_board({
		"distance_for_advanced_buckets": 3,
		"should_show_advanced_buckets": true,
	})
	assert_equal(board._bucket_value_for_distance(4), 2, "advanced offset: 1 + (4-3)*1 = 2")
	board.free()


func test_bucket_value_below_advanced_threshold() -> void:
	print("test_bucket_value_below_advanced_threshold")
	# distance=2, advanced_distance=3, show_advanced=true
	# distance < advanced_distance, so no offset
	# val = 1 + 2 * 1 = 3
	var board := _make_board({
		"distance_for_advanced_buckets": 3,
		"should_show_advanced_buckets": true,
	})
	assert_equal(board._bucket_value_for_distance(2), 3, "below threshold: no offset")
	board.free()


# --- Bucket position key tests ---

func test_bucket_position_key_positive() -> void:
	print("test_bucket_position_key_positive")
	var board := _make_board()
	# 1.234 * 1000 = 1234
	assert_equal(board._bucket_position_key(1.234), 1234, "positive x -> 1234")
	board.free()


func test_bucket_position_key_negative() -> void:
	print("test_bucket_position_key_negative")
	var board := _make_board()
	# -0.5 * 1000 = -500
	assert_equal(board._bucket_position_key(-0.5), -500, "negative x -> -500")
	board.free()


func test_bucket_position_key_zero() -> void:
	print("test_bucket_position_key_zero")
	var board := _make_board()
	assert_equal(board._bucket_position_key(0.0), 0, "zero x -> 0")
	board.free()


# --- Bounds geometry test ---

func test_get_bounds_geometry() -> void:
	print("test_get_bounds_geometry")
	# num_rows=4, vertical_spacing=1.0, space_between_pegs=1.0
	# top = 1.0 + 0.5 = 1.5
	# bottom = -1.0 * 4 + (1.0/3) - 0.5 = -4 + 0.333 - 0.5 = -4.167
	# half_width = (4/2.0) * 1.0 + 0.5 = 2.5
	# Rect2(-2.5, -4.167, 5.0, 5.667)
	var board := _make_board({"num_rows": 4, "vertical_spacing": 1.0, "space_between_pegs": 1.0})
	var bounds: Rect2 = board.get_bounds()
	assert_near(bounds.position.x, -2.5, 0.01, "bounds x")
	assert_near(bounds.size.x, 5.0, 0.01, "bounds width")
	assert_true(bounds.position.y < 0.0, "bounds bottom is negative")
	assert_true(bounds.size.y > 0.0, "bounds height is positive")
	board.free()


# --- In-flight coins test ---

func test_has_in_flight_coins_empty() -> void:
	print("test_has_in_flight_coins_empty")
	var board := _make_board()
	assert_false(board.has_in_flight_coins(), "no coins in flight on fresh board")
	board.free()


# --- Hold-to-drop pacing tests ---

func test_hold_drop_first_press_fires_immediately() -> void:
	print("test_hold_drop_first_press_fires_immediately")
	var board := _make_board()
	# Accumulator is primed so a fresh press fires on its first tick.
	assert_true(board._tick_hold_drop_accumulator(0.016, true), "first frame of press fires")
	board.free()


func test_hold_drop_rate_limited_to_interval() -> void:
	print("test_hold_drop_rate_limited_to_interval")
	var board := _make_board()
	# Burn the priming fire so we're measuring from a fresh accumulator at 0.
	assert_true(board._tick_hold_drop_accumulator(0.016, true), "primed fire")
	# 60 fps frames totaling ~99ms: still under the 100ms interval.
	for i in 6:
		assert_false(board._tick_hold_drop_accumulator(0.0165, true), "frame %d should not fire" % i)
	# Next frame crosses 100ms total → fires.
	assert_true(board._tick_hold_drop_accumulator(0.0165, true), "fires after >=100ms accumulated")
	board.free()


func test_hold_drop_release_resets_accumulator() -> void:
	print("test_hold_drop_release_resets_accumulator")
	var board := _make_board()
	# Hold long enough to fire and start a fresh interval.
	board._tick_hold_drop_accumulator(0.016, true)
	board._tick_hold_drop_accumulator(0.05, true)  # accumulator at 0.05, no fire
	# Release: accumulator must reset so the next press fires immediately.
	assert_false(board._tick_hold_drop_accumulator(0.016, false), "release does not fire")
	assert_true(board._tick_hold_drop_accumulator(0.016, true), "next press fires immediately")
	board.free()


func test_hold_drop_advanced_uses_same_accumulator() -> void:
	print("test_hold_drop_advanced_uses_same_accumulator")
	# Normal and advanced hold both pass is_pressed=true to _tick_hold_drop_accumulator.
	# Verify the pacing is identical — no separate accumulator was introduced.
	var board := _make_board()
	assert_true(board._tick_hold_drop_accumulator(0.016, true), "advanced: first press fires immediately")
	board._tick_hold_drop_accumulator(0.05, true)  # partial interval
	assert_false(board._tick_hold_drop_accumulator(0.016, true), "advanced: mid-interval does not fire")
	assert_true(board._tick_hold_drop_accumulator(0.035, true), "advanced: fires after 100ms total")
	board.free()


# --- Reconcile reward guard tests ---
# _on_reconcile_reward must early-return for wrong type / wrong board / already-
# set, since the happy path calls build_board() which touches @onready nodes
# and would crash a bare-instance test. Manual integration test covers the
# happy path on a real scene.

func test_reconcile_reward_ignores_wrong_type() -> void:
	print("test_reconcile_reward_ignores_wrong_type")
	var board := _make_board({"board_type": Enums.BoardType.GOLD})
	var reward := RewardData.new()
	reward.type = RewardData.RewardType.UNLOCK_UPGRADE
	reward.board_type = Enums.BoardType.GOLD
	reward.target_board = Enums.BoardType.GOLD
	board._on_reconcile_reward(reward)
	assert_false(board.should_show_advanced_buckets,
		"non-UNLOCK_ADVANCED_BUCKET reward must not flip the flag")
	board.free()


func test_reconcile_reward_ignores_wrong_board() -> void:
	print("test_reconcile_reward_ignores_wrong_board")
	var board := _make_board({"board_type": Enums.BoardType.GOLD})
	var reward := RewardData.new()
	reward.type = RewardData.RewardType.UNLOCK_ADVANCED_BUCKET
	reward.target_board = Enums.BoardType.ORANGE  # wrong board
	board._on_reconcile_reward(reward)
	assert_false(board.should_show_advanced_buckets,
		"reward targeting different board must not flip the flag")
	board.free()


func test_reconcile_reward_ignores_already_set() -> void:
	print("test_reconcile_reward_ignores_already_set")
	# If the flag is already set, the handler must early-return *before* build_board()
	# (which would crash without @onready nodes). Reaching this assertion proves it.
	var board := _make_board({
		"board_type": Enums.BoardType.GOLD,
		"should_show_advanced_buckets": true,
	})
	var reward := RewardData.new()
	reward.type = RewardData.RewardType.UNLOCK_ADVANCED_BUCKET
	reward.target_board = Enums.BoardType.GOLD
	board._on_reconcile_reward(reward)
	assert_true(board.should_show_advanced_buckets, "flag remains set")
	board.free()


# --- Queue rate bonus: gold-only challenge reward ---

## Resets ChallengeProgressManager and grants `n` QUEUE_RATE_BONUS rewards
## (one per synthetic challenge so the one-time-per-challenge guard allows all).
func _grant_queue_rate_rewards(n: int) -> void:
	ChallengeProgressManager.deserialize({})
	for i in n:
		var reward := ChallengeRewardData.new()
		reward.type = ChallengeRewardData.RewardType.STARTING_MODIFIER
		reward.modifier_type = ChallengeRewardData.ModifierType.QUEUE_RATE_BONUS
		ChallengeProgressManager.complete_challenge("qrb_%d" % i, [], [reward])


func test_queue_rate_bonus_gold_zero_grants_is_base() -> void:
	print("test_queue_rate_bonus_gold_zero_grants_is_base")
	_grant_queue_rate_rewards(0)
	var board := _make_board({"board_type": Enums.BoardType.GOLD})
	assert_near(board._queue_rate_bonus_for_board(Enums.BoardType.GOLD),
		PlinkoBoard.QUEUE_RATE_BONUS_PER_COIN, 0.0001, "no grants → base bonus")
	board.free()


func test_queue_rate_bonus_gold_applies_grant_count() -> void:
	print("test_queue_rate_bonus_gold_applies_grant_count")
	_grant_queue_rate_rewards(2)
	var board := _make_board({"board_type": Enums.BoardType.GOLD})
	var expected: float = PlinkoBoard.QUEUE_RATE_BONUS_PER_COIN \
		+ 2 * PlinkoBoard.QUEUE_RATE_BONUS_PER_UNLOCK
	assert_near(board._queue_rate_bonus_for_board(Enums.BoardType.GOLD),
		expected, 0.0001, "gold board stacks 2 grants onto the base")
	board.free()


func test_queue_rate_bonus_non_gold_stays_base() -> void:
	print("test_queue_rate_bonus_non_gold_stays_base")
	_grant_queue_rate_rewards(2)
	var board := _make_board({"board_type": Enums.BoardType.ORANGE})
	assert_near(board._queue_rate_bonus_for_board(Enums.BoardType.ORANGE),
		PlinkoBoard.QUEUE_RATE_BONUS_PER_COIN, 0.0001,
		"non-gold board ignores the gold-only reward")
	board.free()
