extends "res://test/test_base.gd"

## Cap-raise reveal tests — run with:
##   godot --headless --scene res://test/test_cap_raise_reveal.tscn
##
## Single-currency model: the cap-raise reveal fires on the SECOND board
## completion — a coin brings the board's PRIMARY currency to >= 500 (the final
## level threshold) when the next board is ALREADY prestiged (so prestige owns
## the 1st completion, the reveal owns the 2nd) and the board's cap raises are
## not yet available. Covers the trigger predicate
## PlinkoBoard._will_reveal_cap_raise_completion (truth table + mutual exclusion
## with prestige) and the CoinValues / UpgradeSection suppression handshake —
## including the anti-soft-lock guarantee that an interrupted reveal still leaves
## every "+" button visible.


func _run_tests() -> void:
	print("\n=== Cap-Raise Reveal Tests ===\n")

	test_reveal_true_post_prestige()
	test_reveal_false_before_prestige()
	test_reveal_false_when_cap_already_available()
	test_reveal_false_below_threshold()
	test_reveal_false_for_non_primary_bucket()
	test_reveal_false_when_disabled()
	test_prestige_and_cap_raise_mutually_exclusive()

	await test_currency_cap_button_suppressed_during_reveal()
	await test_currency_cap_button_revealed_by_target_callable()
	await test_currency_cap_button_shows_normally_without_reveal()
	test_delayed_currency_bar_hidden_then_revealed()
	await test_upgrade_section_handshake()
	await test_partial_reveal_still_force_shows_all()


# --- Helpers ---

const THRESHOLD := 500  # LevelManager.TIER_THRESHOLDS[-1]


func _reset() -> void:
	PrestigeManager.deserialize({})            # clear prestige counts
	UpgradeManager.reset()                     # _cap_raise_available all false
	CurrencyManager.reset()
	ThemeProvider.theme.cap_raise_reveal_enabled = true


func _make_gold_board() -> PlinkoBoard:
	var board := PlinkoBoard.new()
	board.board_type = Enums.BoardType.GOLD
	board.buckets_container = Node3D.new()
	return board


func _free_gold_board(board: PlinkoBoard) -> void:
	if is_instance_valid(board.buckets_container):
		board.buckets_container.free()
	board.free()


## A gold-primary bucket worth `value`, parented to the board's container so
## _get_bucket_index resolves. Returns the bucket.
func _add_gold_bucket(board: PlinkoBoard, value: int) -> Bucket:
	var bucket := Bucket.new()
	bucket.currency_type = Enums.CurrencyType.GOLD_COIN
	bucket.value = value
	board.buckets_container.add_child(bucket)
	return bucket


func _make_coin() -> Coin:
	var coin := Coin.new()
	coin.coin_type = Enums.CurrencyType.GOLD_COIN
	coin.multiplier = 1.0
	return coin


## Seeds gold balance to 490 so a 10-value bucket completes the board (490+10=500).
func _seed_near_completion() -> void:
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 490)


func _make_board_manager(board: PlinkoBoard) -> BoardManager:
	var bm := BoardManager.new()
	bm._boards.append(board)
	return bm


## Board manager with BOTH gold and orange boards — orange being present makes
## CoinValues._currency_bars_revealed() true so the currency bars are built.
func _make_board_manager_with_orange(board: PlinkoBoard) -> BoardManager:
	var bm := BoardManager.new()
	bm._boards.append(board)
	var orange := PlinkoBoard.new()
	orange.board_type = Enums.BoardType.ORANGE
	bm._boards.append(orange)
	return bm


func _make_coin_values(bm: BoardManager) -> VBoxContainer:
	var cv := VBoxContainer.new()
	cv.set_script(preload("res://entities/main/coin_values.gd"))
	add_child(cv)
	cv.setup(bm)
	return cv


# --- _will_reveal_cap_raise_completion truth table ---

func test_reveal_true_post_prestige() -> void:
	print("test_reveal_true_post_prestige")
	_reset()
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)  # gold's next board already prestiged
	_seed_near_completion()
	var board := _make_gold_board()
	var bucket := _add_gold_bucket(board, 10)
	assert_true(board._will_reveal_cap_raise_completion(_make_coin(), bucket),
		"post-prestige completion, cap not yet available → reveal triggers")
	_free_gold_board(board)


func test_reveal_false_before_prestige() -> void:
	print("test_reveal_false_before_prestige")
	_reset()
	_seed_near_completion()
	var board := _make_gold_board()
	var bucket := _add_gold_bucket(board, 10)
	# can_prestige(ORANGE) is true → this completion triggers PRESTIGE, not a reveal.
	assert_false(board._will_reveal_cap_raise_completion(_make_coin(), bucket),
		"before prestige the reveal must not trigger (prestige owns this coin)")
	_free_gold_board(board)


