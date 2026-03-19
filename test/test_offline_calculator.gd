extends SceneTree

## Minimal test runner — run with:
##   godot --headless -s test/test_offline_calculator.gd

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	print("\n=== OfflineCalculator Tests ===\n")

	test_zero_elapsed_no_change()
	test_no_autodroppers_no_change()
	test_gold_board_basic_earnings()
	test_cap_enforcement()
	test_multi_drop_from_prestige()
	test_orange_board_depletes_gold()
	test_cross_board_processing_order()
	test_insufficient_currency_limits_drops()
	test_advanced_drops_earn_advanced_currency()
	test_input_not_mutated()
	test_multiple_autodroppers_scale_throughput()
	test_normal_and_advanced_on_same_board()
	test_normal_drops_earn_advanced_currency()
	test_long_offline_capped_by_currency_cap()
	test_zero_balance_cannot_afford_drops()
	test_higher_bucket_value_multiplier()
	test_red_board_basic()
	test_missing_board_state_uses_defaults()
	test_all_three_boards_sequential_processing()
	test_gold_accumulates_then_orange_fires()

	print("\n--- Results: %d passed, %d failed ---" % [_pass_count, _fail_count])
	if _fail_count > 0:
		printerr("SOME TESTS FAILED")
	quit()


# --- Assertion helpers ---

func assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		_pass_count += 1
	else:
		_fail_count += 1
		printerr("  FAIL: %s — expected %s, got %s" % [label, expected, actual])


# --- Test state builder ---

## Default board_state for a basic board: 2 rows, drop_delay=2.0 (gold default),
## bucket_value_multiplier=1, distance_for_advanced=3, multi_drop=1.
func _default_board_state(board_type: String, overrides: Dictionary = {}) -> Dictionary:
	var base_delay := 2.0
	match board_type:
		"ORANGE": base_delay = 4.0
		"RED": base_delay = 8.0
	var bs := {
		"num_rows": 2,
		"drop_delay": base_delay,
		"bucket_value_multiplier": 1,
		"distance_for_advanced_buckets": 3,
		"multi_drop_count": 1,
	}
	for key in overrides:
		bs[key] = overrides[key]
	return bs


func _make_state(overrides: Dictionary = {}) -> Dictionary:
	var state := {
		"version": 3,
		"save_timestamp": 0.0,
		"currency": _make_currency_data(),
		"upgrades": {},
		"boards": {
			"board_types": [0],
			"assignments": {},
			"advanced_buckets": {"GOLD": false, "ORANGE": false, "RED": false},
			"autodroppers_unlocked": false,
			"board_state": {
				"GOLD": _default_board_state("GOLD"),
			},
		},
		"prestige": {},
		"level": {},
	}
	_deep_merge(state, overrides)
	return state


func _make_currency_data() -> Dictionary:
	return {
		"GOLD_COIN": {"balance": 100, "cap": 500, "cap_raise_level": 0},
		"RAW_ORANGE": {"balance": 0, "cap": 50, "cap_raise_level": 0},
		"ORANGE_COIN": {"balance": 0, "cap": 500, "cap_raise_level": 0},
		"RAW_RED": {"balance": 0, "cap": 50, "cap_raise_level": 0},
		"RED_COIN": {"balance": 0, "cap": 500, "cap_raise_level": 0},
	}


