extends "res://test/test_base.gd"

## TierRegistry.get_drop_costs() tests — run with:
##   godot --headless --scene res://test/test_tier_registry_drop_costs.tscn
##
## Every later board is fueled by the previous tier's PRIMARY currency. The
## starting tier (gold) costs 1 of its own primary currency. From violet on, a
## WHITE component is appended — the only multi-component cost in the game.
##   gold   → [[GOLD_COIN, 1]]
##   orange → [[GOLD_COIN, 100]]      (previous tier's primary, previous_currency_cost)
##   red    → [[ORANGE_COIN, 100]]
##   violet → [[RED_COIN, 100], [WHITE_COIN, 1]]
##   blue   → [[VIOLET_COIN, 100], [WHITE_COIN, 100]]
##   green  → [[BLUE_COIN, 100], [WHITE_COIN, 1000]]


func _run_tests() -> void:
	print("\n=== TierRegistry.get_drop_costs Tests ===\n")

	test_gold_costs_one_of_its_own_primary()
	test_orange_costs_previous_primary_only()
	test_red_costs_previous_primary_only()
	test_early_boards_have_no_white_component()
	test_violet_appends_white()
	test_blue_and_green_append_scaled_white()
	test_white_is_additive_not_replacing()
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


## The early and mid game must be untouched by white, or a player meets the
## currency before earrings can possibly exist.
func test_early_boards_have_no_white_component() -> void:
	print("test_early_boards_have_no_white_component")
	for board in [Enums.BoardType.GOLD, Enums.BoardType.ORANGE, Enums.BoardType.RED]:
		var costs: Array = TierRegistry.get_drop_costs(board)
		for cost in costs:
			assert_false(cost[0] == Enums.CurrencyType.WHITE_COIN,
				"board %d must not cost white" % board)


func test_violet_appends_white() -> void:
	print("test_violet_appends_white")
	var costs: Array = TierRegistry.get_drop_costs(Enums.BoardType.VIOLET)
	assert_equal(costs.size(), 2, "violet cost has two components")
	assert_equal(costs[0][0], Enums.CurrencyType.RED_COIN, "violet is fueled by red")
	assert_equal(costs[1][0], Enums.CurrencyType.WHITE_COIN, "and by white")
	assert_equal(costs[1][1], 1, "violet costs 1 white")


func test_blue_and_green_append_scaled_white() -> void:
	print("test_blue_and_green_append_scaled_white")
	var blue: Array = TierRegistry.get_drop_costs(Enums.BoardType.BLUE)
	assert_equal(blue.size(), 2, "blue cost has two components")
	assert_equal(blue[1][0], Enums.CurrencyType.WHITE_COIN, "blue costs white")
	assert_equal(blue[1][1], 100, "blue costs 100 white")

	var green: Array = TierRegistry.get_drop_costs(Enums.BoardType.GREEN)
	assert_equal(green.size(), 2, "green cost has two components")
	assert_equal(green[1][0], Enums.CurrencyType.WHITE_COIN, "green costs white")
	assert_equal(green[1][1], 1000, "green costs 1000 white")


## White is ADDITIVE: it must never displace the previous tier's primary
## currency, or the existing tier economy stops mattering on the late boards.
func test_white_is_additive_not_replacing() -> void:
	print("test_white_is_additive_not_replacing")
	for board in [Enums.BoardType.VIOLET, Enums.BoardType.BLUE, Enums.BoardType.GREEN]:
		var costs: Array = TierRegistry.get_drop_costs(board)
		var prev := TierRegistry.get_previous_tier(board)
		assert_equal(costs[0][0], prev.primary_currency,
			"board %d still costs the previous tier's primary" % board)
		assert_equal(costs[0][1], TierRegistry.get_tier(board).previous_currency_cost,
			"board %d primary amount is unchanged by the white component" % board)


## get_drop_costs must return a fresh array each call — PlinkoBoard._get_drop_costs
## mutates it to apply DROP_COST_REDUCTION, so a shared/cached array would corrupt.
func test_returns_fresh_array_safe_to_mutate() -> void:
	print("test_returns_fresh_array_safe_to_mutate")
	var a: Array = TierRegistry.get_drop_costs(Enums.BoardType.ORANGE)
	a[0][1] = 999
	var b: Array = TierRegistry.get_drop_costs(Enums.BoardType.ORANGE)
	assert_equal(b[0][1], 100, "a second call is unaffected by mutating the first")
