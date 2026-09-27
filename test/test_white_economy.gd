extends "res://test/test_base.gd"

## White's place in the live economy — run with:
##   godot --headless --scene res://test/test_white_economy.tscn
##
## Covers the two rules that could not live in WhiteCurrency because they need
## the autoloads: white pricing its own cap raises (it has no next tier to draw
## from), and the last tier being uncapped so it can reach the earring geometry at
## all. Pure WhiteCurrency maths lives in test_white_currency.gd.


func _run_tests() -> void:
	print("\n=== White Economy Tests ===\n")

	test_white_has_no_tier()
	test_white_cap_raise_is_priced_in_white()
	test_white_cap_raise_blocked_when_broke()
	test_white_cap_raise_spends_white_and_raises_cap()
	test_white_cap_raise_needs_no_board_unlock()
	test_white_plus_button_is_actually_reachable()
	test_white_cap_raise_is_not_free()
	test_white_starting_cap_covers_the_priciest_drop()
	test_other_currencies_still_use_next_tier()
	test_last_tier_is_uncapped()
	test_last_tier_add_row_still_bounded_by_geometry()
	test_non_last_tiers_keep_their_caps()


# --- White is tier-less ---

func test_white_has_no_tier() -> void:
	print("test_white_has_no_tier")
	# Everything downstream (caps, cap-raise pricing, the offline prestige gate)
	# branches on this being null.
	assert_true(TierRegistry.get_tier_for_currency(Enums.CurrencyType.WHITE_COIN) == null,
		"WHITE_COIN belongs to no tier")
	for board in Enums.BoardType.values():
		assert_false(TierRegistry.primary_currency(board) == Enums.CurrencyType.WHITE_COIN,
			"no board claims white as its primary currency")


# --- Cap raises ---

func test_white_cap_raise_is_priced_in_white() -> void:
	print("test_white_cap_raise_is_priced_in_white")
	assert_equal(CurrencyManager.cap_raise_currency(Enums.CurrencyType.WHITE_COIN),
		Enums.CurrencyType.WHITE_COIN, "white pays for its own cap raises")
	assert_equal(CurrencyManager.cap_raise_amount(Enums.CurrencyType.WHITE_COIN),
		WhiteCurrency.CAP_RAISE_AMOUNT, "and raises by its own constant")


func test_white_cap_raise_blocked_when_broke() -> void:
	print("test_white_cap_raise_blocked_when_broke")
	CurrencyManager.reset()
	assert_false(CurrencyManager.can_buy_cap_raise(Enums.CurrencyType.WHITE_COIN),
		"cannot raise the white cap with no white")


func test_white_cap_raise_spends_white_and_raises_cap() -> void:
	print("test_white_cap_raise_spends_white_and_raises_cap")
	CurrencyManager.reset()
	var cost: int = CurrencyManager.get_cap_raise_cost(Enums.CurrencyType.WHITE_COIN)
	CurrencyManager.add(Enums.CurrencyType.WHITE_COIN, cost)
	var cap_before: int = CurrencyManager.get_cap(Enums.CurrencyType.WHITE_COIN)

	assert_true(CurrencyManager.can_buy_cap_raise(Enums.CurrencyType.WHITE_COIN),
		"affordable once the player holds the cost")
	assert_true(CurrencyManager.buy_cap_raise(Enums.CurrencyType.WHITE_COIN), "purchase succeeds")
	assert_equal(CurrencyManager.get_balance(Enums.CurrencyType.WHITE_COIN), 0,
		"the white was spent, not conjured")
	assert_equal(CurrencyManager.get_cap(Enums.CurrencyType.WHITE_COIN),
		cap_before + WhiteCurrency.CAP_RAISE_AMOUNT, "cap rose by the constant")


## White has no owning board, so its cap raise must not wait on
## UpgradeManager.is_cap_raise_available — that would make it permanently
## unbuyable rather than gated.
func test_white_cap_raise_needs_no_board_unlock() -> void:
	print("test_white_cap_raise_needs_no_board_unlock")
	CurrencyManager.reset()
	UpgradeManager.reset()
	assert_equal(CurrencyManager.cap_raise_board(Enums.CurrencyType.WHITE_COIN), -1,
		"no board gates white")
	CurrencyManager.add(Enums.CurrencyType.WHITE_COIN,
		CurrencyManager.get_cap_raise_cost(Enums.CurrencyType.WHITE_COIN))
	assert_true(CurrencyManager.can_buy_cap_raise(Enums.CurrencyType.WHITE_COIN),
		"buyable despite no board cap-raise unlock")


