extends "res://test/test_base.gd"

## Cap-raise reveal tests — run with:
##   godot --headless --scene res://test/test_cap_raise_reveal.tscn
##
## Covers the trigger predicate PlinkoBoard._will_reveal_cap_raise (truth table +
## mutual exclusion with prestige) and the CoinValues / UpgradeSection
## suppression handshake — including the anti-soft-lock guarantee that an
## interrupted reveal still leaves every "+" button visible.


func _run_tests() -> void:
	print("\n=== Cap-Raise Reveal Tests ===\n")

	test_reveal_true_post_prestige()
	test_reveal_false_before_prestige()
	test_reveal_false_when_cap_already_available()
	test_reveal_false_for_non_raw_currency()
	test_reveal_false_for_wrong_board()
	test_reveal_false_when_disabled()
	test_prestige_and_cap_raise_mutually_exclusive()

	test_currency_cap_button_suppressed_during_reveal()
	test_currency_cap_button_revealed_by_target_callable()
	test_currency_cap_button_shows_normally_without_reveal()
	test_delayed_currency_bar_hidden_then_revealed()
	test_upgrade_section_handshake()
	test_partial_reveal_still_force_shows_all()


# --- Helpers ---

func _reset() -> void:
	PrestigeManager.deserialize({})            # clear prestige counts
	UpgradeManager.reset()                     # _cap_raise_available all false
	ThemeProvider.theme.cap_raise_reveal_enabled = true


func _make_gold_board() -> PlinkoBoard:
	var board := PlinkoBoard.new()
	board.board_type = Enums.BoardType.GOLD
	return board


func _make_board_manager(board: PlinkoBoard) -> BoardManager:
	var bm := BoardManager.new()
	bm._boards.append(board)
	return bm


func _make_coin_values(bm: BoardManager) -> VBoxContainer:
	var cv := VBoxContainer.new()
	cv.set_script(preload("res://entities/main/coin_values.gd"))
	add_child(cv)
	cv.setup(bm)
	return cv


# --- _will_reveal_cap_raise truth table ---

func test_reveal_true_post_prestige() -> void:
	print("test_reveal_true_post_prestige")
	_reset()
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)  # gold tier already prestiged
	var board := _make_gold_board()
	assert_true(board._will_reveal_cap_raise(Enums.CurrencyType.RAW_ORANGE),
		"post-prestige, cap not yet available → reveal triggers")
	board.free()


func test_reveal_false_before_prestige() -> void:
	print("test_reveal_false_before_prestige")
	_reset()
	var board := _make_gold_board()
	# can_prestige(ORANGE) is true → this raw-orange coin triggers PRESTIGE, not a reveal.
	assert_false(board._will_reveal_cap_raise(Enums.CurrencyType.RAW_ORANGE),
		"before prestige the reveal must not trigger (prestige owns this coin)")
	board.free()


func test_reveal_false_when_cap_already_available() -> void:
	print("test_reveal_false_when_cap_already_available")
	_reset()
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)
	UpgradeManager._cap_raise_available[Enums.BoardType.GOLD] = true  # buttons already exist
	var board := _make_gold_board()
	assert_false(board._will_reveal_cap_raise(Enums.CurrencyType.RAW_ORANGE),
		"cap raises already available → one-time reveal does not replay")
	board.free()


func test_reveal_false_for_non_raw_currency() -> void:
	print("test_reveal_false_for_non_raw_currency")
	_reset()
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)
	var board := _make_gold_board()
	assert_false(board._will_reveal_cap_raise(Enums.CurrencyType.GOLD_COIN),
		"a non-raw currency never triggers the cap-raise reveal")
	board.free()


func test_reveal_false_for_wrong_board() -> void:
	print("test_reveal_false_for_wrong_board")
	_reset()
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)
	var board := PlinkoBoard.new()
	board.board_type = Enums.BoardType.ORANGE  # raw-orange's cap-raise board is GOLD, not this
	assert_false(board._will_reveal_cap_raise(Enums.CurrencyType.RAW_ORANGE),
		"reveal only fires when the cap-raise board is the board the coin is on")
	board.free()


