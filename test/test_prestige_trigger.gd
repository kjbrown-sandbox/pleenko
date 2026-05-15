extends "res://test/test_base.gd"

## Prestige trigger tests — run with:
##   godot --headless --scene res://test/test_prestige_trigger.tscn
##
## Verifies that prestige state is only set through the PrestigeAnimator path,
## not silently through BoardManager._on_currency_changed.

func _run_tests() -> void:
	print("\n=== Prestige Trigger Tests ===\n")

	test_currency_changed_does_not_trigger_prestige()
	test_currency_changed_does_not_re_trigger_after_prestige()
	test_will_trigger_prestige_true_for_raw_currency()
	test_will_trigger_prestige_false_after_prestige()


func _reset() -> void:
	CurrencyManager.reset()
	PrestigeManager.deserialize({})


func _make_board_manager() -> BoardManager:
	var bm := BoardManager.new()
	var gold_board := PlinkoBoard.new()
	gold_board.board_type = Enums.BoardType.GOLD
	gold_board.coin_queue = CoinQueue.new()
	bm._boards.append(gold_board)
	return bm


# --- Test Cases ---

func test_currency_changed_does_not_trigger_prestige() -> void:
	print("test_currency_changed_does_not_trigger_prestige")
	_reset()
	# Precondition: orange board has never been prestiged
	assert_true(PrestigeManager.can_prestige(Enums.BoardType.ORANGE),
		"precondition: can_prestige(ORANGE) should be true")

	var bm := _make_board_manager()
	# Simulate earning raw orange currency (e.g. from deserialize or coin landing)
	bm._on_currency_changed(Enums.CurrencyType.RAW_ORANGE, 5, 100)

	# The key assertion: prestige state should NOT be set by BoardManager
	assert_true(PrestigeManager.can_prestige(Enums.BoardType.ORANGE),
		"BoardManager must not consume prestige — PrestigeAnimator handles it")
	bm.queue_free()


func test_currency_changed_does_not_re_trigger_after_prestige() -> void:
	print("test_currency_changed_does_not_re_trigger_after_prestige")
	_reset()
	# Simulate a completed prestige for orange
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)
	assert_true(PrestigeManager.is_board_unlocked_permanently(Enums.BoardType.ORANGE),
		"precondition: orange should be permanently unlocked")

	var bm := _make_board_manager()
	# Pre-add an orange board so unlock_board finds the duplicate and returns
	# (avoids _spawn_board which needs a real scene tree)
	var orange_board := PlinkoBoard.new()
	orange_board.board_type = Enums.BoardType.ORANGE
	orange_board.coin_queue = CoinQueue.new()
	bm._boards.append(orange_board)

	bm._on_currency_changed(Enums.CurrencyType.RAW_ORANGE, 5, 100)

	# Prestige state should be unchanged (still permanently unlocked, not re-triggered)
	assert_true(PrestigeManager.is_board_unlocked_permanently(Enums.BoardType.ORANGE),
		"orange should remain permanently unlocked")
	bm.queue_free()


func test_will_trigger_prestige_true_for_raw_currency() -> void:
	print("test_will_trigger_prestige_true_for_raw_currency")
	_reset()
	var board := PlinkoBoard.new()
	board.board_type = Enums.BoardType.GOLD
	assert_true(board._will_trigger_prestige(Enums.CurrencyType.RAW_ORANGE),
		"RAW_ORANGE should trigger prestige when orange not yet prestiged")
	board.free()


func test_will_trigger_prestige_false_after_prestige() -> void:
	print("test_will_trigger_prestige_false_after_prestige")
	_reset()
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)
	var board := PlinkoBoard.new()
	board.board_type = Enums.BoardType.GOLD
	assert_false(board._will_trigger_prestige(Enums.CurrencyType.RAW_ORANGE),
		"RAW_ORANGE should not trigger prestige after orange already prestiged")
	board.free()
