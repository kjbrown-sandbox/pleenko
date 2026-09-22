extends "res://test/test_base.gd"

## Auto-buy tests — run with:
##   godot --headless --scene res://test/test_auto_buy.tscn
##
## Red's signature upgrade: lock a (board, upgrade) pair to a slot and it buys
## itself the instant it becomes affordable.
##
## AutoBuyLocks is a pure RefCounted with an injected capacity, so the slot rules
## run with no currency in play. The drain loop runs against the real
## UpgradeManager, because the thing most worth guarding is that buying — which
## spends currency, which re-emits currency_changed — cannot recurse.


func _run_tests() -> void:
	print("\n=== Auto-buy Tests ===\n")

	test_nothing_locks_without_slots()
	test_locking_consumes_a_slot()
	test_toggle_off_frees_the_slot()
	test_refusal_and_unlock_are_distinguishable()
	test_locks_are_per_board_upgrade_pair()
	test_free_slots_never_goes_negative()
	test_restore_drops_locks_beyond_capacity()
	test_restore_ignores_malformed_entries()
	test_pairs_round_trip_through_the_key()
	test_affordable_lock_is_bought()
	test_purchase_does_not_recurse()
	test_unaffordable_lock_is_left_alone()
	test_capped_upgrade_keeps_its_lock()
	test_drain_is_bounded_per_pass()
	test_prestige_reset_clears_locks()
	test_save_round_trip()
	test_old_save_loads_with_no_locks()
	test_tres_description_matches_the_slot_slope()
	test_restore_rejects_out_of_range_ordinals()
	await test_auto_bought_upgrade_reaches_the_board()
	await test_manual_purchase_applies_exactly_once()
	test_auto_buy_keeps_buying_while_coins_land()
	test_catch_up_spends_offline_earnings()
	test_catch_up_budget_exceeds_the_per_landing_one()
	test_catch_up_is_inert_with_no_locks()
	await test_cap_raise_does_not_grow_the_board()
	await test_force_apply_does_not_grow_the_board()
	test_upgrade_bought_fires_only_for_paid_levels()

	print("\n=== Done ===\n")


func _make_locks(slots: int) -> AutoBuyLocks:
	var locks := AutoBuyLocks.new()
	locks.capacity_fn = func() -> int: return slots
	return locks


# --- Slot rules (pure) ---

