extends "res://test/test_base.gd"

## Earrings tests — run with:
##   godot --headless --scene res://test/test_earrings.tscn
##
## Covers the pure EarringGeometry table, the two board-side size decisions and
## their parity, the ADD_ROW hard cap (including its cap-raise bypass), the
## gateway/transporter payout rules, and the EarringBoard coin surface.

const SPACE := 1.0
const VS := 1.0
## Buckets that go into the test tree must be scene instances: a bare
## Bucket.new() has no MeshInstance3D / Label3D children and errors in _ready.
const BucketScene: PackedScene = preload("res://entities/bucket/bucket.tscn")
const EarringScene: PackedScene = preload("res://entities/earring_board/earring_board.tscn")
const PlinkoBoardScene: PackedScene = preload("res://entities/plinko_board/plinko_board.tscn")

## Level at which the main triangle is full (8 rows / 9 buckets) — the last
## level before growth diverts into the earrings. Derived, not typed in.
var _cap_level: int = EarringGeometry.growth_level_for(EarringGeometry.MAIN_MAX_ROWS, 0)


func _run_tests() -> void:
	print("\n=== Earrings Tests ===\n")

	# Pure geometry
	test_apex_matches_edge_bucket_x()
	test_innermost_bottom_x_walks_inward()
	test_earrings_meet_only_at_full_size()
	test_growth_table_matches_locked_spec()
	test_growth_table_boundaries()
	test_max_add_row_level_is_derived()
	test_uncapped_mode_never_grows_earrings()
	test_is_gateway_bucket()
	test_has_transporter()
	test_is_transporter_cell()

	# Board-side size decisions
	test_load_path_parity_with_growth_path()
	test_uncapped_board_grows_past_nine_buckets()
	test_level_six_save_loads_as_eight_main_six_earring()
	test_earring_growth_does_not_shift_voided_columns()

	# Hard cap
	test_add_row_refused_at_hard_cap()
	test_cap_raise_refused_at_hard_cap()
	test_hard_cap_survives_cap_raises()
	test_force_apply_honours_hard_cap()
	test_uncapped_mode_has_no_hard_cap()

	# Payout rules
	test_gateway_buckets_pay_nothing()
	test_gateway_buckets_pay_normally_before_earrings()
	test_bucket_value_upgrade_leaves_gateways_at_zero()
	test_gameplay_target_never_picks_a_gateway()
	test_earring_bucket_credits_parent_currency()
	test_transporter_pays_nothing_and_transports()

	# Coin surface
	test_coin_surface_conformance()
	test_earring_descent_terminates_in_a_bucket()
	test_earring_cell_to_world_is_parent_local()
	test_earring_scene_builds_pegs_and_buckets()
	test_earring_scene_shares_the_injected_transporter()
	test_full_board_builds_earrings_and_transporter()
	test_handoff_rewires_the_coin_without_reparenting_it()

	# Challenge wiring
	test_challenge_data_defaults_to_uncapped()
	test_offline_layout_treats_gateways_as_earring_payouts()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_board(rows: int, earrings_enabled: bool = true) -> PlinkoBoard:
	var board := PlinkoBoard.new()
	board.board_type = Enums.BoardType.GOLD
	board.num_rows = rows
	board.space_between_pegs = SPACE
	board.vertical_spacing = VS
	board.earrings_enabled = earrings_enabled
	board.buckets_container = Node3D.new()
	return board


func _free_board(board: PlinkoBoard) -> void:
	if is_instance_valid(board.buckets_container):
		board.buckets_container.free()
	board.free()


## `count` bare buckets parented to the board's container so _get_bucket_index
## and the child count resolve. Added to the test tree so their tweens work.
func _fill_buckets(board: PlinkoBoard, count: int, value: int) -> void:
	for i in count:
		var bucket := Bucket.new()
		bucket.currency_type = Enums.CurrencyType.GOLD_COIN
		bucket.value = value
		board.buckets_container.add_child(bucket)


func _make_earring(rows: int, side: int) -> EarringBoard:
	var earring := EarringBoard.new()
	earring.num_rows = rows
	earring.side = side
	earring.space_between_pegs = SPACE
	earring.vertical_spacing = VS
	earring.board_type = Enums.BoardType.GOLD
	return earring


func _make_coin() -> Coin:
	var coin := Coin.new()
	coin.coin_type = Enums.CurrencyType.GOLD_COIN
	coin.multiplier = 1.0
	return coin


# ── Pure geometry ─────────────────────────────────────────────────────────────

func test_apex_matches_edge_bucket_x() -> void:
	print("test_apex_matches_edge_bucket_x")
	# The apex must land exactly on the edge bucket build_board() places, for
	# every board size — derived from the same -s*(n-1)/2, never a literal -4s.
	for rows in [2, 4, 6, 8]:
		var num_buckets: int = EarringGeometry.buckets_for_rows(rows)
		var expected: float = -SPACE * float(num_buckets - 1) / 2.0
		assert_near(EarringGeometry.edge_bucket_x(num_buckets, SPACE), expected, 1e-5,
			"left edge bucket x at %d rows" % rows)
		assert_near(EarringGeometry.apex_x_for_side(num_buckets, SPACE,
			EarringGeometry.SIDE_LEFT), expected, 1e-5, "left apex at %d rows" % rows)
		assert_near(EarringGeometry.apex_x_for_side(num_buckets, SPACE,
			EarringGeometry.SIDE_RIGHT), -expected, 1e-5, "right apex at %d rows" % rows)