func test_reveal_false_when_cap_already_available() -> void:
	print("test_reveal_false_when_cap_already_available")
	_reset()
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)
	UpgradeManager._cap_raise_available[Enums.BoardType.GOLD] = true  # buttons already exist
	_seed_near_completion()
	var board := _make_gold_board()
	var bucket := _add_gold_bucket(board, 10)
	assert_false(board._will_reveal_cap_raise_completion(_make_coin(), bucket),
		"cap raises already available → one-time reveal does not replay")
	_free_gold_board(board)


func test_reveal_false_below_threshold() -> void:
	print("test_reveal_false_below_threshold")
	_reset()
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 100)  # 100 + 10 = 110 < 500
	var board := _make_gold_board()
	var bucket := _add_gold_bucket(board, 10)
	assert_false(board._will_reveal_cap_raise_completion(_make_coin(), bucket),
		"a coin that does not cross 500 never reveals the caps")
	_free_gold_board(board)


func test_reveal_false_for_non_primary_bucket() -> void:
	print("test_reveal_false_for_non_primary_bucket")
	_reset()
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)
	_seed_near_completion()
	var board := _make_gold_board()
	# Bucket earns a non-primary currency → can never complete the gold board.
	var bucket := Bucket.new()
	bucket.currency_type = Enums.CurrencyType.RAW_ORANGE
	bucket.value = 100
	board.buckets_container.add_child(bucket)
	assert_false(board._will_reveal_cap_raise_completion(_make_coin(), bucket),
		"a non-primary bucket never triggers the cap-raise reveal")
	_free_gold_board(board)


func test_reveal_false_when_disabled() -> void:
	print("test_reveal_false_when_disabled")
	_reset()
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)
	ThemeProvider.theme.cap_raise_reveal_enabled = false
	_seed_near_completion()
	var board := _make_gold_board()
	var bucket := _add_gold_bucket(board, 10)
	assert_false(board._will_reveal_cap_raise_completion(_make_coin(), bucket),
		"master theme toggle off → no reveal")
	_free_gold_board(board)
	ThemeProvider.theme.cap_raise_reveal_enabled = true


func test_prestige_and_cap_raise_mutually_exclusive() -> void:
	print("test_prestige_and_cap_raise_mutually_exclusive")
	_reset()
	_seed_near_completion()
	var board := _make_gold_board()
	var bucket := _add_gold_bucket(board, 10)
	var coin := _make_coin()
	# Before prestige: prestige path owns the completion, reveal does not.
	assert_true(board._will_trigger_prestige_completion(coin, bucket),
		"before prestige: _will_trigger_prestige_completion true")
	assert_false(board._will_reveal_cap_raise_completion(coin, bucket),
		"before prestige: _will_reveal_cap_raise_completion false")
	# After prestige: reveal path owns the completion, prestige does not.
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)
	assert_false(board._will_trigger_prestige_completion(coin, bucket),
		"after prestige: _will_trigger_prestige_completion false")
	assert_true(board._will_reveal_cap_raise_completion(coin, bucket),
		"after prestige: _will_reveal_cap_raise_completion true")
	coin.free()
	_free_gold_board(board)


# --- CoinValues suppression handshake ---

func test_currency_cap_button_suppressed_during_reveal() -> void:
	print("test_currency_cap_button_suppressed_during_reveal")
	_reset()
	var bm := _make_board_manager_with_orange(_make_gold_board())
	var cv := _make_coin_values(bm)
	UpgradeManager._cap_raise_available[Enums.BoardType.GOLD] = true

	cv.begin_cap_raise_reveal(Enums.BoardType.GOLD)
	cv._on_cap_raise_unlocked(Enums.BoardType.GOLD)
	# RefinedBaselineButton applies its +/- visibility on a deferred idle frame
	# (_queue_apply), so wait one frame before reading plus_button.visible.
	await get_tree().process_frame

	var bar = cv._bars[Enums.CurrencyType.GOLD_COIN]
	assert_false(bar.plus_button.visible,
		"during a reveal the cap '+' stays hidden for the animator")
	assert_true(cv.get_pending_currency_cap_targets().size() >= 1,
		"the hidden cap button is reported as a pending reveal target")

	# Anti-soft-lock: ending the reveal without ever revealing must still show it.
	cv.end_cap_raise_reveal()
	await get_tree().process_frame
	assert_true(bar.plus_button.visible,
		"end_cap_raise_reveal force-shows the button — never stranded hidden")

	cv.queue_free()
	bm.queue_free()


