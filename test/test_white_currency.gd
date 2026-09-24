extends "res://test/test_base.gd"

## WhiteCurrency tests — run with:
##   godot --headless --scene res://test/test_white_currency.tscn
##
## WhiteCurrency is a pure static module, so every one of these runs without a
## board, a scene tree, or an autoload.


func _run_tests() -> void:
	print("\n=== WhiteCurrency Tests ===\n")

	test_binomial_edges()
	test_binomial_known_row()
	test_binomial_symmetric()
	test_binomial_out_of_range()
	test_bucket_value_is_the_linear_v()
	test_bucket_value_orange_is_exactly_three_times_gold()
	test_bucket_value_centre_is_one_before_tier_scaling()
	test_bucket_value_tier_multiplier_is_three_per_step()
	test_bucket_value_never_pays_nothing()
	test_bucket_value_symmetric()
	test_expected_value_is_probability_weighted()
	test_expected_value_of_no_earring_is_zero()
	test_is_gated_tier_boundary()
	test_drop_cost_zero_below_gate()
	test_drop_cost_authored_table()
	test_drop_cost_clamps_past_table()


# --- binomial ---

func test_binomial_edges() -> void:
	print("test_binomial_edges")
	assert_equal(WhiteCurrency.binomial(0, 0), 1, "C(0,0) = 1")
	assert_equal(WhiteCurrency.binomial(8, 0), 1, "C(8,0) = 1")
	assert_equal(WhiteCurrency.binomial(8, 8), 1, "C(8,8) = 1")


func test_binomial_known_row() -> void:
	print("test_binomial_known_row")
	# Pascal row 8: 1 8 28 56 70 56 28 8 1
	var expected: Array[int] = [1, 8, 28, 56, 70, 56, 28, 8, 1]
	for k in expected.size():
		assert_equal(WhiteCurrency.binomial(8, k), expected[k], "C(8,%d)" % k)


func test_binomial_symmetric() -> void:
	print("test_binomial_symmetric")
	# The mini(k, n-k) fold must not change the answer.
	for k in 13:
		assert_equal(WhiteCurrency.binomial(12, k), WhiteCurrency.binomial(12, 12 - k),
			"C(12,%d) == C(12,%d)" % [k, 12 - k])


func test_binomial_out_of_range() -> void:
	print("test_binomial_out_of_range")
	assert_equal(WhiteCurrency.binomial(4, -1), 0, "negative k = 0")
	assert_equal(WhiteCurrency.binomial(4, 5), 0, "k > n = 0")
	assert_equal(WhiteCurrency.binomial(-1, 0), 0, "negative n = 0")


# --- bucket_value ---

## The locked shape, read straight off a full-size gold earring.
func test_bucket_value_is_the_linear_v() -> void:
	print("test_bucket_value_is_the_linear_v")
	var expected: Array[int] = [5, 4, 3, 2, 1, 2, 3, 4, 5]
	for col in expected.size():
		assert_equal(WhiteCurrency.bucket_value(8, col, 0), expected[col],
			"gold 8-row col %d" % col)


## Orange is exactly 3x gold, bucket for bucket — the multiplier scales the whole
## V rather than being folded in before a rounding step.
func test_bucket_value_orange_is_exactly_three_times_gold() -> void:
	print("test_bucket_value_orange_is_exactly_three_times_gold")
	var expected: Array[int] = [15, 12, 9, 6, 3, 6, 9, 12, 15]
	for col in expected.size():
		assert_equal(WhiteCurrency.bucket_value(8, col, 1), expected[col],
			"orange 8-row col %d" % col)
		assert_equal(WhiteCurrency.bucket_value(8, col, 1),
			WhiteCurrency.bucket_value(8, col, 0) * 3, "col %d is 3x gold" % col)


func test_bucket_value_centre_is_one_before_tier_scaling() -> void:
	print("test_bucket_value_centre_is_one_before_tier_scaling")
	# Every earring size bottoms out at 1 on gold, like every other bucket row.
	for rows in [2, 4, 6, 8]:
		@warning_ignore("integer_division")
		var centre: int = (rows + 1) / 2
		assert_equal(WhiteCurrency.bucket_value(rows, centre, 0), 1,
			"%d-row centre pays 1" % rows)


