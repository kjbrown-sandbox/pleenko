extends "res://test/test_base.gd"

## TierRegistry.get_drop_costs() tests — run with:
##   godot --headless --scene res://test/test_tier_registry_drop_costs.tscn
##
## Single-currency redesign: every later board is fueled purely by the previous
## tier's PRIMARY currency. There is no raw-currency component in drop costs
## anymore. The starting tier (gold) costs 1 of its own primary currency.
##   gold   → [[GOLD_COIN, 1]]
##   orange → [[GOLD_COIN, 100]]      (previous tier's primary, previous_currency_cost)
##   red    → [[ORANGE_COIN, 100]]


func _run_tests() -> void:
	print("\n=== TierRegistry.get_drop_costs Tests ===\n")

	test_gold_costs_one_of_its_own_primary()
	test_orange_costs_previous_primary_only()
	test_red_costs_previous_primary_only()
	test_no_raw_currency_component()
	test_returns_fresh_array_safe_to_mutate()


func test_gold_costs_one_of_its_own_primary() -> void:
	print("test_gold_costs_one_of_its_own_primary")
	var costs: Array = TierRegistry.get_drop_costs(Enums.BoardType.GOLD)
	assert_equal(costs.size(), 1, "gold cost is a single component")
	assert_equal(costs[0][0], Enums.CurrencyType.GOLD_COIN, "gold pays in gold")
	assert_equal(costs[0][1], 1, "gold drop costs 1")


func test_orange_costs_previous_primary_only() -> void:
	print("test_orange_costs_previous_primary_only")
	var costs: Array = TierRegistry.get_drop_costs(Enums.BoardType.ORANGE)
	assert_equal(costs.size(), 1, "orange cost is a single component")
	assert_equal(costs[0][0], Enums.CurrencyType.GOLD_COIN, "orange is fueled by gold (previous primary)")
	assert_equal(costs[0][1], 100, "orange drop costs 100 gold")


func test_red_costs_previous_primary_only() -> void:
	print("test_red_costs_previous_primary_only")
	var costs: Array = TierRegistry.get_drop_costs(Enums.BoardType.RED)
	assert_equal(costs.size(), 1, "red cost is a single component")
	assert_equal(costs[0][0], Enums.CurrencyType.ORANGE_COIN, "red is fueled by orange (previous primary)")
	assert_equal(costs[0][1], 100, "red drop costs 100 orange")


## Regression guard: no later board may include a raw currency in its drop cost.
func test_no_raw_currency_component() -> void:
	print("test_no_raw_currency_component")
	for i in range(1, TierRegistry.get_tier_count()):
		var tier := TierRegistry.get_tier_by_index(i)
		var costs: Array = TierRegistry.get_drop_costs(tier.board_type)
		for cost in costs:
			assert_false(TierRegistry.is_raw_currency(cost[0]),
				"board %d cost component must not be a raw currency" % tier.board_type)


## get_drop_costs must return a fresh array each call — PlinkoBoard._get_drop_costs
## mutates it to apply DROP_COST_REDUCTION, so a shared/cached array would corrupt.
func test_returns_fresh_array_safe_to_mutate() -> void:
	print("test_returns_fresh_array_safe_to_mutate")
	var a: Array = TierRegistry.get_drop_costs(Enums.BoardType.ORANGE)
	a[0][1] = 999
	var b: Array = TierRegistry.get_drop_costs(Enums.BoardType.ORANGE)
	assert_equal(b[0][1], 100, "a second call is unaffected by mutating the first")