func test_currency_cap_button_revealed_by_target_callable() -> void:
	print("test_currency_cap_button_revealed_by_target_callable")
	_reset()
	var bm := _make_board_manager_with_orange(_make_gold_board())
	var cv := _make_coin_values(bm)
	UpgradeManager._cap_raise_available[Enums.BoardType.GOLD] = true

	cv.begin_cap_raise_reveal(Enums.BoardType.GOLD)
	cv._on_cap_raise_unlocked(Enums.BoardType.GOLD)
	await get_tree().process_frame

	var targets: Array[Dictionary] = cv.get_pending_currency_cap_targets()
	assert_true(targets.size() >= 1, "precondition: a pending target exists")
	var reveal: Callable = targets[0]["reveal"]
	reveal.call()
	await get_tree().process_frame
	var plus_button: Control = targets[0]["plus_button"]
	assert_true(plus_button.visible, "the target's reveal callable shows its '+' button")

	cv.end_cap_raise_reveal()
	cv.queue_free()
	bm.queue_free()


func test_currency_cap_button_shows_normally_without_reveal() -> void:
	print("test_currency_cap_button_shows_normally_without_reveal")
	_reset()
	var bm := _make_board_manager_with_orange(_make_gold_board())
	var cv := _make_coin_values(bm)
	UpgradeManager._cap_raise_available[Enums.BoardType.GOLD] = true

	# No begin_cap_raise_reveal — the normal path must be untouched.
	cv._on_cap_raise_unlocked(Enums.BoardType.GOLD)
	await get_tree().process_frame
	var bar = cv._bars[Enums.CurrencyType.GOLD_COIN]
	assert_true(bar.plus_button.visible,
		"without a reveal active the cap '+' appears immediately, as before")

	cv.queue_free()
	bm.queue_free()


func test_delayed_currency_bar_hidden_then_revealed() -> void:
	print("test_delayed_currency_bar_hidden_then_revealed")
	_reset()
	# Real sequence: the reveal begins on the GOLD board BEFORE the orange board
	# is unlocked (so the orange currency bar does not exist yet). The orange
	# board is then unlocked mid-reveal; CoinValues rebuilds and creates the new
	# bar HIDDEN (the delayed currency), to be faded in later by the animator.
	var gold := _make_gold_board()
	var bm := _make_board_manager(gold)  # gold only — bars stay hidden initially
	var cv := _make_coin_values(bm)

	cv.begin_cap_raise_reveal(Enums.BoardType.GOLD)
	# Single-currency model: the delayed bar is the next board's PRIMARY currency
	# (orange). Earn some so its bar would otherwise appear the instant it shows.
	CurrencyManager.add(Enums.CurrencyType.ORANGE_COIN, 5)
	# Unlock the orange board mid-reveal, the way next_board_unlock_requested does.
	var orange := PlinkoBoard.new()
	orange.board_type = Enums.BoardType.ORANGE
	bm._boards.append(orange)
	bm.board_unlocked.emit(Enums.BoardType.ORANGE)  # CoinValues listens → rebuild

	var orange_bar = cv._bars.get(Enums.CurrencyType.ORANGE_COIN)
	assert_true(orange_bar != null, "precondition: orange currency bar was created")
	assert_false(orange_bar.visible,
		"during a reveal the new currency bar starts hidden")

	cv.reveal_delayed_currency_bar()
	assert_true(orange_bar.visible,
		"reveal_delayed_currency_bar fades the new bar into view")

	cv.queue_free()
	orange.free()
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
	# RefinedBaselineButton applies +/- visibility on a deferred idle frame.
	await get_tree().process_frame

	var row: UpgradeRow = us.get_upgrade_row(Enums.UpgradeType.ADD_ROW)
	assert_true(row != null, "precondition: ADD_ROW row spawned")
	assert_false(row.bar.plus_button.visible,
		"during a reveal the board upgrade's cap '+' stays hidden")
	assert_true(us.get_pending_cap_raise_targets().size() >= 1,
		"the hidden cap button is reported as a pending reveal target")

	us.end_cap_raise_reveal()
	await get_tree().process_frame
	assert_true(row.bar.plus_button.visible,
		"end_cap_raise_reveal force-shows the board upgrade's '+' button")

	us.queue_free()
	_free_gold_board(board)
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
	await get_tree().process_frame

	var targets: Array[Dictionary] = us.get_pending_cap_raise_targets()
	assert_true(targets.size() >= 2, "precondition: two board upgrade cap targets")
	# Reveal only the first — simulate the cinematic being interrupted partway.
	targets[0]["reveal"].call()
	us.end_cap_raise_reveal()
	await get_tree().process_frame

	var add_row: UpgradeRow = us.get_upgrade_row(Enums.UpgradeType.ADD_ROW)
	var bucket_row: UpgradeRow = us.get_upgrade_row(Enums.UpgradeType.BUCKET_VALUE)
	assert_true(add_row.bar.plus_button.visible and bucket_row.bar.plus_button.visible,
		"end_cap_raise_reveal force-shows every cap button — revealed AND un-revealed")

	us.queue_free()
	_free_gold_board(board)
	UpgradeManager.reset()
