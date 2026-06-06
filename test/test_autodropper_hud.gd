extends "res://test/test_base.gd"

## Autodropper HUD display tests — run with:
##   godot --headless --scene res://test/test_autodropper_hud.tscn
##
## Verifies that CoinValues shows/hides universal upgrade rows based on
## autodropper unlock state and provides target accessors for sparkles.


func _run_tests() -> void:
	print("\n=== Autodropper HUD Tests ===\n")

	test_currencies_header_gated_until_orange_unlocked()
	test_headers_with_autodroppers()
	test_upgrade_row_created_for_autodropper()
	test_get_upgrade_row_returns_null_when_missing()
	test_rebuild_on_unlock()
	test_advanced_autodropper_row()


# --- Helpers ---

func _make_board_manager() -> BoardManager:
	var bm := BoardManager.new()
	var gold_board := PlinkoBoard.new()
	gold_board.board_type = Enums.BoardType.GOLD
	gold_board.coin_queue = CoinQueue.new()
	bm._boards.append(gold_board)
	return bm


## Single-currency model: the "Currencies" section is hidden until the orange
## board is unlocked (until then the level bar IS the currency display). Adds an
## orange board so CoinValues._currency_bars_revealed() is true.
func _add_orange_board(bm: BoardManager) -> void:
	var orange_board := PlinkoBoard.new()
	orange_board.board_type = Enums.BoardType.ORANGE
	orange_board.coin_queue = CoinQueue.new()
	bm._boards.append(orange_board)


func _has_label(cv: VBoxContainer, text: String) -> bool:
	for child in cv.get_children():
		if child is Label and child.text == text:
			return true
	return false


func _make_coin_values(bm: BoardManager) -> VBoxContainer:
	var cv := VBoxContainer.new()
	cv.set_script(preload("res://entities/main/coin_values.gd"))
	add_child(cv)
	cv.setup(bm)
	return cv


# --- Tests ---

## Single-currency model: the Currencies section is gated on the orange board
## being unlocked. With gold only it is hidden; once orange is unlocked it shows.
func test_currencies_header_gated_until_orange_unlocked() -> void:
	print("test_currencies_header_gated_until_orange_unlocked")
	UpgradeManager.reset()

	# Gold only → no Currencies header (the level bar is the currency display).
	var bm_gold := _make_board_manager()
	var cv_gold := _make_coin_values(bm_gold)
	assert_false(_has_label(cv_gold, "Currencies"),
		"Currencies header hidden before the orange board is unlocked")
	assert_equal(cv_gold._upgrade_rows.size(), 0, "no upgrade rows without autodroppers")
	cv_gold.queue_free()
	bm_gold.queue_free()

	# Orange unlocked → Currencies header appears.
	var bm_orange := _make_board_manager()
	_add_orange_board(bm_orange)
	var cv_orange := _make_coin_values(bm_orange)
	assert_true(_has_label(cv_orange, "Currencies"),
		"Currencies header shown once the orange board is unlocked")
	cv_orange.queue_free()
	bm_orange.queue_free()


func test_headers_with_autodroppers() -> void:
	print("test_headers_with_autodroppers")
	var bm := _make_board_manager()
	_add_orange_board(bm)  # orange unlocked so the Currencies section is revealed
	# Unlock the autodropper upgrade so CoinValues sees it
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.AUTODROPPER)

	var cv := _make_coin_values(bm)

	assert_true(_has_label(cv, "Currencies"), "'Currencies' header present")
	assert_true(_has_label(cv, "Universal upgrades"), "'Universal upgrades' header present")

	cv.queue_free()
	bm.queue_free()
	# Reset unlock state
	UpgradeManager.reset()


func test_upgrade_row_created_for_autodropper() -> void:
	print("test_upgrade_row_created_for_autodropper")
	var bm := _make_board_manager()
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.AUTODROPPER)

	var cv := _make_coin_values(bm)

	assert_true(cv._upgrade_rows.has(Enums.UpgradeType.AUTODROPPER), "autodropper row exists")
	var row: UpgradeRow = cv._upgrade_rows[Enums.UpgradeType.AUTODROPPER]
	assert_true(row != null, "row is not null")

	cv.queue_free()
	bm.queue_free()
	UpgradeManager.reset()


func test_get_upgrade_row_returns_null_when_missing() -> void:
	print("test_get_upgrade_row_returns_null_when_missing")
	UpgradeManager.reset()
	var bm := _make_board_manager()
	var cv := _make_coin_values(bm)

	var row = cv.get_upgrade_row(Enums.UpgradeType.AUTODROPPER)
	assert_true(row == null, "get_upgrade_row returns null when not unlocked")

	cv.queue_free()
	bm.queue_free()


func test_rebuild_on_unlock() -> void:
	print("test_rebuild_on_unlock")
	UpgradeManager.reset()
	var bm := _make_board_manager()
	var cv := _make_coin_values(bm)

	assert_false(cv._upgrade_rows.has(Enums.UpgradeType.AUTODROPPER), "no row before unlock")

	# Simulate unlock signal
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.AUTODROPPER)

	assert_true(cv._upgrade_rows.has(Enums.UpgradeType.AUTODROPPER), "row created after unlock")

	cv.queue_free()
	bm.queue_free()
	UpgradeManager.reset()


func test_advanced_autodropper_row() -> void:
	print("test_advanced_autodropper_row")
	var bm := _make_board_manager()
	# Add orange board for advanced autodropper
	var orange_board := PlinkoBoard.new()
	orange_board.board_type = Enums.BoardType.ORANGE
	orange_board.coin_queue = CoinQueue.new()
	bm._boards.append(orange_board)

	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.AUTODROPPER)
	UpgradeManager.unlock(Enums.BoardType.ORANGE, Enums.UpgradeType.ADVANCED_AUTODROPPER)

	var cv := _make_coin_values(bm)

	assert_true(cv._upgrade_rows.has(Enums.UpgradeType.AUTODROPPER), "normal autodropper row exists")
	assert_true(cv._upgrade_rows.has(Enums.UpgradeType.ADVANCED_AUTODROPPER), "advanced autodropper row exists")
	assert_equal(cv._upgrade_rows.size(), 2, "exactly two upgrade rows")

	cv.queue_free()
	bm.queue_free()
	UpgradeManager.reset()