## REGRESSION, and the one this suite originally missed. Every other test here
## calls CurrencyManager directly, which passed happily while the "+" button that
## reaches it was never shown — `_update_all_cap_buttons` gated on
## `cap_raise_board != -1`, which is always -1 for tier-less white. The white cap
## then stuck at STARTING_CAP forever and, since banking is capped, the priciest
## board became permanently undroppable. Assert the BUTTON, not just the model.
func test_white_plus_button_is_actually_reachable() -> void:
	print("test_white_plus_button_is_actually_reachable")
	UpgradeManager.reset()
	CurrencyManager.reset()

	# The white bar only exists once the first white-COSTING board is unlocked, so
	# that board must be present or this test silently asserts nothing — which is
	# precisely how the original bug survived its own test suite.
	var bm := BoardManager.new()
	var gated := TierRegistry.get_tier_by_index(WhiteCurrency.FIRST_GATED_TIER_INDEX)
	for type: int in [Enums.BoardType.GOLD, Enums.BoardType.ORANGE, gated.board_type]:
		var board := PlinkoBoard.new()
		board.board_type = type as Enums.BoardType
		board.coin_queue = CoinQueue.new()
		bm._boards.append(board)

	var cv := VBoxContainer.new()
	cv.set_script(preload("res://entities/main/coin_values.gd"))
	add_child(cv)
	cv.setup(bm)

	assert_true(cv._bars.has(Enums.CurrencyType.WHITE_COIN),
		"the white bar exists once the first gated board is unlocked")
	# Asserted on `mode`, which is what show_plus_button() actually sets — the
	# derived plus_button.visible depends on the node's _ready having run, which
	# a bare test instance cannot rely on.
	var bar = cv._bars[Enums.CurrencyType.WHITE_COIN]
	assert_equal(bar.mode, RefinedBaselineButton.Mode.WITH_PLUS,
		"white's cap + button is enabled without any board cap-raise unlock")
	assert_equal(CurrencyManager.cap_raise_board(Enums.CurrencyType.WHITE_COIN), -1,
		"and it shows despite having no owning board — the trap this guards")

	# Contrast: a tier currency's "+" stays hidden, so the carve-out is white-only.
	var gold_bar = cv._bars[Enums.CurrencyType.GOLD_COIN]
	assert_equal(gold_bar.mode, RefinedBaselineButton.Mode.NEITHER,
		"gold's + stays hidden until its board unlocks cap raises")

	cv.queue_free()
	bm.queue_free()


## The shared cap-raise curve starts at 1. For a currency that buys its own
## raises that would mean the first +500 cap costs a single white — free, and
## against the scarcity the drop costs are built around.
func test_white_cap_raise_is_not_free() -> void:
	print("test_white_cap_raise_is_not_free")
	CurrencyManager.reset()
	var first: int = CurrencyManager.get_cap_raise_cost(Enums.CurrencyType.WHITE_COIN)
	assert_equal(first, WhiteCurrency.cap_raise_cost(0), "priced by WhiteCurrency, not the shared curve")
	assert_true(first > 1, "the first white cap raise is not a token price")
	# And it escalates, so storage keeps costing more.
	assert_true(WhiteCurrency.cap_raise_cost(1) > WhiteCurrency.cap_raise_cost(0),
		"each raise costs more than the last")


## Banking is capped, so a drop priced above the starting cap could never become
## affordable — the player could not even reach the first cap raise.
func test_white_starting_cap_covers_the_priciest_drop() -> void:
	print("test_white_starting_cap_covers_the_priciest_drop")
	var priciest: int = 0
	for cost: int in WhiteCurrency.DROP_COSTS:
		priciest = maxi(priciest, cost)
	assert_true(WhiteCurrency.STARTING_CAP > priciest,
		"starting cap (%d) exceeds the priciest drop (%d)" % [WhiteCurrency.STARTING_CAP, priciest])


## Regression: the white special-case must not leak into the normal path. A tier
## currency is still priced in the NEXT tier's primary.
func test_other_currencies_still_use_next_tier() -> void:
	print("test_other_currencies_still_use_next_tier")
	assert_equal(CurrencyManager.cap_raise_currency(Enums.CurrencyType.GOLD_COIN),
		Enums.CurrencyType.ORANGE_COIN, "gold caps are raised with orange")
	assert_equal(CurrencyManager.cap_raise_currency(Enums.CurrencyType.ORANGE_COIN),
		Enums.CurrencyType.RED_COIN, "orange caps are raised with red")


# --- Last tier uncapped ---

## The last tier has no next tier, so it can never buy a cap raise. Leaving its
## authored max_level in place stranded it below every ceiling the other boards
## climb past — it could never pass 9 buckets, so it could never grow earrings,
## mint white, or earn a transporter.
func test_last_tier_is_uncapped() -> void:
	print("test_last_tier_is_uncapped")
	UpgradeManager.reset()
	var last := TierRegistry.get_tier_by_index(TierRegistry.get_tier_count() - 1)
	assert_equal(TierRegistry.cap_raise_currency(last.board_type), -1,
		"the last tier has no cap-raise currency (the premise)")
	for upgrade: int in [Enums.UpgradeType.BUCKET_VALUE, Enums.UpgradeType.DROP_RATE,
			Enums.UpgradeType.QUEUE]:
		assert_equal(UpgradeManager.get_max_level(last.board_type,
			upgrade as Enums.UpgradeType), 0,
			"last tier upgrade %d is uncapped" % upgrade)


## ADD_ROW is the exception: its ceiling is geometric, not economic. Uncapping the
## last tier must let it REACH that ceiling without removing it — buying past the
## point where the earrings meet would grow nothing.
func test_last_tier_add_row_still_bounded_by_geometry() -> void:
	print("test_last_tier_add_row_still_bounded_by_geometry")
	UpgradeManager.reset()
	var last := TierRegistry.get_tier_by_index(TierRegistry.get_tier_count() - 1)
	var cap: int = UpgradeManager.get_max_level(last.board_type, Enums.UpgradeType.ADD_ROW)
	assert_equal(cap, EarringGeometry.max_add_row_level(),
		"ADD_ROW still stops where the earrings meet")
	assert_true(cap > 0, "and that ceiling is a real number, not 'uncapped'")


func test_non_last_tiers_keep_their_caps() -> void:
	print("test_non_last_tiers_keep_their_caps")
	UpgradeManager.reset()
	# Gold has a next tier, so its authored max_level must still apply — otherwise
	# the uncapping rule has leaked and cap raises stop mattering everywhere.
	var gold_bv: int = UpgradeManager.get_max_level(Enums.BoardType.GOLD,
		Enums.UpgradeType.BUCKET_VALUE)
	assert_true(gold_bv > 0, "gold bucket value is still capped")