func test_innermost_bottom_x_walks_inward() -> void:
	print("test_innermost_bottom_x_walks_inward")
	var num_buckets: int = EarringGeometry.buckets_for_rows(EarringGeometry.MAIN_MAX_ROWS)
	var left_apex: float = EarringGeometry.apex_x_for_side(num_buckets, SPACE,
		EarringGeometry.SIDE_LEFT)
	var right_apex: float = EarringGeometry.apex_x_for_side(num_buckets, SPACE,
		EarringGeometry.SIDE_RIGHT)
	var full: int = EarringGeometry.max_earring_rows()

	# Each row walks the inner corner exactly half a peg-spacing toward centre.
	for r in range(1, full + 1):
		assert_near(EarringGeometry.innermost_bottom_x(left_apex, r, SPACE),
			left_apex + r * SPACE / 2.0, 1e-5, "left inner corner at %d rows" % r)
		assert_near(EarringGeometry.innermost_bottom_x(right_apex, r, SPACE),
			right_apex - r * SPACE / 2.0, 1e-5, "right inner corner at %d rows" % r)

	# It arrives at exactly 0 at the full row count, and is strictly short of it
	# (still left of centre) before that.
	assert_near(EarringGeometry.innermost_bottom_x(left_apex, full, SPACE), 0.0, 1e-5,
		"left earring reaches x = 0 at %d rows" % full)
	assert_near(EarringGeometry.innermost_bottom_x(right_apex, full, SPACE), 0.0, 1e-5,
		"right earring reaches x = 0 at %d rows" % full)
	for r in range(1, full):
		assert_true(EarringGeometry.innermost_bottom_x(left_apex, r, SPACE) < -1e-6,
			"left earring still short of centre at %d rows" % r)
		assert_true(EarringGeometry.innermost_bottom_x(right_apex, r, SPACE) > 1e-6,
			"right earring still short of centre at %d rows" % r)


func test_earrings_meet_only_at_full_size() -> void:
	print("test_earrings_meet_only_at_full_size")
	var num_buckets: int = EarringGeometry.buckets_for_rows(EarringGeometry.MAIN_MAX_ROWS)
	var full: int = EarringGeometry.max_earring_rows()
	assert_false(EarringGeometry.earrings_meet(0, num_buckets), "0 rows: no earrings, no meeting")
	for r in range(1, full):
		assert_false(EarringGeometry.earrings_meet(r, num_buckets),
			"%d rows does not meet" % r)
	assert_true(EarringGeometry.earrings_meet(full, num_buckets),
		"%d rows meets at dead centre" % full)


func test_growth_table_matches_locked_spec() -> void:
	print("test_growth_table_matches_locked_spec")
	# The locked table: level -> (main rows, buckets, earring rows).
	var table := [
		[0, 2, 3, 0],
		[1, 4, 5, 0],
		[2, 6, 7, 0],
		[3, 8, 9, 0],
		[4, 8, 9, 2],
		[5, 8, 9, 4],
		[6, 8, 9, 6],
		[7, 8, 9, 8],
	]
	for row in table:
		var level: int = row[0]
		assert_equal(EarringGeometry.main_rows_for_level(level, true), row[1],
			"level %d -> %d main rows" % [level, row[1]])
		assert_equal(EarringGeometry.buckets_for_rows(
			EarringGeometry.main_rows_for_level(level, true)), row[2],
			"level %d -> %d buckets" % [level, row[2]])
		assert_equal(EarringGeometry.earring_rows_for_level(level, true), row[3],
			"level %d -> %d earring rows" % [level, row[3]])


func test_growth_table_boundaries() -> void:
	print("test_growth_table_boundaries")
	var cap := _cap_level
	assert_equal(EarringGeometry.earring_rows_for_level(cap, true), 0,
		"at the main-board cap the earrings haven't started")
	assert_equal(EarringGeometry.earring_rows_for_level(cap + 1, true), 2, "cap+1 -> 2")
	assert_equal(EarringGeometry.earring_rows_for_level(cap + 4, true), 8, "cap+4 -> 8")
	assert_equal(EarringGeometry.earring_rows_for_level(cap + 5, true), 8,
		"cap+5 -> still 8, no overflow past the meeting point")
	assert_equal(EarringGeometry.earring_rows_for_level(cap + 20, true), 8,
		"far past the cap -> still 8")
	assert_equal(EarringGeometry.main_rows_for_level(cap + 20, true),
		EarringGeometry.MAIN_MAX_ROWS, "the main triangle never grows past its cap")


func test_max_add_row_level_is_derived() -> void:
	print("test_max_add_row_level_is_derived")
	var hard: int = EarringGeometry.max_add_row_level()
	assert_equal(hard, 7, "hard cap sits at ADD_ROW level 7")
	assert_true(EarringGeometry.earrings_meet(
		EarringGeometry.earring_rows_for_level(hard, true),
		EarringGeometry.buckets_for_rows(EarringGeometry.main_rows_for_level(hard, true))),
		"the earrings have met at the hard cap")
	assert_false(EarringGeometry.earrings_meet(
		EarringGeometry.earring_rows_for_level(hard - 1, true),
		EarringGeometry.buckets_for_rows(EarringGeometry.main_rows_for_level(hard - 1, true))),
		"they have NOT met one level below it")


func test_uncapped_mode_never_grows_earrings() -> void:
	print("test_uncapped_mode_never_grows_earrings")
	for level in range(0, 15):
		assert_equal(EarringGeometry.earring_rows_for_level(level, false), 0,
			"uncapped level %d grows no earrings" % level)
		assert_equal(EarringGeometry.main_rows_for_level(level, false), 2 + level * 2,
			"uncapped level %d grows the main triangle" % level)


func test_is_gateway_bucket() -> void:
	print("test_is_gateway_bucket")
	assert_false(EarringGeometry.is_gateway_bucket(0, 9, 0),
		"no earrings -> edge bucket is a normal bucket")
	assert_true(EarringGeometry.is_gateway_bucket(0, 9, 2), "left edge is a gateway")
	assert_true(EarringGeometry.is_gateway_bucket(8, 9, 2), "right edge is a gateway")
	assert_false(EarringGeometry.is_gateway_bucket(4, 9, 2), "centre bucket is not")
	assert_false(EarringGeometry.is_gateway_bucket(1, 9, 2), "bucket 1 is not")


