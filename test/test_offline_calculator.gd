extends "res://test/test_base.gd"

## OfflineCalculator tests — run with:
##   godot --headless --scene res://test/test_offline_calculator.tscn


func _run_tests() -> void:
	print("\n=== OfflineCalculator Tests ===\n")

	test_zero_elapsed_no_change()
	test_no_autodroppers_no_change()
	test_gold_board_basic_earnings()
	test_cap_enforcement()
	test_multi_drop_from_prestige()
	test_orange_board_depletes_gold()
	test_cross_board_processing_order()
	test_insufficient_currency_limits_drops()
	test_advanced_assignment_earns_like_normal()
	test_input_not_mutated()
	test_multiple_autodroppers_scale_throughput()
	test_normal_and_advanced_on_same_board()
	test_earring_gateways_credit_white()
	test_white_credited_without_any_prestige()
	test_long_offline_capped_by_currency_cap()
	test_zero_balance_cannot_afford_drops()
	test_higher_bucket_value_multiplier()
	test_red_board_basic()
	test_missing_board_state_uses_defaults()
	test_all_three_boards_interleaved()
	test_gold_accumulates_then_orange_fires()
	test_no_orange_credited_before_orange_prestige()
	test_orange_credited_after_orange_prestige()
	test_gold_always_credited_even_without_prestige()
	test_no_red_credited_before_red_prestige()


# --- Test state builder ---

## Default board_state for a basic board: 2 rows, drop_delay=2.0 (gold default),
## bucket_value_multiplier=1, multi_drop=1.
func _default_board_state(board_type: String, overrides: Dictionary = {}) -> Dictionary:
	var base_delay := 2.0
	match board_type:
		"ORANGE": base_delay = 4.0
		"RED": base_delay = 8.0
	var bs := {
		"num_rows": 2,
		"drop_delay": base_delay,
		"bucket_value_multiplier": 1,
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
			"autodroppers_unlocked": false,
			"board_state": {
				"GOLD": _default_board_state("GOLD"),
			},
		},
		"prestige": {},
		"level": {},
	}
	_deep_merge(state, overrides)
	# Auto-seed prestige from board_types — in production a board only ever
	# exists in board_types after the player has prestiged into it. Tests that
	# specifically exercise the unprestiged state should override "prestige".
	if state["prestige"].is_empty():
		var board_types_for_seed: Array = state["boards"].get("board_types", [])
		for board_type_int in board_types_for_seed:
			if int(board_type_int) == Enums.BoardType.GOLD:
				continue
			var key: String = Enums.BoardType.keys()[int(board_type_int)]
			state["prestige"][key] = 1
	# OfflineCalculator runs against JSON-parsed save data where every number
	# is a float. Coerce board_types to floats so its `float(idx) in board_types`
	# check matches — int literals in tests would otherwise mis-compare.
	var coerced: Array = []
	for v in state["boards"]["board_types"]:
		coerced.append(float(v))
	state["boards"]["board_types"] = coerced
	return state


