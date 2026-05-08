extends "res://test/test_base.gd"

## Soft-lock rescue tests — run with:
##   godot --headless --scene res://test/test_soft_lock_rescue.tscn
##
## Tests check_and_rescue_gold_soft_lock() on a bare BoardManager with a
## minimal gold PlinkoBoard. Uses autoloads (CurrencyManager, TierRegistry).


func _run_tests() -> void:
	print("\n=== Soft-Lock Rescue Tests ===\n")

	test_rescue_grants_gold_when_both_zero()
	test_no_rescue_when_gold_nonzero()
	test_no_rescue_when_raw_orange_nonzero()
	test_rescue_idempotent()
	test_currency_changed_triggers_rescue()


func _reset_to_zero() -> void:
	CurrencyManager.reset()
	# reset() gives 1 gold to the starting tier — spend it to reach 0/0.
	CurrencyManager.spend(Enums.CurrencyType.GOLD_COIN, 1)


func _make_board_manager() -> BoardManager:
	var bm := BoardManager.new()
	var gold_board := PlinkoBoard.new()
	gold_board.board_type = Enums.BoardType.GOLD
	# coin_queue is @onready (null on bare board). Assign a bare CoinQueue
	# so the rescue function's is_empty() check doesn't crash.
	gold_board.coin_queue = CoinQueue.new()
	bm._boards.append(gold_board)
	return bm


# --- Test Cases ---

func test_rescue_grants_gold_when_both_zero() -> void:
	print("test_rescue_grants_gold_when_both_zero")
	_reset_to_zero()
	var bm := _make_board_manager()
	bm.check_and_rescue_gold_soft_lock()
	assert_equal(
		CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN), 1,
		"should grant 1 gold when both source currencies are 0")
	bm.queue_free()


func test_no_rescue_when_gold_nonzero() -> void:
	print("test_no_rescue_when_gold_nonzero")
	_reset_to_zero()
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 5)
	var bm := _make_board_manager()
	bm.check_and_rescue_gold_soft_lock()
	assert_equal(
		CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN), 5,
		"should NOT grant gold when gold balance is nonzero")
	bm.queue_free()


func test_no_rescue_when_raw_orange_nonzero() -> void:
	print("test_no_rescue_when_raw_orange_nonzero")
	_reset_to_zero()
	CurrencyManager.add(Enums.CurrencyType.RAW_ORANGE, 3)
	var bm := _make_board_manager()
	bm.check_and_rescue_gold_soft_lock()
	assert_equal(
		CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN), 0,
		"should NOT grant gold when raw orange is nonzero")
	bm.queue_free()


func test_rescue_idempotent() -> void:
	print("test_rescue_idempotent")
	_reset_to_zero()
	var bm := _make_board_manager()
	bm.check_and_rescue_gold_soft_lock()
	bm.check_and_rescue_gold_soft_lock()
	assert_equal(
		CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN), 1,
		"calling rescue twice should still result in exactly 1 gold")
	bm.queue_free()


func test_currency_changed_triggers_rescue() -> void:
	print("test_currency_changed_triggers_rescue")
	_reset_to_zero()
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 1)
	# Now gold=1, raw_orange=0. Spending the gold should leave both at 0.
	CurrencyManager.spend(Enums.CurrencyType.GOLD_COIN, 1)
	assert_equal(
		CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN), 0,
		"gold should be 0 after spending")
	# Simulate what BoardManager._on_currency_changed does
	var bm := _make_board_manager()
	bm.check_and_rescue_gold_soft_lock()
	assert_equal(
		CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN), 1,
		"rescue should grant 1 gold after spend leaves both at 0")
	bm.queue_free()