func test_has_transporter() -> void:
	print("test_has_transporter")
	var nb: int = EarringGeometry.buckets_for_rows(EarringGeometry.MAIN_MAX_ROWS)
	for level in range(0, EarringGeometry.max_add_row_level()):
		assert_false(EarringGeometry.has_transporter(level, nb, true),
			"no transporter at level %d" % level)
	assert_true(EarringGeometry.has_transporter(EarringGeometry.max_add_row_level(), nb, true),
		"transporter exists once the earrings meet")
	assert_false(EarringGeometry.has_transporter(EarringGeometry.max_add_row_level(), nb, false),
		"an uncapped board never gets a transporter")


func test_is_transporter_cell() -> void:
	print("test_is_transporter_cell")
	var full: int = EarringGeometry.max_earring_rows()
	# Left earring: the inner corner is its RIGHTMOST bottom column.
	assert_true(EarringGeometry.is_transporter_cell(full, full, full, EarringGeometry.SIDE_LEFT),
		"left earring's inner corner is col == rows")
	assert_false(EarringGeometry.is_transporter_cell(full, 0, full, EarringGeometry.SIDE_LEFT),
		"left earring's outer corner is not")
	# Right earring: its LEFTMOST bottom column.
	assert_true(EarringGeometry.is_transporter_cell(full, 0, full, EarringGeometry.SIDE_RIGHT),
		"right earring's inner corner is col 0")
	assert_false(EarringGeometry.is_transporter_cell(full, full, full, EarringGeometry.SIDE_RIGHT),
		"right earring's outer corner is not")
	assert_false(EarringGeometry.is_transporter_cell(full - 1, full, full,
		EarringGeometry.SIDE_LEFT), "a peg row is never the transporter cell")
	assert_false(EarringGeometry.is_transporter_cell(0, 0, 0, EarringGeometry.SIDE_LEFT),
		"no earring, no transporter cell")


# ── Board-side size decisions ─────────────────────────────────────────────────

func test_load_path_parity_with_growth_path() -> void:
	print("test_load_path_parity_with_growth_path")
	# The claim that "earring size is derived, nothing new is saved" is only true
	# if loading level L lands on the same size as L purchases do. Drives the two
	# real board methods (add_two_rows' and apply_saved_state's ONLY size
	# decisions) rather than re-deriving the formula here.
	for enabled in [true, false]:
		var grown := _make_board(EarringGeometry.STARTING_ROWS, enabled)
		for level in range(0, _cap_level + 7):
			var loaded := _make_board(EarringGeometry.STARTING_ROWS, enabled)
			var from_save: Vector2i = loaded.size_for_add_row_level(level)
			assert_equal(Vector2i(grown.num_rows, grown.get_earring_rows()), from_save,
				"level %d (earrings_enabled=%s): grown size == loaded size" % [level, enabled])
			_free_board(loaded)
			var next: Vector2i = grown.next_size()
			grown.num_rows = next.x
			grown._earring_rows = next.y
		_free_board(grown)


func test_uncapped_board_grows_past_nine_buckets() -> void:
	print("test_uncapped_board_grows_past_nine_buckets")
	# StartingBoards authors challenge board sizes by looping add_two_rows. If
	# the cap applied unconditionally, no challenge could author a board bigger
	# than 9 buckets — a silent regression against existing challenge data.
	var board := _make_board(EarringGeometry.STARTING_ROWS, false)
	for i in 10:
		var next: Vector2i = board.next_size()
		board.num_rows = next.x
		board._earring_rows = next.y
	assert_equal(board.num_rows, 22, "10 uncapped growth steps -> 22 rows")
	assert_true(EarringGeometry.buckets_for_rows(board.num_rows) > 9,
		"an uncapped board goes well past 9 buckets")
	assert_equal(board.get_earring_rows(), 0, "and never sprouts earrings")
	_free_board(board)

	# The same board with earrings enabled stops at the cap and diverts.
	var capped := _make_board(EarringGeometry.STARTING_ROWS, true)
	for i in 10:
		var next: Vector2i = capped.next_size()
		capped.num_rows = next.x
		capped._earring_rows = next.y
	assert_equal(capped.num_rows, EarringGeometry.MAIN_MAX_ROWS,
		"with earrings enabled the main triangle stops at its cap")
	assert_equal(capped.get_earring_rows(), EarringGeometry.max_earring_rows(),
		"and the earrings absorbed the rest, up to the meeting point")
	_free_board(capped)


func test_level_six_save_loads_as_eight_main_six_earring() -> void:
	print("test_level_six_save_loads_as_eight_main_six_earring")
	# Accepted, deliberate save change: a save at ADD_ROW level 6 used to load
	# as a 14-row board; it now loads as 8 main rows + 6 earring rows.
	var board := _make_board(EarringGeometry.STARTING_ROWS, true)
	var size: Vector2i = board.size_for_add_row_level(6)
	assert_equal(size.x, 8, "level-6 save -> 8 main rows (was 14)")
	assert_equal(size.y, 6, "level-6 save -> 6 earring rows")
	_free_board(board)


