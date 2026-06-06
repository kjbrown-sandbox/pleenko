extends "res://test/test_base.gd"

## Prestige trigger tests — run with:
##   godot --headless --scene res://test/test_prestige_trigger.tscn
##
## Single-currency model: prestige is no longer keyed off earning a raw
## currency. Instead a coin that brings the board's PRIMARY currency to the
## final threshold (LevelManager.TIER_THRESHOLDS[-1] == 500) "completes" the
## board. The FIRST completion (next board still prestige-able) routes to
## prestige; a non-primary bucket or a balance still short of 500 does not.
##
## These tests exercise the pure completion predicates on a bare PlinkoBoard:
##   _coin_completes_board / _will_trigger_prestige_completion.


func _run_tests() -> void:
	print("\n=== Prestige Trigger Tests ===\n")

	test_currency_changed_does_not_trigger_prestige()
	test_currency_changed_does_not_re_trigger_after_prestige()

	test_completes_board_below_threshold_false()
	test_completes_board_at_threshold_true()
	test_completes_board_already_at_cap_false()
	test_completes_board_non_primary_bucket_false()

	test_will_trigger_prestige_true_on_completion()
	test_will_trigger_prestige_false_after_prestige()
	test_will_trigger_prestige_false_below_threshold()
	test_will_trigger_prestige_false_on_last_tier()


func _reset() -> void:
	CurrencyManager.reset()
	PrestigeManager.deserialize({})


const THRESHOLD := 500  # LevelManager.TIER_THRESHOLDS[-1]


## Bare gold board with a minimal Buckets container so _get_bucket_index works.
## Returns [board, bucket] — the bucket is value `bucket_value`, primary currency
## (gold) unless `currency` is overridden.
func _make_board_and_bucket(bucket_value: int, currency: int = Enums.CurrencyType.GOLD_COIN) -> Array:
	var board := PlinkoBoard.new()
	board.board_type = Enums.BoardType.GOLD
	var container := Node3D.new()
	board.buckets_container = container
	var bucket := Bucket.new()
	bucket.currency_type = currency
	bucket.value = bucket_value
	container.add_child(bucket)
	return [board, bucket]


func _make_coin() -> Coin:
	var coin := Coin.new()
	coin.coin_type = Enums.CurrencyType.GOLD_COIN
	coin.multiplier = 1.0
	return coin


func _free_board(board: PlinkoBoard) -> void:
	board.buckets_container.free()
	board.free()


func _make_board_manager() -> BoardManager:
	var bm := BoardManager.new()
	var gold_board := PlinkoBoard.new()
	gold_board.board_type = Enums.BoardType.GOLD
	gold_board.coin_queue = CoinQueue.new()
	bm._boards.append(gold_board)
	return bm


# --- BoardManager no longer auto-triggers prestige on currency change ---

func test_currency_changed_does_not_trigger_prestige() -> void:
	print("test_currency_changed_does_not_trigger_prestige")
	_reset()
	assert_true(PrestigeManager.can_prestige(Enums.BoardType.ORANGE),
		"precondition: can_prestige(ORANGE) should be true")

	var bm := _make_board_manager()
	# Earning ANY currency must not consume prestige — that is now driven by the
	# board-completion predicate on the coin path, not BoardManager.
	bm._on_currency_changed(Enums.CurrencyType.GOLD_COIN, THRESHOLD, 1000)

	assert_true(PrestigeManager.can_prestige(Enums.BoardType.ORANGE),
		"BoardManager must not consume prestige on currency change")
	bm.queue_free()


func test_currency_changed_does_not_re_trigger_after_prestige() -> void:
	print("test_currency_changed_does_not_re_trigger_after_prestige")
	_reset()
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)
	assert_true(PrestigeManager.is_board_unlocked_permanently(Enums.BoardType.ORANGE),
		"precondition: orange should be permanently unlocked")

	var bm := _make_board_manager()
	bm._on_currency_changed(Enums.CurrencyType.GOLD_COIN, THRESHOLD, 1000)

	assert_true(PrestigeManager.is_board_unlocked_permanently(Enums.BoardType.ORANGE),
		"orange should remain permanently unlocked")
	bm.queue_free()


# --- _coin_completes_board truth table ---