func _deep_merge(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		if key in target and target[key] is Dictionary and source[key] is Dictionary:
			_deep_merge(target[key], source[key])
		else:
			target[key] = source[key]


# --- Test Cases ---


func test_zero_elapsed_no_change() -> void:
	print("test_zero_elapsed_no_change")
	var state := _make_state({
		"boards": {"assignments": {"GOLD_NORMAL": 1}},
	})
	var result := OfflineCalculator.calculate(state, 0.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 100, "gold unchanged")


func test_no_autodroppers_no_change() -> void:
	print("test_no_autodroppers_no_change")
	var state := _make_state()
	var result := OfflineCalculator.calculate(state, 300.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 100, "gold unchanged")


func test_gold_board_basic_earnings() -> void:
	print("test_gold_board_basic_earnings")
	# 1 autodropper on GOLD_NORMAL, 2 rows, drop_delay=2.0, 60 seconds
	# drops = floor(1/2.0 * 60) = 30
	# 2 rows -> 3 buckets. Pascal: [0.25, 0.5, 0.25]
	# Bucket layout: [2 GOLD, 1 GOLD, 2 GOLD]
	# Per-bucket earnings: 0.25*2=0.5, 0.5*1=0.5, 0.25*2=0.5. Total per drop = 1.5 GOLD
	# Net cost = 1 - 1.5 = -0.5 (net positive, all affordable)
	# Total: cost 30, earn 45. Final = 100 - 30 + 45 = 115
	var state := _make_state({
		"boards": {"assignments": {"GOLD_NORMAL": 1}},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 115, "gold after earnings")


func test_cap_enforcement() -> void:
	print("test_cap_enforcement")
	# Start with 490 gold, cap 500. Same board as basic_earnings (2 rows, 3 buckets).
	# Per-bucket earnings: 0.25*2=0.5, 0.5*1=0.5, 0.25*2=0.5. Total per drop = 1.5 GOLD
	# 30 drops: cost 30, earn 45. Raw would be 490 - 30 + 45 = 505, but capped at 500.
	var state := _make_state({
		"currency": {"GOLD_COIN": {"balance": 490, "cap": 500, "cap_raise_level": 0}},
		"boards": {"assignments": {"GOLD_NORMAL": 1}},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 500, "gold capped")


func test_multi_drop_from_prestige() -> void:
	print("test_multi_drop_from_prestige")
	# multi_drop_count=2 (from prestige). Same board layout as basic_earnings.
	# Per-bucket earnings (x2 multi): 0.25*2*2=1.0, 0.5*1*2=1.0, 0.25*2*2=1.0. Total per drop = 3.0 GOLD
	# 30 drops: earn 90, cost 30. Final = 100 - 30 + 90 = 160
	var state := _make_state({
		"boards": {
			"assignments": {"GOLD_NORMAL": 1},
			"board_state": {
				"GOLD": _default_board_state("GOLD", {"multi_drop_count": 2}),
			},
		},
		"prestige": {"ORANGE": 1},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 160, "gold with prestige")


func test_orange_board_depletes_gold() -> void:
	print("test_orange_board_depletes_gold")
	# Orange: drop_delay=4.0, 1 autodropper, 60s -> 15 potential drops
	# 2 rows -> 3 buckets. Pascal: [0.25, 0.5, 0.25]
	# Bucket layout: [2 ORANGE, 1 ORANGE, 2 ORANGE]
	# Per-bucket earnings: 0.25*2=0.5, 0.5*1=0.5, 0.25*2=0.5. Total per drop = 1.5 ORANGE
	# Cost per drop: 1 RAW_ORANGE + 100 GOLD
	# Gold limits: floor(200/100) = 2, RAW_ORANGE limits: floor(20/1) = 20
	# Actual = min(15, 2, 20) = 2
	var state := _make_state({
		"currency": {
			"GOLD_COIN": {"balance": 200, "cap": 500, "cap_raise_level": 0},
			"RAW_ORANGE": {"balance": 20, "cap": 50, "cap_raise_level": 0},
		},
		"boards": {
			"board_types": [0, 1],
			"assignments": {"ORANGE_NORMAL": 1},
			"board_state": {
				"GOLD": _default_board_state("GOLD"),
				"ORANGE": _default_board_state("ORANGE"),
			},
		},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 0, "gold depleted")
	assert_equal(result["currency"]["ORANGE_COIN"]["balance"], 3, "orange earned")
	assert_equal(result["currency"]["RAW_ORANGE"]["balance"], 18, "raw_orange remaining")


func test_cross_board_processing_order() -> void:
	print("test_cross_board_processing_order")
	# Both boards interleaved in 10s batches. 2 rows, 3 buckets each.
	# Gold: 5 drops/batch, earn 1.5 GOLD/drop, cost 1 GOLD/drop
	# Orange: ~2.5 drops/batch, earn 1.5 ORANGE/drop, cost 1 RAW_ORANGE + 100 GOLD/drop
	#
	# Batch 1: Gold 5 drops (100→102). Orange 1 drop (102→2, RAW_ORANGE 20→19, ORANGE 0→1)
	# Batch 2: Gold limited to 2 drops (2→3). Orange can't afford (3 < 100).
	# Batches 3-6: Gold gradually recovers but never reaches 100 for another orange drop.
	# Final: GOLD=12, ORANGE=1, RAW_ORANGE=19
	var state := _make_state({
		"currency": {
			"GOLD_COIN": {"balance": 100, "cap": 500, "cap_raise_level": 0},
			"RAW_ORANGE": {"balance": 20, "cap": 50, "cap_raise_level": 0},
		},
		"boards": {
			"board_types": [0, 1],
			"assignments": {"GOLD_NORMAL": 1, "ORANGE_NORMAL": 1},
			"board_state": {
				"GOLD": _default_board_state("GOLD"),
				"ORANGE": _default_board_state("ORANGE"),
			},
		},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 12, "gold after both boards")
	assert_equal(result["currency"]["ORANGE_COIN"]["balance"], 1, "orange earned")
	assert_equal(result["currency"]["RAW_ORANGE"]["balance"], 19, "raw_orange remaining")


func test_insufficient_currency_limits_drops() -> void:
	print("test_insufficient_currency_limits_drops")
	# Orange board: 2 rows -> 3 buckets. Pascal: [0.25, 0.5, 0.25]
	# Bucket layout: [2 ORANGE, 1 ORANGE, 2 ORANGE]
	# Per-bucket earnings: 0.25*2=0.5, 0.5*1=0.5, 0.25*2=0.5. Total per drop = 1.5 ORANGE
	# Cost per drop: 1 RAW_ORANGE + 100 GOLD. Only 3 RAW_ORANGE limits to 3 drops
	var state := _make_state({
		"currency": {
			"GOLD_COIN": {"balance": 500, "cap": 500, "cap_raise_level": 0},
			"RAW_ORANGE": {"balance": 3, "cap": 50, "cap_raise_level": 0},
		},
		"boards": {
			"board_types": [0, 1],
			"assignments": {"ORANGE_NORMAL": 1},
			"board_state": {
				"GOLD": _default_board_state("GOLD"),
				"ORANGE": _default_board_state("ORANGE"),
			},
		},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["RAW_ORANGE"]["balance"], 0, "raw_orange exhausted")
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 200, "gold after 3 drops")
	assert_equal(result["currency"]["ORANGE_COIN"]["balance"], 4, "orange earned")


func test_advanced_drops_earn_advanced_currency() -> void:
	print("test_advanced_drops_earn_advanced_currency")
	# GOLD_ADVANCED, 8 rows, advanced buckets visible, coin multiplier = 3
	# 9 buckets, distances [4,3,2,1,0,1,2,3,4], advanced_distance=3
	# Bucket layout: [2 RAW_O, 1 RAW_O, 3 GOLD, 2 GOLD, 1 GOLD, 2 GOLD, 3 GOLD, 1 RAW_O, 2 RAW_O]
	# Pascal row 8: [1, 8, 28, 56, 70, 56, 28, 8, 1] / 256
	#
	# Per-bucket RAW_ORANGE earnings (x3 coin mult):
	#   b0: (1/256)*2*3=0.0234, b1: (8/256)*1*3=0.0938
	#   b7: (8/256)*1*3=0.0938, b8: (1/256)*2*3=0.0234
	#   Total RAW_ORANGE per drop = 0.234375
	#
	# Per-bucket GOLD_COIN earnings (x3 coin mult):
	#   b2: (28/256)*3*3=0.984, b3: (56/256)*2*3=1.3125, b4: (70/256)*1*3=0.8203
	#   b5: (56/256)*2*3=1.3125, b6: (28/256)*3*3=0.984
	#   Total GOLD_COIN per drop = 5.4141
	#
	# Cost: 1 RAW_ORANGE per drop (gross). drop_delay=2.0, 1 autodropper, 60s
	# Batched (10s each, 5 drops/batch): each batch spends up to 5 RAW_ORANGE,
	# earns some back. Over 6 batches: 5+5+5+5+4+1 = 25 total drops.
	# RAW_ORANGE: 20 spent, 6 earned back partially across batches → 0
	# GOLD: 100 + earnings from 25 advanced drops = 235
	var state := _make_state({
		"currency": {
			"RAW_ORANGE": {"balance": 20, "cap": 50, "cap_raise_level": 0},
		},
		"boards": {
			"assignments": {"GOLD_ADVANCED": 1},
			"advanced_buckets": {"GOLD": true, "ORANGE": false, "RED": false},
			"board_state": {
				"GOLD": _default_board_state("GOLD", {"num_rows": 8}),
			},
		},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["RAW_ORANGE"]["balance"], 0, "raw_orange spent")
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 235, "gold earned from advanced")


func test_input_not_mutated() -> void:
	print("test_input_not_mutated")
	var state := _make_state({
		"boards": {"assignments": {"GOLD_NORMAL": 1}},
	})
	var original_gold: int = state["currency"]["GOLD_COIN"]["balance"]
	var _result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(state["currency"]["GOLD_COIN"]["balance"], original_gold, "original state unchanged")


func test_multiple_autodroppers_scale_throughput() -> void:
	print("test_multiple_autodroppers_scale_throughput")
	# 3 autodroppers on GOLD_NORMAL, 2 rows, drop_delay=2.0, 60s
	# drops = floor(3/2.0 * 60) = 90
	# 3 buckets: [2 GOLD, 1 GOLD, 2 GOLD]. Per-drop = 1.5 GOLD
	# Cost 1 GOLD per drop (net positive, all affordable)
	# Total: cost 90, earn int(90*1.5)=135. Final = 100 - 90 + 135 = 145
	var state := _make_state({
		"boards": {"assignments": {"GOLD_NORMAL": 3}},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 145, "gold with 3 autodroppers")


func test_normal_and_advanced_on_same_board() -> void:
	print("test_normal_and_advanced_on_same_board")
	# Gold board, 8 rows, advanced buckets visible
	# 9 buckets, distances [4,3,2,1,0,1,2,3,4], advanced_distance=3
	# Layout: [2 RAW_O, 1 RAW_O, 3 GOLD, 2 GOLD, 1 GOLD, 2 GOLD, 3 GOLD, 1 RAW_O, 2 RAW_O]
	# Pascal row 8: [1, 8, 28, 56, 70, 56, 28, 8, 1] / 256
	#
	# NORMAL processed first (coin_mult=1):
	#   30 drops, cost 1 GOLD each
	#   GOLD per drop: (28*3+56*2+70*1+56*2+28*3)/256 = 462/256 = 1.8047
	#   RAW_ORANGE per drop: (1*2+8*1+8*1+1*2)/256 = 20/256 = 0.078125
	#   Net GOLD cost = 1 - 1.8047 < 0 → all affordable, actual=30
	#   GOLD: 100 - 30 + int(30*1.8047) = 100 - 30 + 54 = 124
	#   RAW_ORANGE: 0 + int(30*0.078125) = 2
	#
	# ADVANCED processed second (coin_mult=3):
	#   30 potential drops, cost 1 RAW_ORANGE each
	#   RAW_ORANGE per drop: 0.234375, net cost = 1 - 0.234375 = 0.765625
	#   max_affordable = floor(2/0.765625) = 2
	#   actual = min(30, 2) = 2
	#   RAW_ORANGE: 2 - 2 + int(2*0.234375) = 0
	#   GOLD: 124 + int(2*5.4141) = 124 + 10 = 134
	var state := _make_state({
		"currency": {
			"RAW_ORANGE": {"balance": 0, "cap": 50, "cap_raise_level": 0},
		},
		"boards": {
			"assignments": {"GOLD_NORMAL": 1, "GOLD_ADVANCED": 1},
			"advanced_buckets": {"GOLD": true, "ORANGE": false, "RED": false},
			"board_state": {
				"GOLD": _default_board_state("GOLD", {"num_rows": 8}),
			},
		},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 134, "gold from both normal+advanced")
	assert_equal(result["currency"]["RAW_ORANGE"]["balance"], 0, "raw_orange spent by advanced")


func test_normal_drops_earn_advanced_currency() -> void:
	print("test_normal_drops_earn_advanced_currency")
	# GOLD_NORMAL on gold board with 8 rows and advanced buckets visible
	# Same bucket layout as test_normal_and_advanced_on_same_board
	# coin_multiplier=1 (normal), so RAW_ORANGE earned at 1x not 3x
	# 30 drops, cost 1 GOLD each
	# GOLD per drop: 462/256 = 1.8047 (net positive, all affordable)
	# RAW_ORANGE per drop: 20/256 = 0.078125
	# GOLD: 100 - 30 + int(30*1.8047) = 124
	# RAW_ORANGE: 0 + int(30*0.078125) = int(2.34375) = 2
	var state := _make_state({
		"boards": {
			"assignments": {"GOLD_NORMAL": 1},
			"advanced_buckets": {"GOLD": true, "ORANGE": false, "RED": false},
			"board_state": {
				"GOLD": _default_board_state("GOLD", {"num_rows": 8}),
			},
		},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 124, "gold from normal on advanced board")
	assert_equal(result["currency"]["RAW_ORANGE"]["balance"], 2, "raw_orange earned at 1x multiplier")


func test_long_offline_capped_by_currency_cap() -> void:
	print("test_long_offline_capped_by_currency_cap")
	# 24 hours (86400s), 1 gold autodropper, 2 rows
	# Batched processing: gold quickly reaches cap (500) and stays there.
	# Each batch: cost 5, earn 7-8, cap prevents growth above 500.
	var state := _make_state({
		"boards": {"assignments": {"GOLD_NORMAL": 1}},
	})
	var result := OfflineCalculator.calculate(state, 86400.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 500, "gold capped after 24h")


func test_zero_balance_cannot_afford_drops() -> void:
	print("test_zero_balance_cannot_afford_drops")
	# Start with 0 gold, 1 autodropper, 2 rows
	# Each drop costs 1 GOLD (gross). With 0 balance, can't afford any drops.
	# Even though the board is net-positive (earn 1.5, cost 1), you need
	# initial capital to start the cycle.
	var state := _make_state({
		"currency": {"GOLD_COIN": {"balance": 0, "cap": 500, "cap_raise_level": 0}},
		"boards": {"assignments": {"GOLD_NORMAL": 1}},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 0, "no drops without initial capital")


func test_higher_bucket_value_multiplier() -> void:
	print("test_higher_bucket_value_multiplier")
	# Gold board, 2 rows, bucket_value_multiplier=3
	# 3 buckets, distances [1, 0, 1]
	# Values: [1+1*3=4, 1+0*3=1, 1+1*3=4]
	# Per-drop: 0.25*4 + 0.5*1 + 0.25*4 = 2.5 GOLD
	# 30 drops: cost 30, earn int(30*2.5)=75. Final = 100 - 30 + 75 = 145
	var state := _make_state({
		"boards": {
			"assignments": {"GOLD_NORMAL": 1},
			"board_state": {
				"GOLD": _default_board_state("GOLD", {"bucket_value_multiplier": 3}),
			},
		},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 145, "gold with higher bucket multiplier")


func test_red_board_basic() -> void:
	print("test_red_board_basic")
	# 1 RED_NORMAL autodropper, 2 rows, drop_delay=8.0, 60s
	# drops = floor(1/8.0 * 60) = 7
	# 3 buckets: [2 RED, 1 RED, 2 RED]. Per-drop = 1.5 RED_COIN
	# Cost: 1 RAW_RED + 100 ORANGE per drop
	# RAW_RED limits: floor(10/1) = 10
	# ORANGE limits: floor(500/100) = 5
	# actual = min(7, 10, 5) = 5
	# RAW_RED: 10 - 5 = 5, ORANGE: 500 - 500 = 0
	# RED_COIN: 0 + int(5 * 1.5) = 7
	var state := _make_state({
		"currency": {
			"RAW_RED": {"balance": 10, "cap": 50, "cap_raise_level": 0},
			"ORANGE_COIN": {"balance": 500, "cap": 500, "cap_raise_level": 0},
		},
		"boards": {
			"board_types": [0, 1, 2],
			"assignments": {"RED_NORMAL": 1},
			"board_state": {
				"GOLD": _default_board_state("GOLD"),
				"ORANGE": _default_board_state("ORANGE"),
				"RED": _default_board_state("RED"),
			},
		},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["RAW_RED"]["balance"], 5, "raw_red remaining")
	assert_equal(result["currency"]["ORANGE_COIN"]["balance"], 0, "orange depleted")
	assert_equal(result["currency"]["RED_COIN"]["balance"], 7, "red earned")


func test_missing_board_state_uses_defaults() -> void:
	print("test_missing_board_state_uses_defaults")
	# Board exists in board_types but no entry in board_state
	# Default drop_delay=0.0 → skipped, no earnings, no crash
	var state := _make_state({
		"boards": {
			"board_types": [0, 1],
			"assignments": {"ORANGE_NORMAL": 1},
			"board_state": {
				"GOLD": _default_board_state("GOLD"),
				# No "ORANGE" entry — should use defaults
			},
		},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 100, "gold unchanged")
	assert_equal(result["currency"]["ORANGE_COIN"]["balance"], 0, "orange unchanged")


func test_all_three_boards_sequential_processing() -> void:
	print("test_all_three_boards_sequential_processing")
	# Tests sequential GOLD → ORANGE → RED processing order.
	# Start: 480 GOLD (cap 500), 20 RAW_ORANGE (cap 50), 10 RAW_RED (cap 50),
	#         200 ORANGE (cap 500), 0 RED (cap 500)
	#
	# Gold board: GOLD_NORMAL, 2 rows, 30 drops
	#   Cost 30, earn int(30*1.5)=45. GOLD: 480 - 30 + 45 = 495
	#
	# Orange board: ORANGE_NORMAL, 2 rows, drop_delay=4.0, 15 potential drops
	#   Cost: 1 RAW_ORANGE + 100 GOLD per drop. Earns 1.5 ORANGE per drop.
	#   GOLD limits: floor(495/100) = 4, RAW_ORANGE limits: floor(20/1) = 20
	#   actual = min(15, 4, 20) = 4
	#   GOLD: 495 - 400 = 95, RAW_ORANGE: 20 - 4 = 16
	#   ORANGE: 200 + int(4*1.5) = 206
	#
	# Red board: RED_NORMAL, 2 rows, drop_delay=8.0, 7 potential drops
	#   Cost: 1 RAW_RED + 100 ORANGE per drop. Earns 1.5 RED per drop.
	#   RAW_RED limits: floor(10/1) = 10, ORANGE limits: floor(206/100) = 2
	#   actual = min(7, 10, 2) = 2
	#   RAW_RED: 10 - 2 = 8, ORANGE: 206 - 200 = 6
	#   RED: 0 + int(2*1.5) = 3
	var state := _make_state({
		"currency": {
			"GOLD_COIN": {"balance": 480, "cap": 500, "cap_raise_level": 0},
			"RAW_ORANGE": {"balance": 20, "cap": 50, "cap_raise_level": 0},
			"ORANGE_COIN": {"balance": 200, "cap": 500, "cap_raise_level": 0},
			"RAW_RED": {"balance": 10, "cap": 50, "cap_raise_level": 0},
			"RED_COIN": {"balance": 0, "cap": 500, "cap_raise_level": 0},
		},
		"boards": {
			"board_types": [0, 1, 2],
			"assignments": {"GOLD_NORMAL": 1, "ORANGE_NORMAL": 1, "RED_NORMAL": 1},
			"board_state": {
				"GOLD": _default_board_state("GOLD"),
				"ORANGE": _default_board_state("ORANGE"),
				"RED": _default_board_state("RED"),
			},
		},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 95, "gold after all boards")
	assert_equal(result["currency"]["RAW_ORANGE"]["balance"], 16, "raw_orange remaining")
	assert_equal(result["currency"]["ORANGE_COIN"]["balance"], 6, "orange after red spent it")
	assert_equal(result["currency"]["RAW_RED"]["balance"], 8, "raw_red remaining")
	assert_equal(result["currency"]["RED_COIN"]["balance"], 3, "red earned")


func test_gold_accumulates_then_orange_fires() -> void:
	print("test_gold_accumulates_then_orange_fires")
	# Gold board: bucket_value_multiplier=3, earn 2.5 GOLD/drop, cost 1.
	#   5 drops/batch → cost 5, earn 12-13 (alternating). Net ~+7.5/batch.
	# Orange: drop_delay=80 → rate=0.125/s → 1 drop after 8 batches (80s).
	#   (10/80 = 0.125 = 1/8, exact in binary — no float accumulation error)
	# Gold over 8 batches: 60 → 120. Orange fires: 120 - 100 = 20.
	var state := _make_state({
		"currency": {
			"GOLD_COIN": {"balance": 60, "cap": 500, "cap_raise_level": 0},
			"RAW_ORANGE": {"balance": 10, "cap": 50, "cap_raise_level": 0},
		},
		"boards": {
			"board_types": [0, 1],
			"assignments": {"GOLD_NORMAL": 1, "ORANGE_NORMAL": 1},
			"board_state": {
				"GOLD": _default_board_state("GOLD", {"bucket_value_multiplier": 3}),
				"ORANGE": _default_board_state("ORANGE", {"drop_delay": 80.0}),
			},
		},
	})
	var result := OfflineCalculator.calculate(state, 80.0)
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 20, "gold after orange spent 100")
	assert_equal(result["currency"]["RAW_ORANGE"]["balance"], 9, "one raw_orange spent")