func test_nothing_locks_without_slots() -> void:
	print("test_nothing_locks_without_slots")
	# A bare AutoBuyLocks defaults to zero capacity on purpose: an unconfigured
	# instance refusing everything is safer than one allowing everything.
	var locks := AutoBuyLocks.new()
	assert_equal(locks.capacity(), 0, "capacity defaults to none")
	assert_false(locks.toggle(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"locking is refused with no slots")
	assert_equal(locks.count(), 0, "and nothing is recorded")


func test_locking_consumes_a_slot() -> void:
	print("test_locking_consumes_a_slot")
	var locks := _make_locks(2)
	assert_true(locks.toggle(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW), "first lock")
	assert_equal(locks.free_slots(), 1, "one slot left")
	assert_true(locks.toggle(Enums.BoardType.ORANGE, Enums.UpgradeType.QUEUE), "second lock")
	assert_equal(locks.free_slots(), 0, "roster is full")
	assert_false(locks.toggle(Enums.BoardType.RED, Enums.UpgradeType.DROP_RATE),
		"a third is refused")
	assert_equal(locks.count(), 2, "and is not recorded")


func test_toggle_off_frees_the_slot() -> void:
	print("test_toggle_off_frees_the_slot")
	var locks := _make_locks(1)
	locks.toggle(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	assert_false(locks.toggle(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"toggling the same pair releases it")
	assert_equal(locks.free_slots(), 1, "the slot comes back")
	assert_true(locks.toggle(Enums.BoardType.ORANGE, Enums.UpgradeType.QUEUE),
		"and can be spent on something else")


func test_refusal_and_unlock_are_distinguishable() -> void:
	print("test_refusal_and_unlock_are_distinguishable")
	# Both leave the pair unlocked and both return false, so the CALLER has to be
	# able to tell them apart — a UI that conflated them would swallow a click on
	# a full roster with no feedback.
	var locks := _make_locks(1)
	locks.toggle(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	assert_false(locks.can_lock(Enums.BoardType.ORANGE, Enums.UpgradeType.QUEUE),
		"a new pair cannot be locked on a full roster")
	assert_true(locks.can_lock(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"but the already-locked pair can still be toggled off")


func test_locks_are_per_board_upgrade_pair() -> void:
	print("test_locks_are_per_board_upgrade_pair")
	# The same upgrade on two boards is two locks — this is what makes a slot a
	# small grant, and it follows how UpgradeManager stores levels.
	var locks := _make_locks(2)
	locks.toggle(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	assert_false(locks.is_locked(Enums.BoardType.ORANGE, Enums.UpgradeType.ADD_ROW),
		"orange's copy of the same upgrade is a separate lock")
	assert_true(locks.toggle(Enums.BoardType.ORANGE, Enums.UpgradeType.ADD_ROW),
		"and takes its own slot")


func test_free_slots_never_goes_negative() -> void:
	print("test_free_slots_never_goes_negative")
	# Capacity can SHRINK mid-session: a prestige wipes the levels that paid for
	# the slots. free_slots must not go negative and make can_lock nonsense.
	var slots: Array[int] = [3]
	var locks := AutoBuyLocks.new()
	locks.capacity_fn = func() -> int: return slots[0]
	locks.toggle(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	locks.toggle(Enums.BoardType.ORANGE, Enums.UpgradeType.QUEUE)
	slots[0] = 0
	assert_equal(locks.free_slots(), 0, "free slots floors at zero")
	assert_false(locks.can_lock(Enums.BoardType.RED, Enums.UpgradeType.DROP_RATE),
		"and nothing new can be locked")


# --- Persistence (pure) ---

func test_restore_drops_locks_beyond_capacity() -> void:
	print("test_restore_drops_locks_beyond_capacity")
	# Honouring more locks than the player owns slots for would be a quiet cheat.
	var locks := _make_locks(1)
	locks.restore([
		AutoBuyLocks.key_for(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		AutoBuyLocks.key_for(Enums.BoardType.ORANGE, Enums.UpgradeType.QUEUE),
	])
	assert_equal(locks.count(), 1, "only as many locks as slots survive")


func test_restore_ignores_malformed_entries() -> void:
	print("test_restore_ignores_malformed_entries")
	# The save file is the untrusted input here.
	var locks := _make_locks(5)
	locks.restore(["", "garbage", "1:", ":2", "1:2:3", 42, null,
		AutoBuyLocks.key_for(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)])
	assert_equal(locks.count(), 1, "only the well-formed entry is restored")
	assert_true(locks.is_locked(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"and it is the right pair")


func test_pairs_round_trip_through_the_key() -> void:
	print("test_pairs_round_trip_through_the_key")
	# pairs() is what the drain loop iterates, so a key that didn't decode back
	# to its own board/upgrade would auto-buy the wrong thing.
	var locks := _make_locks(3)
	locks.toggle(Enums.BoardType.VIOLET, Enums.UpgradeType.BUCKET_VALUE)
	locks.toggle(Enums.BoardType.GREEN, Enums.UpgradeType.DROP_RATE)
	var seen: Dictionary = {}
	for pair: Dictionary in locks.pairs():
		seen[AutoBuyLocks.key_for(pair["board_type"], pair["upgrade_type"])] = true
	assert_true(seen.has(AutoBuyLocks.key_for(
		Enums.BoardType.VIOLET, Enums.UpgradeType.BUCKET_VALUE)), "violet pair survives")
	assert_true(seen.has(AutoBuyLocks.key_for(
		Enums.BoardType.GREEN, Enums.UpgradeType.DROP_RATE)), "green pair survives")
	assert_equal(seen.size(), 2, "and nothing extra appears")


# --- Drain loop (against the real UpgradeManager) ---

func _arm(slots: int, board: Enums.BoardType, upgrade: Enums.UpgradeType) -> void:
	UpgradeManager.reset()
	CurrencyManager.reset()
	UpgradeManager.get_state(UpgradeManager.AUTO_BUY_BOARD,
		Enums.UpgradeType.AUTO_BUY).level = slots
	UpgradeManager.unlock(board, upgrade)


func test_affordable_lock_is_bought() -> void:
	print("test_affordable_lock_is_bought")
	_arm(1, Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	var cost: int = UpgradeManager.get_cost(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, cost)

	UpgradeManager.toggle_auto_buy(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)

	assert_equal(UpgradeManager.get_level(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW), 1,
		"locking something already affordable buys it immediately")
	UpgradeManager.reset()
	CurrencyManager.reset()


func test_purchase_does_not_recurse() -> void:
	print("test_purchase_does_not_recurse")
	# THE guard that matters. buy() spends, spending emits currency_changed, and
	# that lands back in the drain — without the re-entrancy flag this is
	# unbounded recursion on the very first affordable purchase, not a subtle
	# bug. Fund several levels so the loop has every chance to run away.
	_arm(1, Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 100000)

	UpgradeManager.toggle_auto_buy(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)

	# Reaching this line at all is the assertion: a recursive drain would have
	# blown the stack rather than failed.
	assert_true(UpgradeManager.get_level(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW) > 0,
		"the drain bought at least one level without recursing")
	assert_false(UpgradeManager._draining, "and the re-entrancy flag is released")
	UpgradeManager.reset()
	CurrencyManager.reset()


func test_unaffordable_lock_is_left_alone() -> void:
	print("test_unaffordable_lock_is_left_alone")
	_arm(1, Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	UpgradeManager.toggle_auto_buy(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)

	assert_equal(UpgradeManager.get_level(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW), 0,
		"nothing is bought with no currency")
	assert_true(UpgradeManager.auto_buy_locks.is_locked(
		Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"but the lock stands, waiting for the coin that pays for it")
	UpgradeManager.reset()
	CurrencyManager.reset()


func test_capped_upgrade_keeps_its_lock() -> void:
	print("test_capped_upgrade_keeps_its_lock")
	# A capped pair stops buying but KEEPS its slot: freeing it automatically
	# would silently re-allocate a slot the player chose to spend here.
	_arm(1, Enums.BoardType.GOLD, Enums.UpgradeType.QUEUE)
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(
		Enums.BoardType.GOLD, Enums.UpgradeType.QUEUE)
	state.level = UpgradeManager.get_max_level(Enums.BoardType.GOLD, Enums.UpgradeType.QUEUE)
	var capped_at: int = state.level
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 100000)

	UpgradeManager.toggle_auto_buy(Enums.BoardType.GOLD, Enums.UpgradeType.QUEUE)

	assert_equal(state.level, capped_at, "a capped upgrade buys nothing more")
	assert_true(UpgradeManager.auto_buy_locks.is_locked(
		Enums.BoardType.GOLD, Enums.UpgradeType.QUEUE), "and holds its slot")
	assert_equal(UpgradeManager.auto_buy_locks.free_slots(), 0, "which stays spent")
	UpgradeManager.reset()
	CurrencyManager.reset()


func test_drain_is_bounded_per_pass() -> void:
	print("test_drain_is_bounded_per_pass")
	# An enormous balance must not stall a frame buying thousands of levels.
	# Whatever is left is picked up by the next currency_changed.
	_arm(1, Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE)
	# Three things could bound this drain and only ONE of them is under test, so
	# neutralise the other two explicitly:
	#   - the .tres caps BUCKET_VALUE at 7, below the ceiling, so 7 <= 32 would
	#     pass with the ceiling deleted entirely;
	#   - cost escalates, and CurrencyManager.add clamps to the currency CAP, so
	#     "add a billion" does not actually buy a billion's worth.
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(
		Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE)
	state.current_cap = UpgradeManager.MAX_AUTO_BUYS_PER_DRAIN * 4
	state.cost = 1
	state.delta = 0
	# delta re-escalates from the RESOURCE on every buy, so zeroing the state's
	# delta alone is not enough — costs would climb 1, 11, 31, 61... and run the
	# balance dry long before the ceiling. Flatten the curve for this test and
	# put it back, since the resource is shared with every other suite.
	var data: BaseUpgradeData = UpgradeManager.get_upgrade(Enums.UpgradeType.BUCKET_VALUE)
	var real_escalation: int = data.delta_escalation
	data.delta_escalation = 0
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN,
		UpgradeManager.MAX_AUTO_BUYS_PER_DRAIN * 4)
	assert_true(CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN)
			> UpgradeManager.MAX_AUTO_BUYS_PER_DRAIN,
		"funded past the ceiling, so cost is not what bounds the drain")

	UpgradeManager.toggle_auto_buy(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE)

	assert_equal(state.level, UpgradeManager.MAX_AUTO_BUYS_PER_DRAIN,
		"one drain buys exactly the ceiling and stops")

	data.delta_escalation = real_escalation
	UpgradeManager.reset()
	CurrencyManager.reset()


# --- Lifecycle ---

func test_prestige_reset_clears_locks() -> void:
	print("test_prestige_reset_clears_locks")
	# Locks go with the levels. A prestige wipes the slots that paid for them, so
	# keeping the locks would auto-buy on credit the player no longer owns.
	_arm(2, Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	UpgradeManager.toggle_auto_buy(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	assert_equal(UpgradeManager.auto_buy_locks.count(), 1, "locked before the reset")

	UpgradeManager.reset()

	assert_equal(UpgradeManager.auto_buy_locks.count(), 0, "and cleared by it")
	CurrencyManager.reset()


func test_save_round_trip() -> void:
	print("test_save_round_trip")
	_arm(2, Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	UpgradeManager.unlock(Enums.BoardType.ORANGE, Enums.UpgradeType.QUEUE)
	UpgradeManager.toggle_auto_buy(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	UpgradeManager.toggle_auto_buy(Enums.BoardType.ORANGE, Enums.UpgradeType.QUEUE)

	var blob: Dictionary = UpgradeManager.serialize()
	UpgradeManager.reset()
	assert_equal(UpgradeManager.auto_buy_locks.count(), 0, "cleared before restoring")

	UpgradeManager.deserialize(blob)

	assert_true(UpgradeManager.auto_buy_locks.is_locked(
		Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW), "gold's lock survives a round trip")
	assert_true(UpgradeManager.auto_buy_locks.is_locked(
		Enums.BoardType.ORANGE, Enums.UpgradeType.QUEUE), "so does orange's")
	UpgradeManager.reset()
	CurrencyManager.reset()


## An old save has no auto_buy_locks key at all; it must load with none rather
## than erroring, so no SAVE_VERSION bump is needed for this feature.
func test_old_save_loads_with_no_locks() -> void:
	print("test_old_save_loads_with_no_locks")
	UpgradeManager.reset()
	UpgradeManager.deserialize({"state": {}, "unlocked": {}})
	assert_equal(UpgradeManager.auto_buy_locks.count(), 0,
		"a pre-auto-buy save loads with nothing locked")
	UpgradeManager.reset()


## auto_buy.tres promises "+1 auto-buy slot per level" in player-facing prose.
## Pin it against the live slope so the description can't become a lie.
func test_tres_description_matches_the_slot_slope() -> void:
	print("test_tres_description_matches_the_slot_slope")
	var data: BaseUpgradeData = UpgradeManager.get_upgrade(Enums.UpgradeType.AUTO_BUY)
	assert_true(data != null, "the auto-buy upgrade resource is registered")
	if data:
		# Derived from the live slope, not a copy of the string being checked —
		# the sibling suites all pin descriptions this way.
		UpgradeManager.get_state(UpgradeManager.AUTO_BUY_BOARD,
			Enums.UpgradeType.AUTO_BUY).level = 1
		var slope: int = UpgradeManager.current_auto_buy_slots()
		assert_equal(slope, 1, "one slot per level is the live slope")
		assert_true(data.description.contains("+%d auto-buy slot" % slope),
			"description quotes the live slope (+%d)" % slope)
		UpgradeManager.reset()


# --- The bug that shipped ---

## Auto-buy originally called UpgradeManager.buy() directly, but the BOARD effect
## of a per-board upgrade lived only in UpgradeSection's click handler — so an
## auto-bought upgrade took the currency, raised the level, and changed nothing
## about the board. Every upgrade the player can lock was affected.
##
## The effect now rides upgrade_purchased, so it happens whoever triggered the
## buy. Asserted on the BOARD, not on get_level(), because the level was always
## the part that already worked.
func test_auto_bought_upgrade_reaches_the_board() -> void:
	print("test_auto_bought_upgrade_reaches_the_board")
	_arm(1, Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)

	var board: PlinkoBoard = preload("res://entities/plinko_board/plinko_board.tscn").instantiate()
	add_child(board)
	board.setup(Enums.BoardType.GOLD)
	var rows_before: int = board.num_rows

	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN,
		UpgradeManager.get_cost(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW))
	UpgradeManager.toggle_auto_buy(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)

	assert_equal(UpgradeManager.get_level(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW), 1,
		"the level went up")
	# The effect is deferred out of the landing it may have been triggered from.
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(board.num_rows > rows_before,
		"and the board actually grew (%d -> %d)" % [rows_before, board.num_rows])

	board.queue_free()
	UpgradeManager.reset()
	CurrencyManager.reset()


## A manual click must not double-apply now that the effect rides the signal —
## the click handler was reduced to a bare buy() for exactly this reason.
func test_manual_purchase_applies_exactly_once() -> void:
	print("test_manual_purchase_applies_exactly_once")
	UpgradeManager.reset()
	CurrencyManager.reset()
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)

	var board: PlinkoBoard = preload("res://entities/plinko_board/plinko_board.tscn").instantiate()
	add_child(board)
	board.setup(Enums.BoardType.GOLD)
	var rows_before: int = board.num_rows

	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN,
		UpgradeManager.get_cost(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW))
	board.upgrade_section._buy_upgrade(Enums.UpgradeType.ADD_ROW)
	await get_tree().process_frame
	await get_tree().process_frame

	# add_two_rows adds exactly two; four would mean both paths fired.
	assert_equal(board.num_rows, rows_before + 2,
		"a click grows the board once, not twice")

	board.queue_free()
	UpgradeManager.reset()
	CurrencyManager.reset()


## An out-of-range ordinal in a hand-edited save must never reach the drain: it
## would raise on _state[99] mid-loop and, with no `finally` in GDScript, leave
## the re-entrancy flag latched and auto-buy dead for the session.
func test_restore_rejects_out_of_range_ordinals() -> void:
	print("test_restore_rejects_out_of_range_ordinals")
	var locks := _make_locks(5)
	locks.restore(["99:3", "0:99", "-1:0", "0:-1",
		AutoBuyLocks.key_for(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)])
	assert_equal(locks.count(), 1, "only the in-range pair is restored")
	assert_true(locks.is_locked(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"and it is the right one")


# --- Idle ---

## ACTIVE idle: the game is open and autodroppers are landing coins. Every
## landing credits currency, which is the signal the drain rides — so purchases
## keep happening with no player input at all. Simulated by crediting currency
## repeatedly, which is exactly what a landing does.
func test_auto_buy_keeps_buying_while_coins_land() -> void:
	print("test_auto_buy_keeps_buying_while_coins_land")
	_arm(1, Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE)
	UpgradeManager.toggle_auto_buy(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE)
	assert_equal(UpgradeManager.get_level(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE), 0,
		"nothing bought yet — no currency has arrived")

	var levels: Array[int] = []
	for landing in 6:
		# One "coin landing": credit the board's currency, which fires
		# currency_changed exactly the way finalize_coin_landing does.
		CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 40)
		levels.append(UpgradeManager.get_level(
			Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE))

	assert_true(levels[0] > 0, "the first landing that affords it buys immediately")
	assert_true(levels[levels.size() - 1] > levels[0],
		"and later landings keep buying (%d -> %d) with no input"
			% [levels[0], levels[levels.size() - 1]])
	UpgradeManager.reset()
	CurrencyManager.reset()


## OFFLINE idle: earnings accrue while the game is closed, and are credited into
## the save blob BEFORE any manager deserializes — so the currency_changed fired
## during load arrives while the lock set is still empty and the normal drain
## cannot see it. catch_up_auto_buys is the one-shot that spends it.
func test_catch_up_spends_offline_earnings() -> void:
	print("test_catch_up_spends_offline_earnings")
	_arm(1, Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE)
	UpgradeManager.toggle_auto_buy(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE)

	# Stand in for a load: currency lands while nothing is watching. Done by
	# suppressing the drain the way the real load order does — locks restored
	# after the currency signal has already gone out.
	var locks_blob: Array = UpgradeManager.auto_buy_locks.serialize()
	UpgradeManager.auto_buy_locks.clear()
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 400)
	UpgradeManager.auto_buy_locks.restore(locks_blob)

	assert_equal(UpgradeManager.get_level(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE), 0,
		"precondition: the load-time credit bought nothing on its own")

	UpgradeManager.catch_up_auto_buys()

	assert_true(UpgradeManager.get_level(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE) > 0,
		"the catch-up spends what accumulated while the game was closed")
	UpgradeManager.reset()
	CurrencyManager.reset()


## The catch-up is allowed a far bigger budget than a per-landing drain, since a
## long idle is exactly when a large backlog is expected.
func test_catch_up_budget_exceeds_the_per_landing_one() -> void:
	print("test_catch_up_budget_exceeds_the_per_landing_one")
	assert_true(UpgradeManager.MAX_AUTO_BUYS_ON_LOAD > UpgradeManager.MAX_AUTO_BUYS_PER_DRAIN,
		"a returning player is not rate-limited to the per-landing ceiling")
	assert_true(UpgradeManager.MAX_AUTO_BUYS_ON_LOAD > 0,
		"and the catch-up is still bounded, so a corrupt save cannot hang the load")

	# Constants alone would stay green if catch_up_auto_buys stopped passing the
	# bigger limit through, so drive a real backlog past the per-landing ceiling.
	# Same fixture as test_drain_is_bounded_per_pass: flat cost, raised cap, so
	# neither affordability nor the .tres cap is what bounds the drain.
	_arm(1, Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE)
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(
		Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE)
	state.current_cap = UpgradeManager.MAX_AUTO_BUYS_PER_DRAIN * 4
	state.delta = 0
	var data: BaseUpgradeData = UpgradeManager.get_upgrade(Enums.UpgradeType.BUCKET_VALUE)
	var real_escalation: int = data.delta_escalation
	data.delta_escalation = 0

	# Lock it while it is genuinely unaffordable — CurrencyManager.reset leaves a
	# starting balance, so a cheap upgrade would be bought the instant it locks
	# and this would measure the wrong drain.
	state.cost = 1_000_000
	UpgradeManager.toggle_auto_buy(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE)
	assert_equal(state.level, 0, "precondition: nothing bought while unaffordable")

	# Now make it cheap and fund it the way a load does: with the locks out of
	# sight, so the normal drain never sees the credit.
	state.cost = 1
	var locks_blob: Array = UpgradeManager.auto_buy_locks.serialize()
	UpgradeManager.auto_buy_locks.clear()
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN,
		UpgradeManager.MAX_AUTO_BUYS_PER_DRAIN * 4)
	UpgradeManager.auto_buy_locks.restore(locks_blob)
	assert_equal(state.level, 0, "precondition: the load-time credit bought nothing")

	UpgradeManager.catch_up_auto_buys()

	assert_true(state.level > UpgradeManager.MAX_AUTO_BUYS_PER_DRAIN,
		"the catch-up buys past the per-landing ceiling (%d), got %d"
			% [UpgradeManager.MAX_AUTO_BUYS_PER_DRAIN, state.level])

	data.delta_escalation = real_escalation
	UpgradeManager.reset()
	CurrencyManager.reset()


## With nothing locked the catch-up is inert, so it costs a returning player
## nothing and cannot spend currency they never assigned.
func test_catch_up_is_inert_with_no_locks() -> void:
	print("test_catch_up_is_inert_with_no_locks")
	UpgradeManager.reset()
	CurrencyManager.reset()
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE)
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 400)
	var before: int = CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN)

	UpgradeManager.catch_up_auto_buys()

	assert_equal(CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN), before,
		"nothing locked means nothing spent")
	UpgradeManager.reset()
	CurrencyManager.reset()


# --- The board effect must fire ONLY for a paid level ---

## A cap raise raises the CEILING, not the level — and `buy_cap_raise` emits
## `upgrade_purchased` with the level unchanged. Hanging the board effect on that
## broad signal granted a free add_two_rows for cap-raise money, and desynced
## geometry from level: the rows evaporated on the next load, because
## apply_saved_state rebuilds the board from the recorded level.
func test_cap_raise_does_not_grow_the_board() -> void:
	print("test_cap_raise_does_not_grow_the_board")
	UpgradeManager.reset()
	CurrencyManager.reset()
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	UpgradeManager.enable_cap_raise(Enums.BoardType.GOLD)

	var board: PlinkoBoard = preload("res://entities/plinko_board/plinko_board.tscn").instantiate()
	add_child(board)
	board.setup(Enums.BoardType.GOLD)
	var rows_before: int = board.num_rows
	var level_before: int = UpgradeManager.get_level(
		Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)

	var cap_currency: int = TierRegistry.cap_raise_currency(Enums.BoardType.GOLD)
	if cap_currency >= 0:
		CurrencyManager.add(cap_currency,
			UpgradeManager.get_cap_raise_cost(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW))
		assert_true(UpgradeManager.buy_cap_raise(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
			"precondition: the cap raise went through")
		await get_tree().process_frame
		await get_tree().process_frame

		assert_equal(board.num_rows, rows_before,
			"a cap raise does not grow the board — it only raises the ceiling")
		assert_equal(UpgradeManager.get_level(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
			level_before, "and does not advance the level")

	board.queue_free()
	UpgradeManager.reset()
	CurrencyManager.reset()


## force_apply grants a level with no payment — challenge starting conditions and
## prestige rewards. Challenge setup builds its own boards afterwards, so letting
## the effect fire here would apply it twice.
func test_force_apply_does_not_grow_the_board() -> void:
	print("test_force_apply_does_not_grow_the_board")
	UpgradeManager.reset()
	CurrencyManager.reset()
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)

	var board: PlinkoBoard = preload("res://entities/plinko_board/plinko_board.tscn").instantiate()
	add_child(board)
	board.setup(Enums.BoardType.GOLD)
	var rows_before: int = board.num_rows

	UpgradeManager.force_apply(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(UpgradeManager.get_level(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW) > 0,
		"precondition: force_apply did grant the level")
	assert_equal(board.num_rows, rows_before,
		"but the board effect did not fire — board setup owns that")

	board.queue_free()
	UpgradeManager.reset()
	CurrencyManager.reset()


## The narrow signal fires for a real purchase and only for a real purchase.
func test_upgrade_bought_fires_only_for_paid_levels() -> void:
	print("test_upgrade_bought_fires_only_for_paid_levels")
	UpgradeManager.reset()
	CurrencyManager.reset()
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)

	var bought: Array[int] = []
	var handler := func(_ut: Enums.UpgradeType, _bt: Enums.BoardType, lvl: int) -> void:
		bought.append(lvl)
	UpgradeManager.upgrade_bought.connect(handler)

	UpgradeManager.force_apply(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	assert_equal(bought.size(), 0, "force_apply does not count as bought")

	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN,
		UpgradeManager.get_cost(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW))
	UpgradeManager.buy(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	assert_equal(bought.size(), 1, "a paid level does")

	UpgradeManager.upgrade_bought.disconnect(handler)
	UpgradeManager.reset()
	CurrencyManager.reset()