func test_reveal_false_when_disabled() -> void:
	print("test_reveal_false_when_disabled")
	_reset()
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)
	ThemeProvider.theme.cap_raise_reveal_enabled = false
	var board := _make_gold_board()
	assert_false(board._will_reveal_cap_raise(Enums.CurrencyType.RAW_ORANGE),
		"master theme toggle off → no reveal")
	board.free()
	ThemeProvider.theme.cap_raise_reveal_enabled = true


func test_prestige_and_cap_raise_mutually_exclusive() -> void:
	print("test_prestige_and_cap_raise_mutually_exclusive")
	_reset()
	var board := _make_gold_board()
	# Before prestige: prestige path owns the coin, reveal does not.
	assert_true(board._will_trigger_prestige(Enums.CurrencyType.RAW_ORANGE),
		"before prestige: _will_trigger_prestige true")
	assert_false(board._will_reveal_cap_raise(Enums.CurrencyType.RAW_ORANGE),
		"before prestige: _will_reveal_cap_raise false")
	# After prestige: reveal path owns the coin, prestige does not.
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)
	assert_false(board._will_trigger_prestige(Enums.CurrencyType.RAW_ORANGE),
		"after prestige: _will_trigger_prestige false")
	assert_true(board._will_reveal_cap_raise(Enums.CurrencyType.RAW_ORANGE),
		"after prestige: _will_reveal_cap_raise true")
	board.free()


# --- CoinValues suppression handshake ---

func test_currency_cap_button_suppressed_during_reveal() -> void:
	print("test_currency_cap_button_suppressed_during_reveal")
	_reset()
	var bm := _make_board_manager(_make_gold_board())
	var cv := _make_coin_values(bm)
	UpgradeManager._cap_raise_available[Enums.BoardType.GOLD] = true

	cv.begin_cap_raise_reveal(Enums.BoardType.GOLD)
	cv._on_cap_raise_unlocked(Enums.BoardType.GOLD)

	var bar = cv._bars[Enums.CurrencyType.GOLD_COIN]
	assert_false(bar.plus_button.visible,
		"during a reveal the cap '+' stays hidden for the animator")
	assert_true(cv.get_pending_currency_cap_targets().size() >= 1,
		"the hidden cap button is reported as a pending reveal target")

	# Anti-soft-lock: ending the reveal without ever revealing must still show it.
	cv.end_cap_raise_reveal()
	assert_true(bar.plus_button.visible,
		"end_cap_raise_reveal force-shows the button — never stranded hidden")

	cv.queue_free()
	bm.queue_free()


func test_currency_cap_button_revealed_by_target_callable() -> void:
	print("test_currency_cap_button_revealed_by_target_callable")
	_reset()
	var bm := _make_board_manager(_make_gold_board())
	var cv := _make_coin_values(bm)
	UpgradeManager._cap_raise_available[Enums.BoardType.GOLD] = true

	cv.begin_cap_raise_reveal(Enums.BoardType.GOLD)
	cv._on_cap_raise_unlocked(Enums.BoardType.GOLD)

	var targets: Array[Dictionary] = cv.get_pending_currency_cap_targets()
	assert_true(targets.size() >= 1, "precondition: a pending target exists")
	var reveal: Callable = targets[0]["reveal"]
	reveal.call()
	var plus_button: Control = targets[0]["plus_button"]
	assert_true(plus_button.visible, "the target's reveal callable shows its '+' button")

	cv.end_cap_raise_reveal()
	cv.queue_free()
	bm.queue_free()


func test_currency_cap_button_shows_normally_without_reveal() -> void:
	print("test_currency_cap_button_shows_normally_without_reveal")
	_reset()
	var bm := _make_board_manager(_make_gold_board())
	var cv := _make_coin_values(bm)
	UpgradeManager._cap_raise_available[Enums.BoardType.GOLD] = true

	# No begin_cap_raise_reveal — the normal path must be untouched.
	cv._on_cap_raise_unlocked(Enums.BoardType.GOLD)
	var bar = cv._bars[Enums.CurrencyType.GOLD_COIN]
	assert_true(bar.plus_button.visible,
		"without a reveal active the cap '+' appears immediately, as before")

	cv.queue_free()
	bm.queue_free()