func test_completes_board_below_threshold_false() -> void:
	print("test_completes_board_below_threshold_false")
	_reset()
	# Balance 100, bucket adds 50 → 150 < 500.
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 100)
	var pair := _make_board_and_bucket(50)
	var board: PlinkoBoard = pair[0]
	var coin := _make_coin()
	assert_false(board._coin_completes_board(coin, pair[1]),
		"150 < 500 → does not complete the board")
	coin.free()
	_free_board(board)


func test_completes_board_at_threshold_true() -> void:
	print("test_completes_board_at_threshold_true")
	_reset()
	# Balance 490, bucket adds 10 → exactly 500.
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 490)
	var pair := _make_board_and_bucket(10)
	var board: PlinkoBoard = pair[0]
	var coin := _make_coin()
	assert_true(board._coin_completes_board(coin, pair[1]),
		"490 + 10 == 500 → completes the board")
	coin.free()
	_free_board(board)


func test_completes_board_already_at_cap_false() -> void:
	print("test_completes_board_already_at_cap_false")
	_reset()
	# Already at 500 — completion is a one-shot crossing, not a re-fire.
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 500)
	var pair := _make_board_and_bucket(10)
	var board: PlinkoBoard = pair[0]
	var coin := _make_coin()
	assert_false(board._coin_completes_board(coin, pair[1]),
		"already >= 500 → completion does not re-fire")
	coin.free()
	_free_board(board)


func test_completes_board_non_primary_bucket_false() -> void:
	print("test_completes_board_non_primary_bucket_false")
	_reset()
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 490)
	# Bucket earns a NON-primary currency (raw orange) — can never complete gold.
	var pair := _make_board_and_bucket(100, Enums.CurrencyType.RAW_ORANGE)
	var board: PlinkoBoard = pair[0]
	var coin := _make_coin()
	assert_false(board._coin_completes_board(coin, pair[1]),
		"non-primary bucket never completes the board")
	coin.free()
	_free_board(board)


# --- _will_trigger_prestige_completion ---

func test_will_trigger_prestige_true_on_completion() -> void:
	print("test_will_trigger_prestige_true_on_completion")
	_reset()
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 490)
	var pair := _make_board_and_bucket(10)
	var board: PlinkoBoard = pair[0]
	var coin := _make_coin()
	assert_true(board._will_trigger_prestige_completion(coin, pair[1]),
		"completing the board pre-prestige triggers prestige")
	coin.free()
	_free_board(board)


func test_will_trigger_prestige_false_after_prestige() -> void:
	print("test_will_trigger_prestige_false_after_prestige")
	_reset()
	PrestigeManager.claim_prestige(Enums.BoardType.ORANGE)  # next board (orange) already prestiged
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 490)
	var pair := _make_board_and_bucket(10)
	var board: PlinkoBoard = pair[0]
	var coin := _make_coin()
	assert_false(board._will_trigger_prestige_completion(coin, pair[1]),
		"after prestige a completion routes to the cap-raise beat, not prestige")
	coin.free()
	_free_board(board)


func test_will_trigger_prestige_false_below_threshold() -> void:
	print("test_will_trigger_prestige_false_below_threshold")
	_reset()
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 100)
	var pair := _make_board_and_bucket(10)
	var board: PlinkoBoard = pair[0]
	var coin := _make_coin()
	assert_false(board._will_trigger_prestige_completion(coin, pair[1]),
		"a coin that does not cross 500 never triggers prestige")
	coin.free()
	_free_board(board)


func test_will_trigger_prestige_false_on_last_tier() -> void:
	print("test_will_trigger_prestige_false_on_last_tier")
	_reset()
	# The last tier has no next board → completion can't trigger a new prestige.
	var last := TierRegistry.get_tier_by_index(TierRegistry.get_tier_count() - 1)
	CurrencyManager.add(last.primary_currency, 490)
	var board := PlinkoBoard.new()
	board.board_type = last.board_type
	var container := Node3D.new()
	board.buckets_container = container
	var bucket := Bucket.new()
	bucket.currency_type = last.primary_currency
	bucket.value = 10
	container.add_child(bucket)
	var coin := _make_coin()
	assert_false(board._will_trigger_prestige_completion(coin, bucket),
		"last tier has no next board → no prestige")
	coin.free()
	container.free()
	board.free()
