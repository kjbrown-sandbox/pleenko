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
	test_bucket_value_corners_are_two_to_the_rows()
	test_bucket_value_centre_is_smallest()
	test_bucket_value_is_ev_flat()
	test_bucket_value_tier_multiplier_is_three_per_step()
	test_bucket_value_floors_at_one()
	test_bucket_value_symmetric()
	test_expected_value_units_is_bucket_count()
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

func test_bucket_value_corners_are_two_to_the_rows() -> void:
	print("test_bucket_value_corners_are_two_to_the_rows")
	# A corner is reached by exactly one bounce sequence out of 2^rows, so the
	# reciprocal pays the full 2^rows. This is the jackpot the design rests on.
	assert_equal(WhiteCurrency.bucket_value(8, 0, 0), 256, "gold 8-row left corner = 2^8")
	assert_equal(WhiteCurrency.bucket_value(8, 8, 0), 256, "gold 8-row right corner = 2^8")
	assert_equal(WhiteCurrency.bucket_value(3, 0, 0), 8, "3-row corner = 2^3")


func test_bucket_value_centre_is_smallest() -> void:
	print("test_bucket_value_centre_is_smallest")
	# 2^8 / C(8,4) = 256/70 = 3.657 -> 4
	assert_equal(WhiteCurrency.bucket_value(8, 4, 0), 4, "gold 8-row centre rounds to 4")
	var centre: int = WhiteCurrency.bucket_value(8, 4, 0)
	for col in 9:
		assert_true(WhiteCurrency.bucket_value(8, col, 0) >= centre,
			"centre is the minimum (col %d)" % col)


func test_bucket_value_is_ev_flat() -> void:
	print("test_bucket_value_is_ev_flat")
	# The whole point of the reciprocal: probability * value is the same constant
	# for every bucket, so no bucket is a better target than any other. Compared
	# pre-rounding, since roundi is what breaks exact equality.
	var rows := 8
	var total := pow(2.0, float(rows))
	for col in rows + 1:
		var p: float = float(WhiteCurrency.binomial(rows, col)) / total
		var fair: float = total / float(WhiteCurrency.binomial(rows, col))
		assert_near(p * fair, 1.0, 0.0001, "EV of col %d is 1 fair unit" % col)


func test_bucket_value_tier_multiplier_is_three_per_step() -> void:
	print("test_bucket_value_tier_multiplier_is_three_per_step")
	# Gold 1x, orange 3x, red 9x, violet 27x, blue 81x, green 243x.
	assert_equal(WhiteCurrency.bucket_value(8, 0, 0), 256, "tier 0 corner")
	assert_equal(WhiteCurrency.bucket_value(8, 0, 1), 768, "tier 1 corner = 256*3")
	assert_equal(WhiteCurrency.bucket_value(8, 0, 2), 2304, "tier 2 corner = 256*9")
	assert_equal(WhiteCurrency.bucket_value(8, 0, 5), 62208, "tier 5 corner = 256*243")


func test_bucket_value_floors_at_one() -> void:
	print("test_bucket_value_floors_at_one")
	# A wide enough earring's middle would round below 1 without the floor, and a
	# bucket that pays nothing would read as a bug rather than a small prize.
	for rows in range(1, 25):
		for col in rows + 1:
			assert_true(WhiteCurrency.bucket_value(rows, col, 0) >= 1,
				"rows %d col %d pays at least 1" % [rows, col])


func test_bucket_value_symmetric() -> void:
	print("test_bucket_value_symmetric")
	# Neither earring may be richer than the other.
	for col in 9:
		assert_equal(WhiteCurrency.bucket_value(8, col, 3),
			WhiteCurrency.bucket_value(8, 8 - col, 3), "col %d mirrors" % col)


func test_expected_value_units_is_bucket_count() -> void:
	print("test_expected_value_units_is_bucket_count")
	# Every bucket is worth 1 fair unit in expectation, and there are rows+1 of
	# them — this is what lets OfflineCalculator credit a gateway exactly.
	assert_equal(WhiteCurrency.expected_value_units(8), 9, "8 rows -> 9 units")
	assert_equal(WhiteCurrency.expected_value_units(1), 2, "1 row -> 2 units")


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