## add_two_rows shifts every voided bucket index by +1 because a new edge bucket
## appears on each side. Earring growth adds no main-board buckets, so the
## indices must NOT shift — otherwise every existing void walks off the board.
func test_earring_growth_does_not_shift_voided_columns() -> void:
	print("test_earring_growth_does_not_shift_voided_columns")
	var board: PlinkoBoard = PlinkoBoardScene.instantiate()
	add_child(board)
	board.board_type = Enums.BoardType.GOLD
	board.earrings_enabled = true
	board.restore_size(EarringGeometry.MAIN_MAX_ROWS, 0)
	board.void_column(1)  # voids buckets 0 and 1
	var before: PackedInt32Array = board.get_reachable_bucket_indices()

	board.add_two_rows(false)  # main board is full -> this grows the earrings

	assert_equal(board.num_rows, EarringGeometry.MAIN_MAX_ROWS, "the main board did not grow")
	assert_equal(board.get_earring_rows(), 2, "the earrings did")
	assert_true(board.is_column_voided(0) and board.is_column_voided(1),
		"the existing voids stay on the same buckets")
	assert_false(board.is_column_voided(2), "and did not walk one to the right")
	assert_equal(board.get_reachable_bucket_indices(), before,
		"the reachable set is unchanged by earring growth")
	board.queue_free()


# ── ADD_ROW hard cap ──────────────────────────────────────────────────────────