func test_delayed_currency_bar_hidden_then_revealed() -> void:
	print("test_delayed_currency_bar_hidden_then_revealed")
	_reset()
	var bm := _make_board_manager(_make_gold_board())
	var cv := _make_coin_values(bm)

	cv.begin_cap_raise_reveal(Enums.BoardType.GOLD)
	# Earn raw orange — its bar would otherwise appear the instant it is earned.
	CurrencyManager.add(Enums.CurrencyType.RAW_ORANGE, 5)
	cv.refresh_visible_currencies()

	var orange_bar = cv._bars.get(Enums.CurrencyType.RAW_ORANGE)
	assert_true(orange_bar != null, "precondition: raw-orange bar was created")
	assert_false(orange_bar.visible,
		"during a reveal the new raw-currency bar starts hidden")

	cv.reveal_delayed_currency_bar()
	assert_true(orange_bar.visible,
		"reveal_delayed_currency_bar fades the new bar into view")

	cv.queue_free()
	bm.queue_free()
	CurrencyManager.reset()


# --- UpgradeSection suppression handshake ---

func test_upgrade_section_handshake() -> void:
	print("test_upgrade_section_handshake")
	_reset()
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	# Force a positive cap so _setup_cap_raise_if_needed wires the "+" button,
	# independent of the upgrade .tres data.
	UpgradeManager.get_state(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW).base_cap = 5

	var board := _make_gold_board()
	var us := preload("res://entities/plinko_board/upgrade_section.tscn").instantiate()
	add_child(us)
	us.setup(board, Enums.BoardType.GOLD)

	us.begin_cap_raise_reveal()
	UpgradeManager._cap_raise_available[Enums.BoardType.GOLD] = true
	us._on_cap_raise_unlocked(Enums.BoardType.GOLD)

	var row: UpgradeRow = us.get_upgrade_row(Enums.UpgradeType.ADD_ROW)
	assert_true(row != null, "precondition: ADD_ROW row spawned")
	assert_false(row.bar.plus_button.visible,
		"during a reveal the board upgrade's cap '+' stays hidden")
	assert_true(us.get_pending_cap_raise_targets().size() >= 1,
		"the hidden cap button is reported as a pending reveal target")

	us.end_cap_raise_reveal()
	assert_true(row.bar.plus_button.visible,
		"end_cap_raise_reveal force-shows the board upgrade's '+' button")

	us.queue_free()
	board.free()
	UpgradeManager.reset()


## Anti-soft-lock: an interrupt mid-sequence (reveal one cap, then abort) must
## still leave EVERY cap button visible — both the revealed and the un-revealed.
func test_partial_reveal_still_force_shows_all() -> void:
	print("test_partial_reveal_still_force_shows_all")
	_reset()
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE)
	UpgradeManager.get_state(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW).base_cap = 5
	UpgradeManager.get_state(Enums.BoardType.GOLD, Enums.UpgradeType.BUCKET_VALUE).base_cap = 5

	var board := _make_gold_board()
	var us := preload("res://entities/plinko_board/upgrade_section.tscn").instantiate()
	add_child(us)
	us.setup(board, Enums.BoardType.GOLD)

	us.begin_cap_raise_reveal()
	UpgradeManager._cap_raise_available[Enums.BoardType.GOLD] = true
	us._on_cap_raise_unlocked(Enums.BoardType.GOLD)

	var targets: Array[Dictionary] = us.get_pending_cap_raise_targets()
	assert_true(targets.size() >= 2, "precondition: two board upgrade cap targets")
	# Reveal only the first — simulate the cinematic being interrupted partway.
	targets[0]["reveal"].call()
	us.end_cap_raise_reveal()

	var add_row: UpgradeRow = us.get_upgrade_row(Enums.UpgradeType.ADD_ROW)
	var bucket_row: UpgradeRow = us.get_upgrade_row(Enums.UpgradeType.BUCKET_VALUE)
	assert_true(add_row.bar.plus_button.visible and bucket_row.bar.plus_button.visible,
		"end_cap_raise_reveal force-shows every cap button — revealed AND un-revealed")

	us.queue_free()
	board.free()
	UpgradeManager.reset()