func _make_currency_data() -> Dictionary:
	return {
		"GOLD_COIN": {"balance": 100, "cap": 500, "cap_raise_level": 0},
		"ORANGE_COIN": {"balance": 0, "cap": 500, "cap_raise_level": 0},
		"RED_COIN": {"balance": 0, "cap": 500, "cap_raise_level": 0},
		"WHITE_COIN": {"balance": 0, "cap": 500, "cap_raise_level": 0},
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
	# Cost per drop is 100 GOLD.
	# Gold limits: floor(200/100) = 2. Actual = min(15, 2) = 2.
	var state := _make_state({
		"currency": {
			"GOLD_COIN": {"balance": 200, "cap": 500, "cap_raise_level": 0},
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


func test_cross_board_processing_order() -> void:
	print("test_cross_board_processing_order")
	# Both boards interleaved in 10s batches. 2 rows, 3 buckets each.
	# Gold: 5 drops/batch, earn 1.5 GOLD/drop, cost 1 GOLD/drop
	# Orange: ~2.5 drops/batch, earn 1.5 ORANGE/drop, cost 100 GOLD/drop (single-currency)
	#
	# GOLD is the binding limit on orange drops.
	# Batch 1: Gold 5 drops (100→102). Orange 1 drop (102→2, ORANGE 0→1)
	# Batch 2: Gold limited to 2 drops (2→3). Orange can't afford (3 < 100).
	# Batches 3-6: Gold gradually recovers but never reaches 100 for another orange drop.
	# Final: GOLD=12, ORANGE=1
	var state := _make_state({
		"currency": {
			"GOLD_COIN": {"balance": 100, "cap": 500, "cap_raise_level": 0},
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


func test_insufficient_currency_limits_drops() -> void:
	print("test_insufficient_currency_limits_drops")
	# Orange board: 2 rows -> 3 buckets. Pascal: [0.25, 0.5, 0.25]
	# Bucket layout: [2 ORANGE, 1 ORANGE, 2 ORANGE]
	# Per-bucket earnings: 0.25*2=0.5, 0.5*1=0.5, 0.25*2=0.5. Total per drop = 1.5 ORANGE
	# The only fuel is GOLD (100/drop). GOLD=300 limits the
	# board to 3 drops total even though 15 are otherwise available in 60s.
	# 3 drops: GOLD 300→0, ORANGE 3*1.5 = 4.5 → 4.
	var state := _make_state({
		"currency": {
			"GOLD_COIN": {"balance": 300, "cap": 500, "cap_raise_level": 0},
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
	assert_equal(result["currency"]["GOLD_COIN"]["balance"], 0, "gold exhausted after 3 drops")
	assert_equal(result["currency"]["ORANGE_COIN"]["balance"], 4, "orange earned")


## An ADVANCED assignment is still read from old saves so its autodroppers aren't
## silently dropped from the pool, but it now earns and costs exactly what a NORMAL
## one does — the advanced currency and its x2 coin multiplier are both gone.
func test_advanced_assignment_earns_like_normal() -> void:
	print("test_advanced_assignment_earns_like_normal")
	var advanced := _make_state({
		"boards": {
			"assignments": {"GOLD_ADVANCED": 1},
			"board_state": {"GOLD": _default_board_state("GOLD", {"num_rows": 8})},
		},
	})
	var normal := _make_state({
		"boards": {
			"assignments": {"GOLD_NORMAL": 1},
			"board_state": {"GOLD": _default_board_state("GOLD", {"num_rows": 8})},
		},
	})
	var adv_result := OfflineCalculator.calculate(advanced, 60.0)
	var norm_result := OfflineCalculator.calculate(normal, 60.0)
	assert_equal(adv_result["currency"]["GOLD_COIN"]["balance"],
		norm_result["currency"]["GOLD_COIN"]["balance"],
		"an advanced autodropper earns the same as a normal one")


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


## Two assignments on one board stack as plain throughput now that they are
## identical — strictly more than either alone.
func test_normal_and_advanced_on_same_board() -> void:
	print("test_normal_and_advanced_on_same_board")
	var both := _make_state({
		"boards": {
			"assignments": {"GOLD_NORMAL": 1, "GOLD_ADVANCED": 1},
			"board_state": {"GOLD": _default_board_state("GOLD", {"num_rows": 8})},
		},
	})
	var one := _make_state({
		"boards": {
			"assignments": {"GOLD_NORMAL": 1},
			"board_state": {"GOLD": _default_board_state("GOLD", {"num_rows": 8})},
		},
	})
	var both_result := OfflineCalculator.calculate(both, 60.0)
	var one_result := OfflineCalculator.calculate(one, 60.0)
	assert_true(both_result["currency"]["GOLD_COIN"]["balance"]
			> one_result["currency"]["GOLD_COIN"]["balance"],
		"two assignments out-earn one")


## A board with earrings credits WHITE from its two gateways, and nothing else on
## the board changes. White is the only currency a gateway can pay.
func test_earring_gateways_credit_white() -> void:
	print("test_earring_gateways_credit_white")
	var earring_rows: int = EarringGeometry.max_earring_rows()
	var state := _make_state({
		"boards": {
			"assignments": {"GOLD_NORMAL": 1},
			"board_state": {"GOLD": _default_board_state("GOLD", {
				"num_rows": EarringGeometry.MAIN_MAX_ROWS,
				"earring_rows": earring_rows,
			})},
		},
	})
	var result := OfflineCalculator.calculate(state, 600.0)
	assert_true(result["currency"]["WHITE_COIN"]["balance"] > 0,
		"a board with earrings accrues white offline")

	# Without earrings the same board must accrue none.
	var no_earrings := _make_state({
		"boards": {
			"assignments": {"GOLD_NORMAL": 1},
			"board_state": {"GOLD": _default_board_state("GOLD", {
				"num_rows": EarringGeometry.MAIN_MAX_ROWS,
			})},
		},
	})
	var bare := OfflineCalculator.calculate(no_earrings, 600.0)
	assert_equal(bare["currency"]["WHITE_COIN"]["balance"], 0,
		"a board with no earrings accrues no white")


## White has no tier, so the prestige gate that suppresses never-earned
## currencies must not apply to it — reaching an earring is a far deeper gate.
func test_white_credited_without_any_prestige() -> void:
	print("test_white_credited_without_any_prestige")
	var state := _make_state({
		"boards": {
			"assignments": {"GOLD_NORMAL": 1},
			"board_state": {"GOLD": _default_board_state("GOLD", {
				"num_rows": EarringGeometry.MAIN_MAX_ROWS,
				"earring_rows": EarringGeometry.max_earring_rows(),
			})},
		},
		"prestige": {},
	})
	var result := OfflineCalculator.calculate(state, 600.0)
	assert_true(result["currency"]["WHITE_COIN"]["balance"] > 0,
		"white accrues with no prestige recorded")


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
	# RED costs 100 ORANGE_COIN per drop (the previous tier's PRIMARY currency).
	# ORANGE_COIN seeded high so affordability isn't the limit.
	# 7 drops: ORANGE_COIN 1000 - 700 = 300.
	# RED_COIN per drop = 0.25*2 + 0.5*1 + 0.25*2 = 1.5; floor(7 * 1.5) = 10
	var state := _make_state({
		"currency": {
			"ORANGE_COIN": {"balance": 1000, "cap": 1000, "cap_raise_level": 0},
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
	assert_equal(result["currency"]["ORANGE_COIN"]["balance"], 300, "orange spent fueling red drops")
	assert_equal(result["currency"]["RED_COIN"]["balance"], 10, "red earned")


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


func test_all_three_boards_interleaved() -> void:
	print("test_all_three_boards_interleaved")
	# All three boards have an autodropper. Single-currency model: each later board
	# is fueled purely by the previous tier's PRIMARY currency — ORANGE costs 100
	# GOLD per drop, RED costs 100 ORANGE_COIN per drop. Currencies seeded
	# generously so affordability isn't the constraint — drop-rate is.
	var state := _make_state({
		"currency": {
			"GOLD_COIN": {"balance": 5000, "cap": 10000, "cap_raise_level": 0},
			"ORANGE_COIN": {"balance": 5000, "cap": 10000, "cap_raise_level": 0},
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
	assert_true(result["currency"]["GOLD_COIN"]["balance"] > 0, "gold accrues / persists")
	assert_true(result["currency"]["ORANGE_COIN"]["balance"] > 0, "orange accrues / persists")
	assert_true(result["currency"]["RED_COIN"]["balance"] > 0, "red earned")
	# Primary fuel currencies got spent by the higher-tier boards they fuel.
	assert_true(result["currency"]["GOLD_COIN"]["balance"] < 5000, "gold spent by orange drops")


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


## An orange board running offline without an orange prestige recorded must not
## credit ORANGE_COIN — the player has never organically earned it, and the gate
## exists to preserve that first-time prestige beat.
##
## `prestige` is seeded with an unrelated key rather than left empty: _make_state
## auto-seeds prestige from board_types when the dict is empty, which would grant
## the very ORANGE key this test needs absent.
func test_no_orange_credited_before_orange_prestige() -> void:
	print("test_no_orange_credited_before_orange_prestige")
	var state := _make_state({
		"boards": {
			"board_types": [0, 1],
			"assignments": {"ORANGE_NORMAL": 1},
			"board_state": {
				"GOLD": _default_board_state("GOLD"),
				"ORANGE": _default_board_state("ORANGE", {"num_rows": 8}),
			},
		},
		"prestige": {"GOLD": 0},
	})
	var result := OfflineCalculator.calculate(state, 600.0)
	assert_equal(result["currency"]["ORANGE_COIN"]["balance"], 0, "no orange before prestige")


func test_orange_credited_after_orange_prestige() -> void:
	print("test_orange_credited_after_orange_prestige")
	# Same setup with the orange prestige claimed — earnings should now flow.
	var state := _make_state({
		"boards": {
			"board_types": [0, 1],
			"assignments": {"ORANGE_NORMAL": 1},
			"board_state": {
				"GOLD": _default_board_state("GOLD"),
				"ORANGE": _default_board_state("ORANGE", {"num_rows": 8}),
			},
		},
		"prestige": {"ORANGE": 1},
	})
	var result := OfflineCalculator.calculate(state, 600.0)
	assert_true(result["currency"]["ORANGE_COIN"]["balance"] > 0, "orange earned post-prestige")


func test_gold_always_credited_even_without_prestige() -> void:
	print("test_gold_always_credited_even_without_prestige")
	# Starting tier (gold) is always considered earned — no prestige key required.
	var state := _make_state({
		"boards": {"assignments": {"GOLD_NORMAL": 1}},
		"prestige": {},
	})
	var result := OfflineCalculator.calculate(state, 60.0)
	assert_true(result["currency"]["GOLD_COIN"]["balance"] > 100, "gold accrues without prestige")


## The gate is per-currency, not global: a player who has prestiged orange but
## never red still accrues orange while red stays blocked.
func test_no_red_credited_before_red_prestige() -> void:
	print("test_no_red_credited_before_red_prestige")
	var state := _make_state({
		"currency": {
			"GOLD_COIN": {"balance": 500, "cap": 500, "cap_raise_level": 0},
			"ORANGE_COIN": {"balance": 500, "cap": 500, "cap_raise_level": 0},
		},
		"boards": {
			"board_types": [0, 1, 2],
			"assignments": {"ORANGE_NORMAL": 1, "RED_NORMAL": 1},
			"board_state": {
				"GOLD": _default_board_state("GOLD"),
				"ORANGE": _default_board_state("ORANGE", {"num_rows": 8}),
				"RED": _default_board_state("RED", {"num_rows": 8}),
			},
		},
		"prestige": {"ORANGE": 1},
	})
	var result := OfflineCalculator.calculate(state, 600.0)
	assert_equal(result["currency"]["RED_COIN"]["balance"], 0, "no red before red prestige")
	assert_true(result["currency"]["ORANGE_COIN"]["balance"] > 0,
		"orange still accrues — the gate is per-currency")