func _prepare_add_row(level: int, cap: int) -> void:
	UpgradeManager.reset()
	CurrencyManager.reset()
	UpgradeManager.unlock(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(
		Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	state.level = level
	state.current_cap = cap
	state.cost = 1
	CurrencyManager.caps[Enums.CurrencyType.GOLD_COIN] = 1_000_000
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 1_000_000)


func test_add_row_refused_at_hard_cap() -> void:
	print("test_add_row_refused_at_hard_cap")
	var hard: int = EarringGeometry.max_add_row_level()
	_prepare_add_row(hard - 1, hard + 5)
	assert_true(UpgradeManager.can_buy(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"one level below the hard cap ADD_ROW is still buyable")
	_prepare_add_row(hard, hard + 5)
	assert_false(UpgradeManager.can_buy(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"at the hard cap ADD_ROW is refused even with a raised cap and full pockets")
	assert_equal(UpgradeManager.get_max_level(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		hard, "get_max_level reports the hard cap, not the raised current_cap")
	UpgradeManager.reset()
	CurrencyManager.reset()


func test_cap_raise_refused_at_hard_cap() -> void:
	print("test_cap_raise_refused_at_hard_cap")
	var hard: int = EarringGeometry.max_add_row_level()
	# Cap raises available + affordable, so only the hard cap can refuse.
	_prepare_add_row(0, hard)
	UpgradeManager.enable_cap_raise(Enums.BoardType.GOLD)
	var raise_currency: int = TierRegistry.cap_raise_currency(Enums.BoardType.GOLD)
	CurrencyManager.caps[raise_currency] = 1000
	CurrencyManager.add(raise_currency, 1000)
	assert_true(UpgradeManager.is_at_hard_cap(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"current_cap has reached the hard ceiling")
	assert_false(UpgradeManager.can_buy_cap_raise(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"raising a dead cap is refused — no wasted higher-tier spend")

	_prepare_add_row(0, hard - 1)
	UpgradeManager.enable_cap_raise(Enums.BoardType.GOLD)
	CurrencyManager.caps[raise_currency] = 1000
	CurrencyManager.add(raise_currency, 1000)
	assert_true(UpgradeManager.can_buy_cap_raise(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"below the ceiling the cap raise is still offered")
	UpgradeManager.reset()
	CurrencyManager.reset()


func test_hard_cap_survives_cap_raises() -> void:
	print("test_hard_cap_survives_cap_raises")
	# A soft max_level would evaporate after enough cap raises; drive them.
	var hard: int = EarringGeometry.max_add_row_level()
	_prepare_add_row(hard, 2)
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(
		Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	for i in 20:
		state.current_cap += 1
	assert_equal(state.current_cap, 22, "precondition: cap raised far past the hard ceiling")
	assert_false(UpgradeManager.can_buy(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"20 cap raises still cannot buy past the hard cap")
	UpgradeManager.reset()
	CurrencyManager.reset()


func test_force_apply_honours_hard_cap() -> void:
	print("test_force_apply_honours_hard_cap")
	# force_apply is the StartingUpgrades / prestige-reward path and skips can_buy.
	var hard: int = EarringGeometry.max_add_row_level()
	_prepare_add_row(hard, hard + 5)
	UpgradeManager.force_apply(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	assert_equal(UpgradeManager.get_level(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW), hard,
		"force_apply cannot push ADD_ROW past the hard cap")
	_prepare_add_row(hard - 1, hard + 5)
	UpgradeManager.force_apply(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW)
	assert_equal(UpgradeManager.get_level(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW), hard,
		"below the cap force_apply still grants normally")
	UpgradeManager.reset()
	CurrencyManager.reset()


func test_uncapped_mode_has_no_hard_cap() -> void:
	print("test_uncapped_mode_has_no_hard_cap")
	# A challenge whose ChallengeData didn't author earrings must keep today's
	# unbounded behaviour, or existing authored challenge boards silently shrink.
	var hard: int = EarringGeometry.max_add_row_level()
	var challenge := ChallengeData.new()
	challenge.grows_earrings = false
	var was_active: bool = ChallengeManager.is_active_challenge
	# Set the fields rather than set_challenge(), which fans a state-changed
	# signal out to AudioManager — irrelevant to what's under test here.
	ChallengeManager._challenge = challenge
	ChallengeManager.is_active_challenge = true
	assert_false(ChallengeManager.boards_grow_earrings(),
		"a grows_earrings=false challenge board does not grow earrings")
	_prepare_add_row(hard + 3, hard + 10)
	assert_true(UpgradeManager.can_buy(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"an uncapped challenge board can buy ADD_ROW well past the earring cap")
	assert_false(UpgradeManager.is_at_hard_cap(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"and has no hard ceiling at all")

	challenge.grows_earrings = true
	assert_true(ChallengeManager.boards_grow_earrings(),
		"grows_earrings=true reproduces normal-play growth")
	assert_false(UpgradeManager.can_buy(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW),
		"and with it the hard cap applies again")

	ChallengeManager.is_active_challenge = was_active
	ChallengeManager._challenge = null
	assert_true(ChallengeManager.boards_grow_earrings(), "normal play always grows earrings")
	UpgradeManager.reset()
	CurrencyManager.reset()


# ── Payout rules ──────────────────────────────────────────────────────────────

func test_gateway_buckets_pay_nothing() -> void:
	print("test_gateway_buckets_pay_nothing")
	# _predicted_bucket_gain feeds the prestige / cap-raise / next-board
	# cinematics. A gateway credits 0, so it must never fund one.
	var board := _make_board(8)
	board._earring_rows = 2
	_fill_buckets(board, 9, 5)
	var coin := _make_coin()
	assert_equal(board._predicted_bucket_gain(coin, board.get_bucket(0)), 0,
		"left gateway is predicted to gain nothing")
	assert_equal(board._predicted_bucket_gain(coin, board.get_bucket(8)), 0,
		"right gateway is predicted to gain nothing")
	assert_equal(board._predicted_bucket_gain(coin, board.get_bucket(4)), 5,
		"an interior bucket still pays")
	assert_true(board._is_gateway_bucket(0) and board._is_gateway_bucket(8),
		"both edges are gateways")
	assert_false(board._is_gateway_bucket(4), "the centre is not")
	coin.free()
	_free_board(board)


func test_gateway_buckets_pay_normally_before_earrings() -> void:
	print("test_gateway_buckets_pay_normally_before_earrings")
	var board := _make_board(8)
	board._earring_rows = 0
	_fill_buckets(board, 9, 5)
	var coin := _make_coin()
	assert_false(board._is_gateway_bucket(0), "no earrings -> edge bucket is a normal bucket")
	assert_equal(board._predicted_bucket_gain(coin, board.get_bucket(0)), 5,
		"and it pays its full value")
	coin.free()
	_free_board(board)


## The bucket-value ripple rewrites every bucket's value in place rather than
## rebuilding, so it has to know about gateways too — otherwise buying "bucket
## value" would resurrect a payout on a bucket that pays nothing.
func test_bucket_value_upgrade_leaves_gateways_at_zero() -> void:
	print("test_bucket_value_upgrade_leaves_gateways_at_zero")
	var board: PlinkoBoard = PlinkoBoardScene.instantiate()
	add_child(board)
	board.board_type = Enums.BoardType.GOLD
	board.earrings_enabled = true
	var size: Vector2i = board.size_for_add_row_level(EarringGeometry.max_add_row_level() - 1)
	board.restore_size(size.x, size.y)
	var last: int = board.buckets_container.get_child_count() - 1
	var centre_before: int = board.get_bucket(4).value

	board.increase_bucket_values()

	assert_equal(board.get_bucket(0).value, 0, "the left gateway still pays nothing")
	assert_equal(board.get_bucket(last).value, 0, "nor does the right one")
	assert_true(board.get_bucket(1).value > 0, "interior buckets still pay")
	assert_true(board.get_bucket(4).value >= centre_before,
		"and the upgrade still applied to them")
	board.queue_free()


func test_gameplay_target_never_picks_a_gateway() -> void:
	print("test_gameplay_target_never_picks_a_gateway")
	# A golden multiplier on an unpayable bucket would be a lie.
	var board := _make_board(8)
	board._earring_rows = 2
	_fill_buckets(board, 9, 5)
	var with_earrings: PackedInt32Array = board.get_gameplay_target_candidates()
	assert_equal(with_earrings.size(), 7, "both gateways are excluded from the 9 buckets")
	assert_false(0 in with_earrings, "the left gateway is never a golden target")
	assert_false(8 in with_earrings, "nor the right one")
	assert_true(4 in with_earrings, "interior buckets still are")

	board._earring_rows = 0
	assert_equal(board.get_gameplay_target_candidates().size(), 9,
		"before the earrings exist every bucket is a candidate again")
	_free_board(board)


func test_earring_bucket_credits_parent_currency() -> void:
	print("test_earring_bucket_credits_parent_currency")
	var board := _make_board(8)
	board._earring_rows = 4
	var credited: Array = []
	board.earring_credit_fn = func(currency: int, amount: int) -> void:
		credited.append([currency, amount])

	var earring := _make_earring(4, EarringGeometry.SIDE_LEFT)
	var bucket: Bucket = BucketScene.instantiate()
	add_child(bucket)
	bucket.currency_type = TierRegistry.primary_currency(Enums.BoardType.GOLD)
	bucket.value = EarringBoard.EARRING_BUCKET_VALUE
	var coin := _make_coin()
	add_child(coin)

	board.finalize_earring_landing(coin, earring, bucket)
	assert_equal(credited.size(), 1, "an earring landing credits exactly once")
	assert_equal(credited[0][0], TierRegistry.primary_currency(Enums.BoardType.GOLD),
		"in the PARENT board's currency (no new premium currency)")
	assert_equal(credited[0][1], EarringBoard.EARRING_BUCKET_VALUE,
		"every earring bucket is worth 1 for now")

	bucket.free()
	earring.free()
	_free_board(board)


func test_transporter_pays_nothing_and_transports() -> void:
	print("test_transporter_pays_nothing_and_transports")
	var board := _make_board(8)
	board._earring_rows = EarringGeometry.max_earring_rows()
	var credited: Array = []
	board.earring_credit_fn = func(currency: int, amount: int) -> void:
		credited.append([currency, amount])
	var transported: Array = []
	board.coin_transported.connect(
		func(bt: int, ct: int, pos: Vector3) -> void: transported.append([bt, ct, pos]))

	var full: int = EarringGeometry.max_earring_rows()
	var earring := _make_earring(full, EarringGeometry.SIDE_LEFT)
	var transporter: Bucket = BucketScene.instantiate()
	add_child(transporter)
	transporter.currency_type = TierRegistry.primary_currency(Enums.BoardType.GOLD)
	transporter.value = 0
	earring.set_transporter(
		EarringGeometry.innermost_bottom_col(full, EarringGeometry.SIDE_LEFT), transporter)
	assert_true(earring.is_transporter(transporter), "precondition: shared bucket is the transporter")

	var balance_before: int = CurrencyManager.get_balance(
		TierRegistry.primary_currency(Enums.BoardType.GOLD))
	var coin := _make_coin()
	add_child(coin)
	board.finalize_earring_landing(coin, earring, transporter)

	assert_equal(credited.size(), 0, "the transporter credits no currency at all")
	assert_equal(CurrencyManager.get_balance(TierRegistry.primary_currency(Enums.BoardType.GOLD)),
		balance_before, "and the balance is unchanged across the landing")
	assert_equal(transported.size(), 1, "coin_transported fired exactly once")
	assert_equal(transported[0][0], Enums.BoardType.GOLD, "carrying the emitting board's type")
	assert_equal(transported[0][1], Enums.CurrencyType.GOLD_COIN,
		"and the coin's (parent board's) currency")

	transporter.free()
	earring.free()
	_free_board(board)


# ── Coin surface ──────────────────────────────────────────────────────────────

func test_coin_surface_conformance() -> void:
	print("test_coin_surface_conformance")
	# Everything Coin._bounce_or_despawn / _begin_void_fall reaches for.
	var required := [
		"is_terminal_cell", "cell_to_world", "next_lattice_cell", "predicted_bucket_index",
		"resolve_bounce_direction", "is_lattice_cell_voided", "get_bucket",
		"flash_nearest_peg", "notify_deflector_resolved", "eject_coin_from_multimesh",
	]
	var board := _make_board(4)
	var earring := _make_earring(4, EarringGeometry.SIDE_LEFT)
	assert_true(board is CoinSurface, "PlinkoBoard is a CoinSurface")
	assert_true(earring is CoinSurface, "EarringBoard is a CoinSurface")
	for method in required:
		assert_true(board.has_method(method), "PlinkoBoard implements %s" % method)
		assert_true(earring.has_method(method), "EarringBoard implements %s" % method)
	# The fields Coin reads directly, declared once on the shared base — reading
	# them through a CoinSurface-typed reference is the actual contract.
	for surface: CoinSurface in [board, earring]:
		assert_equal(surface.num_rows, 4, "num_rows readable through CoinSurface")
		assert_near(surface.space_between_pegs, SPACE, 1e-5,
			"space_between_pegs readable through CoinSurface")
		assert_equal(surface.board_type, Enums.BoardType.GOLD,
			"board_type readable through CoinSurface")
	earring.free()
	_free_board(board)


## Drives the exact lattice walk Coin does, against any CoinSurface.
func _simulate(surface: CoinSurface, rolls: Array) -> int:
	var row := 0
	var col := 0
	var k := 0
	while not surface.is_terminal_cell(row, col):
		var dir: int = surface.resolve_bounce_direction(row, col, rolls[k % rolls.size()])
		var nc: Vector2i = surface.next_lattice_cell(row, col, dir)
		row = nc.x
		col = nc.y
		k += 1
	return surface.predicted_bucket_index(row, col)


func test_earring_descent_terminates_in_a_bucket() -> void:
	print("test_earring_descent_terminates_in_a_bucket")
	for rows in [2, 4, 6, 8]:
		var earring := _make_earring(rows, EarringGeometry.SIDE_LEFT)
		# roll >= 0.5 -> LEFT, roll < 0.5 -> RIGHT (identical to the main board).
		assert_equal(_simulate(earring, [0.9]), 0, "%d-row earring: all-left -> bucket 0" % rows)
		assert_equal(_simulate(earring, [0.0]), rows,
			"%d-row earring: all-right -> last bucket" % rows)
		var mixed: int = _simulate(earring, [0.0, 0.9])
		assert_true(mixed >= 0 and mixed <= rows,
			"%d-row earring: mixed rolls land in range" % rows)
		earring.free()

	# The all-right landing on a met earring is exactly the transporter cell.
	var full: int = EarringGeometry.max_earring_rows()
	var left := _make_earring(full, EarringGeometry.SIDE_LEFT)
	assert_true(EarringGeometry.is_transporter_cell(full, _simulate(left, [0.0]), full,
		EarringGeometry.SIDE_LEFT),
		"a left earring's all-right descent lands in the transporter")
	left.free()
	var right := _make_earring(full, EarringGeometry.SIDE_RIGHT)
	assert_true(EarringGeometry.is_transporter_cell(full, _simulate(right, [0.9]), full,
		EarringGeometry.SIDE_RIGHT),
		"a right earring's all-left descent lands in the transporter")
	right.free()


func test_earring_cell_to_world_is_parent_local() -> void:
	print("test_earring_cell_to_world_is_parent_local")
	# Handed-off coins stay parented to the PlinkoBoard, so the earring must
	# answer in the parent's frame — and via `transform *`, so a non-identity
	# basis survives.
	var earring := _make_earring(4, EarringGeometry.SIDE_LEFT)
	var apex := Vector3(-4.0, -3.0, 0.0)
	earring.position = apex
	var top: Vector3 = earring.get_top_peg_local()
	assert_near(top.x, apex.x, 1e-5, "top peg sits directly under the apex x")
	assert_near(top.y, apex.y + EarringBoard.COIN_ROW_Y_OFFSET, 1e-5,
		"and one coin-row offset above the apex y")

	var cell: Vector3 = earring.cell_to_world(2, 1)
	var expected: Vector3 = apex + Lattice.cell_to_world(2, 1, SPACE, VS,
		EarringBoard.COIN_ROW_Y_OFFSET)
	assert_near(cell.x, expected.x, 1e-5, "cell x is offset by the earring position")
	assert_near(cell.y, expected.y, 1e-5, "cell y is offset by the earring position")

	# Scale the earring: `transform *` must carry it, `position +` would not.
	earring.scale = Vector3(2.0, 2.0, 1.0)
	var scaled: Vector3 = earring.cell_to_world(2, 1)
	assert_near(scaled.x, apex.x + (expected.x - apex.x) * 2.0, 1e-5,
		"cell_to_world respects the earring's basis, not just its origin")
	earring.free()


func test_earring_scene_builds_pegs_and_buckets() -> void:
	print("test_earring_scene_builds_pegs_and_buckets")
	var earring: EarringBoard = EarringScene.instantiate()
	add_child(earring)
	earring.setup(4, EarringGeometry.SIDE_LEFT, SPACE, Enums.BoardType.GOLD)

	assert_true(earring.peg_field.is_built(), "the earring builds its own PegField")
	assert_equal(earring.peg_field.count(), 10, "4 rows -> 1+2+3+4 = 10 pegs")
	assert_equal(earring.buckets_container.get_child_count(), 5,
		"4 rows -> 5 buckets, all owned by the earring")
	for i in 5:
		var bucket: Bucket = earring.get_bucket(i)
		assert_true(bucket != null, "bucket %d exists" % i)
		assert_equal(bucket.value, EarringBoard.EARRING_BUCKET_VALUE,
			"bucket %d is worth 1" % i)
		assert_equal(bucket.currency_type, TierRegistry.primary_currency(Enums.BoardType.GOLD),
			"bucket %d pays the parent board's currency" % i)
	assert_true(earring.get_bucket(-1) == null and earring.get_bucket(5) == null,
		"out-of-range lookups are null, not an error")
	earring.queue_free()


func test_earring_scene_shares_the_injected_transporter() -> void:
	print("test_earring_scene_shares_the_injected_transporter")
	# Both earrings point their inner corner at ONE bucket owned by PlinkoBoard.
	# The earring must not build a bucket of its own at that column.
	var full: int = EarringGeometry.max_earring_rows()
	var shared: Bucket = BucketScene.instantiate()
	add_child(shared)

	var left: EarringBoard = EarringScene.instantiate()
	add_child(left)
	left.set_transporter(
		EarringGeometry.innermost_bottom_col(full, EarringGeometry.SIDE_LEFT), shared)
	left.setup(full, EarringGeometry.SIDE_LEFT, SPACE, Enums.BoardType.GOLD)

	var right: EarringBoard = EarringScene.instantiate()
	add_child(right)
	right.set_transporter(
		EarringGeometry.innermost_bottom_col(full, EarringGeometry.SIDE_RIGHT), shared)
	right.setup(full, EarringGeometry.SIDE_RIGHT, SPACE, Enums.BoardType.GOLD)

	assert_equal(left.get_bucket(full), shared, "left earring's inner corner IS the transporter")
	assert_equal(right.get_bucket(0), shared, "right earring's inner corner is the same bucket")
	assert_true(left.is_transporter(shared) and right.is_transporter(shared),
		"both earrings agree it's the transporter")
	assert_false(left.is_transporter(left.get_bucket(0)),
		"a normal earring bucket is not the transporter")
	# One fewer own bucket each, because neither builds one at that column.
	assert_equal(left.buckets_container.get_child_count(),
		EarringGeometry.buckets_for_rows(full) - 1,
		"the earring builds no bucket of its own at the transporter column")

	left.queue_free()
	right.queue_free()
	shared.queue_free()


## End-to-end on the real PlinkoBoard scene: build_board must actually spawn the
## earrings, the gateway buckets and the shared transporter, and must clear them
## again when the board shrinks back.
func test_full_board_builds_earrings_and_transporter() -> void:
	print("test_full_board_builds_earrings_and_transporter")
	var board: PlinkoBoard = PlinkoBoardScene.instantiate()
	add_child(board)
	board.board_type = Enums.BoardType.GOLD
	board.earrings_enabled = true

	# One level short of the cap: earrings exist, but haven't met.
	var hard: int = EarringGeometry.max_add_row_level()
	var short_size: Vector2i = board.size_for_add_row_level(hard - 1)
	board.restore_size(short_size.x, short_size.y)
	var num_buckets: int = board.buckets_container.get_child_count()
	assert_equal(num_buckets, 9, "the main board is frozen at 9 buckets")
	assert_equal(board.get_earring_rows(), 6, "with 6-row earrings at level %d" % (hard - 1))
	assert_true(board._left_earring != null and board._right_earring != null,
		"both earrings were built")
	assert_equal(board._left_earring.num_rows, board._right_earring.num_rows,
		"the two earrings always grow symmetrically")
	assert_true(board.get_transporter_bucket() == null,
		"no transporter until the earrings actually meet")
	assert_equal(board.get_bucket(0).value, 0, "the left edge bucket pays nothing")
	assert_equal(board.get_bucket(num_buckets - 1).value, 0, "nor the right one")
	assert_true(board.get_bucket(4).value > 0, "interior buckets still pay")

	# The earring apexes must sit exactly under the edge buckets.
	var left_bucket_x: float = board.buckets_container.position.x + board.get_bucket(0).position.x
	assert_near(board._left_earring.position.x, left_bucket_x, 1e-4,
		"left earring hangs directly under the left edge bucket")
	assert_near(board._right_earring.position.x, -left_bucket_x, 1e-4,
		"right earring under the right edge bucket, mirrored")

	# Bounds grow downward to include the earrings.
	var full_bounds: Rect2 = board.get_bounds()
	var main_only: Rect2 = board.main_board_bounds()
	assert_true(full_bounds.position.y < main_only.position.y,
		"get_bounds reaches below the main board so the camera frames the earrings")
	assert_true(board.toggle_earring_zoom(), "the earring zoom toggles on")
	assert_true(board.get_bounds().size.y < full_bounds.size.y,
		"and punches in on a smaller region")
	assert_false(board.toggle_earring_zoom(), "and back off again")

	# At the hard cap the earrings meet and the transporter appears at x = 0.
	var full_size: Vector2i = board.size_for_add_row_level(hard)
	board.restore_size(full_size.x, full_size.y)
	var transporter: Bucket = board.get_transporter_bucket()
	assert_true(transporter != null, "the transporter appears once the earrings meet")
	assert_equal(transporter.value, 0, "and pays no currency")
	assert_near(transporter.get_parent().position.x, 0.0, 1e-4,
		"it sits at board-local x = 0, dead centre")
	assert_false(transporter.get_parent() == board.buckets_container,
		"never parented to buckets_container, whose children build_board frees")
	var full_rows: int = board.get_earring_rows()
	assert_equal(board._left_earring.get_bucket(
		EarringGeometry.innermost_bottom_col(full_rows, EarringGeometry.SIDE_LEFT)), transporter,
		"the left earring's inner corner resolves to the shared transporter")
	assert_equal(board._right_earring.get_bucket(
		EarringGeometry.innermost_bottom_col(full_rows, EarringGeometry.SIDE_RIGHT)), transporter,
		"and so does the right earring's")

	# Shrinking back tears everything down again.
	board.restore_size(EarringGeometry.MAIN_MAX_ROWS, 0)
	assert_true(board._left_earring == null and board._right_earring == null,
		"dropping to 0 earring rows frees both earrings")
	assert_true(board.get_transporter_bucket() == null, "and the transporter with them")
	assert_true(board.get_bucket(0).value > 0,
		"the edge buckets go back to paying normally")

	board.queue_free()


## The handoff is the one place a coin changes surface mid-flight. It must swap
## BOTH main-board listeners (a live final_bounce_started would run the prestige
## check against an earring bucket), drop the finished tweens, and leave the coin
## parented to the PlinkoBoard — CoinPool mirrors parent-local positions, so
## reparenting would draw every coin in the wrong place.
func test_handoff_rewires_the_coin_without_reparenting_it() -> void:
	print("test_handoff_rewires_the_coin_without_reparenting_it")
	var board: PlinkoBoard = PlinkoBoardScene.instantiate()
	add_child(board)
	board.board_type = Enums.BoardType.GOLD
	board.earrings_enabled = true
	var size: Vector2i = board.size_for_add_row_level(EarringGeometry.max_add_row_level() - 1)
	board.restore_size(size.x, size.y)

	var coin: Coin = PlinkoBoard.CoinScene.instantiate()
	coin.coin_type = Enums.CurrencyType.GOLD_COIN
	coin.board = board
	board.add_child(coin)
	coin.landed.connect(board.on_coin_landed)
	coin.final_bounce_started.connect(board._on_final_bounce_started)

	board._handoff_to_earring(coin, true)

	assert_equal(coin.board, board._left_earring, "the coin now bounces on the left earring")
	assert_equal(coin.get_parent(), board,
		"but stays parented to the PlinkoBoard, so CoinPool keeps drawing it")
	assert_false(coin.landed.is_connected(board.on_coin_landed),
		"the main-board landing listener is disconnected")
	assert_false(coin.final_bounce_started.is_connected(board._on_final_bounce_started),
		"and so is the final-bounce listener that drives the prestige check")
	assert_equal(coin.get_lattice_cell(), Vector2i(0, 0),
		"the lattice cursor restarts at the earring's top peg")

	coin.queue_free()
	board.queue_free()


# ── Challenge wiring ──────────────────────────────────────────────────────────

func test_challenge_data_defaults_to_uncapped() -> void:
	print("test_challenge_data_defaults_to_uncapped")
	# Existing authored .tres files get the default with no edit, so every
	# challenge board still builds to its authored size.
	assert_false(ChallengeData.new().grows_earrings,
		"grows_earrings defaults to false — existing challenges are unaffected")
	var dir := DirAccess.open("res://data/challenges")
	var checked := 0
	if dir:
		for file in dir.get_files():
			if not file.ends_with(".tres"):
				continue
			var data: ChallengeData = load("res://data/challenges/%s" % file)
			if data == null:
				continue
			checked += 1
			assert_false(data.grows_earrings,
				"authored challenge %s is uncapped (no .tres edits needed)" % file)
	assert_true(checked > 0, "found authored challenge resources to check")


## Offline earnings model the same payouts live play does. Before this the edge
## buckets were the HIGHEST-value entries in the offline layout while awarding
## nothing on a real board.
func test_offline_layout_treats_gateways_as_earring_payouts() -> void:
	print("test_offline_layout_treats_gateways_as_earring_payouts")
	var rows: int = EarringGeometry.MAIN_MAX_ROWS
	var no_earrings: Array = OfflineCalculator._get_bucket_layout(
		rows, 1, 3, false, Enums.BoardType.GOLD, 0)
	assert_equal(no_earrings.size(), 9, "9 buckets")
	assert_equal(no_earrings[0]["value"], 5, "without earrings the edge is the top payer")

	var with_earrings: Array = OfflineCalculator._get_bucket_layout(
		rows, 1, 3, false, Enums.BoardType.GOLD, EarringGeometry.max_earring_rows())
	assert_equal(with_earrings[0]["value"], EarringBoard.EARRING_BUCKET_VALUE,
		"with earrings the left gateway is worth an earring bucket, not 5")
	assert_equal(with_earrings[8]["value"], EarringBoard.EARRING_BUCKET_VALUE,
		"and so is the right one")
	assert_equal(with_earrings[4]["value"], no_earrings[4]["value"],
		"interior buckets are untouched")
	assert_equal(with_earrings[0]["currency_key"], no_earrings[0]["currency_key"],
		"and it still pays the board's own currency")