func test_bucket_value_tier_multiplier_is_three_per_step() -> void:
	print("test_bucket_value_tier_multiplier_is_three_per_step")
	# Gold 1x, orange 3x, red 9x, violet 27x, blue 81x, green 243x.
	assert_equal(WhiteCurrency.bucket_value(8, 0, 0), 5, "tier 0 corner")
	assert_equal(WhiteCurrency.bucket_value(8, 0, 1), 15, "tier 1 corner = 5*3")
	assert_equal(WhiteCurrency.bucket_value(8, 0, 2), 45, "tier 2 corner = 5*9")
	assert_equal(WhiteCurrency.bucket_value(8, 0, 5), 1215, "tier 5 corner = 5*243")


func test_bucket_value_never_pays_nothing() -> void:
	print("test_bucket_value_never_pays_nothing")
	# A bucket that pays 0 reads as a bug rather than a small prize.
	for rows in range(1, 25):
		for col in rows + 1:
			assert_true(WhiteCurrency.bucket_value(rows, col, 0) >= 1,
				"rows %d col %d pays at least 1" % [rows, col])


func test_bucket_value_symmetric() -> void:
	print("test_bucket_value_symmetric")
	# Neither earring may be richer than the other. Earrings always grow two rows
	# at a time, so the bucket count is odd and the centre is a real bucket.
	for rows in [2, 4, 6, 8]:
		for col in rows + 1:
			assert_equal(WhiteCurrency.bucket_value(rows, col, 3),
				WhiteCurrency.bucket_value(rows, rows - col, 3),
				"%d-row col %d mirrors" % [rows, col])


## Under the linear V the buckets are NOT EV-equal — the cheap centre is by far
## the likeliest landing, so the expectation sits near the bottom of the range,
## not the middle of it. This is what OfflineCalculator credits a gateway.
func test_expected_value_is_probability_weighted() -> void:
	print("test_expected_value_is_probability_weighted")
	# Pascal row 8 = [1,8,28,56,70,56,28,8,1] over 256, against [5,4,3,2,1,2,3,4,5]:
	# (5+32+84+112+70+112+84+32+5) / 256 = 536/256 = 2.09375
	assert_near(WhiteCurrency.expected_value(8, 0), 2.09375, 0.0001,
		"gold 8-row earring expectation")
	assert_near(WhiteCurrency.expected_value(8, 1), 2.09375 * 3.0, 0.001,
		"orange is 3x the same expectation")
	# Well below the corner value — the corners are rare.
	assert_true(WhiteCurrency.expected_value(8, 0) < float(WhiteCurrency.bucket_value(8, 0, 0)),
		"expectation is far under the jackpot")
	assert_true(WhiteCurrency.expected_value(8, 0) > 1.0, "but above the centre bucket")


func test_expected_value_of_no_earring_is_zero() -> void:
	print("test_expected_value_of_no_earring_is_zero")
	assert_near(WhiteCurrency.expected_value(0, 0), 0.0, 0.0001, "no earring pays nothing")


# --- gating + drop cost ---

func test_is_gated_tier_boundary() -> void:
	print("test_is_gated_tier_boundary")
	assert_false(WhiteCurrency.is_gated_tier(0), "gold not gated")
	assert_false(WhiteCurrency.is_gated_tier(1), "orange not gated")
	assert_false(WhiteCurrency.is_gated_tier(2), "red not gated")
	assert_true(WhiteCurrency.is_gated_tier(3), "violet gated")
	assert_true(WhiteCurrency.is_gated_tier(5), "green gated")


func test_drop_cost_zero_below_gate() -> void:
	print("test_drop_cost_zero_below_gate")
	# Gold/orange/red must be untouched by white, or the early game changes.
	for tier in 3:
		assert_equal(WhiteCurrency.drop_cost(tier), 0, "tier %d costs no white" % tier)


func test_drop_cost_authored_table() -> void:
	print("test_drop_cost_authored_table")
	assert_equal(WhiteCurrency.drop_cost(3), 1, "violet costs 1 white")
	assert_equal(WhiteCurrency.drop_cost(4), 100, "blue costs 100 white")
	assert_equal(WhiteCurrency.drop_cost(5), 1000, "green costs 1000 white")


func test_drop_cost_clamps_past_table() -> void:
	print("test_drop_cost_clamps_past_table")
	# A seventh tier must degrade to "as expensive as green", never index past the
	# end of DROP_COSTS.
	assert_equal(WhiteCurrency.drop_cost(6), 1000, "tier past the table reuses the last entry")
	assert_equal(WhiteCurrency.drop_cost(99), 1000, "far past the table is still clamped")
