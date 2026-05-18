extends "res://test/test_base.gd"

## Deflector model + lattice tests — run with:
##   godot --headless --scene res://test/test_deflector.tscn
##
## Pure-logic tests on a bare PlinkoBoard (no scene tree). Slot-cap tests use
## the real UpgradeManager autoload (available headless), matching the pattern
## in test_ensure_unlocks.gd.

const SPACE := 1.0
const VS := 1.0


func _run_tests() -> void:
	print("\n=== Deflector Tests ===\n")
	test_position_x_for_matches_build_formula()
	test_peg_index_matches_triangular_formula()
	test_cell_to_world_origin_matches_launch_target()
	test_next_lattice_cell_left_right()
	test_is_terminal_cell()
	test_predicted_bucket_index()
	test_resolve_direction_no_deflector_matches_legacy()
	test_resolve_direction_deflector_encourages()
	test_deflector_bias_value()
	test_deflector_outcome()
	test_notify_deflector_resolved_null_editor_safe()
	test_cap_includes_prestige_permanent()
	test_resolve_click_action()
	test_place_respects_slot_cap()
	test_global_cap_via_query()
	test_place_reaim_does_not_consume_slot()
	test_remove_and_has()
	test_serialize_restore_round_trip()
	test_restore_drops_invalid()
	test_restore_cleared_when_cap_zero()
	test_seed_first_peg_deflector()


func _make_board() -> PlinkoBoard:
	var board := PlinkoBoard.new()
	board.board_type = Enums.BoardType.GOLD
	board.num_rows = 4
	board.space_between_pegs = SPACE
	board.vertical_spacing = VS
	return board


func _set_cap(n: int) -> void:
	UpgradeManager.reset()
	# Deflector is universal — cap lives under the canonical board (ORANGE).
	UpgradeManager.get_state(PlinkoBoard.DEFLECTOR_BOARD, Enums.UpgradeType.PEG_DEFLECTOR).level = n


# --- Pure lattice math ---

func test_position_x_for_matches_build_formula() -> void:
	print("test_position_x_for_matches_build_formula")
	var b := _make_board()
	for row in range(0, 6):
		for col in range(0, row + 1):
			var expected := -row * SPACE / 2.0 + col * SPACE
			assert_near(b.position_x_for(row, col), expected, 0.0001,
				"position_x_for(%d,%d)" % [row, col])
	b.free()


func test_peg_index_matches_triangular_formula() -> void:
	print("test_peg_index_matches_triangular_formula")
	var b := _make_board()
	# Walk every cell in row-major order; index must increase by exactly 1,
	# matching build_board()'s flat fill order.
	var expected := 0
	for row in range(0, 7):
		for col in range(0, row + 1):
			assert_equal(b.peg_index(row, col), expected,
				"peg_index(%d,%d)" % [row, col])
			expected += 1
	b.free()


func test_cell_to_world_origin_matches_launch_target() -> void:
	print("test_cell_to_world_origin_matches_launch_target")
	var b := _make_board()
	# Coin spawns and start()s toward (0, 0.2, 0) — cell (0,0) must agree.
	var w := b.cell_to_world(0, 0)
	assert_near(w.x, 0.0, 0.0001, "cell_to_world(0,0).x")
	assert_near(w.y, PlinkoBoard.COIN_ROW_Y_OFFSET, 0.0001, "cell_to_world(0,0).y")
	# Row 2 sits two vertical_spacings below the offset.
	assert_near(b.cell_to_world(2, 1).y,
		PlinkoBoard.COIN_ROW_Y_OFFSET - 2.0 * VS, 0.0001, "cell_to_world(2,1).y")
	b.free()


func test_next_lattice_cell_left_right() -> void:
	print("test_next_lattice_cell_left_right")
	var b := _make_board()
	assert_equal(b.next_lattice_cell(2, 1, Enums.Direction.RIGHT), Vector2i(3, 2),
		"RIGHT → (row+1, col+1)")
	assert_equal(b.next_lattice_cell(2, 1, Enums.Direction.LEFT), Vector2i(3, 1),
		"LEFT → (row+1, col)")
	b.free()


func test_is_terminal_cell() -> void:
	print("test_is_terminal_cell")
	var b := _make_board()  # num_rows = 4 → peg rows 0..3, row 4 is the bucket row
	assert_false(b.is_terminal_cell(3, 0), "row 3 is still a peg row")
	assert_true(b.is_terminal_cell(4, 2), "row 4 is terminal")
	assert_true(b.is_terminal_cell(5, 0), "past the bottom is terminal")
	b.free()


func test_predicted_bucket_index() -> void:
	print("test_predicted_bucket_index")
	var b := _make_board()
	assert_equal(b.predicted_bucket_index(4, 0), 0, "col 0 → bucket 0")
	assert_equal(b.predicted_bucket_index(4, 4), 4, "col 4 → bucket 4")
	b.free()


# --- Direction resolution ---

func test_resolve_direction_no_deflector_matches_legacy() -> void:
	print("test_resolve_direction_no_deflector_matches_legacy")
	var b := _make_board()
	for roll in [0.0, 0.49, 0.5, 0.51, 0.999]:
		var expected: int = Enums.Direction.RIGHT if roll < 0.5 else Enums.Direction.LEFT
		assert_equal(b.resolve_bounce_direction(1, 0, roll), expected,
			"roll %s matches legacy 1 if <0.5 else -1" % roll)
	b.free()


func test_resolve_direction_deflector_encourages() -> void:
	print("test_resolve_direction_deflector_encourages")
	# Base strength 5 → bias 6/7 (~0.857): roll < 6/7 follows the deflector,
	# roll >= 6/7 goes the other way (a 1:6 split — encourage, not force).
	_set_cap(4)
	var b := _make_board()
	var idx := b.peg_index(2, 1)
	b.place_deflector(idx, Enums.Direction.RIGHT)
	assert_equal(b.resolve_bounce_direction(2, 1, 0.0), Enums.Direction.RIGHT,
		"low roll follows the deflector (RIGHT)")
	assert_equal(b.resolve_bounce_direction(2, 1, 0.7), Enums.Direction.RIGHT,
		"roll 0.7 < 6/7 still follows RIGHT")
	assert_equal(b.resolve_bounce_direction(2, 1, 0.84), Enums.Direction.RIGHT,
		"roll 0.84 < 6/7 follows RIGHT (would have missed at the old 4/5)")
	assert_equal(b.resolve_bounce_direction(2, 1, 0.9), Enums.Direction.LEFT,
		"roll 0.9 >= 6/7 goes the other way (not forced)")
	assert_equal(b.resolve_bounce_direction(2, 1, 0.99), Enums.Direction.LEFT,
		"high roll goes the other way")
	b.place_deflector(idx, Enums.Direction.LEFT)
	assert_equal(b.resolve_bounce_direction(2, 1, 0.1), Enums.Direction.LEFT,
		"re-aimed: low roll follows LEFT")
	assert_equal(b.resolve_bounce_direction(2, 1, 0.9), Enums.Direction.RIGHT,
		"re-aimed: high roll goes the other way (RIGHT)")
	# A different peg is unaffected (legacy 50/50).
	assert_equal(b.resolve_bounce_direction(2, 0, 0.0), Enums.Direction.RIGHT,
		"non-deflector peg still uses the roll")
	b.free()


func test_deflector_bias_value() -> void:
	print("test_deflector_bias_value")
	var b := _make_board()
	# Base strength 5 → bias (5+1)/(5+2) = 6/7 (a 1:6 split).
	assert_equal(b.get_deflector_strength(), 5, "base strength is 5")
	assert_near(b._deflector_bias(), 6.0 / 7.0, 0.0001, "bias = 6/7 at strength 5")
	b.free()


func test_deflector_outcome() -> void:
	print("test_deflector_outcome")
	# Pure classifier driving the reaction VFX. NONE when no deflector here;
	# FOLLOWED when the resolved direction equals the deflector's set dir;
	# MISSED when it's the opposite. Does not consume RNG.
	_set_cap(4)
	var b := _make_board()
	# No deflectors anywhere → NONE regardless of direction.
	assert_equal(b.deflector_outcome(2, 1, Enums.Direction.RIGHT),
		PlinkoBoard.DeflectorOutcome.NONE, "empty board → NONE")
	assert_equal(b.deflector_outcome(2, 1, Enums.Direction.LEFT),
		PlinkoBoard.DeflectorOutcome.NONE, "empty board → NONE (other dir)")

	var idx := b.peg_index(2, 1)
	b.place_deflector(idx, Enums.Direction.RIGHT)
	assert_equal(b.deflector_outcome(2, 1, Enums.Direction.RIGHT),
		PlinkoBoard.DeflectorOutcome.FOLLOWED, "RIGHT deflector, coin RIGHT → FOLLOWED")
	assert_equal(b.deflector_outcome(2, 1, Enums.Direction.LEFT),
		PlinkoBoard.DeflectorOutcome.MISSED, "RIGHT deflector, coin LEFT → MISSED")
	# A different peg, with a deflector present elsewhere → still NONE.
	assert_equal(b.deflector_outcome(2, 0, Enums.Direction.RIGHT),
		PlinkoBoard.DeflectorOutcome.NONE, "non-deflected peg → NONE")

	# Re-aim LEFT — the classification must follow the new direction.
	b.place_deflector(idx, Enums.Direction.LEFT)
	assert_equal(b.deflector_outcome(2, 1, Enums.Direction.LEFT),
		PlinkoBoard.DeflectorOutcome.FOLLOWED, "LEFT deflector, coin LEFT → FOLLOWED")
	assert_equal(b.deflector_outcome(2, 1, Enums.Direction.RIGHT),
		PlinkoBoard.DeflectorOutcome.MISSED, "LEFT deflector, coin RIGHT → MISSED")
	b.free()


func test_notify_deflector_resolved_null_editor_safe() -> void:
	print("test_notify_deflector_resolved_null_editor_safe")
	# A bare board never instantiates _deflector_editor (only _setup does) —
	# that is exactly the state every pure test runs under, and the state the
	# new Coin._bounce_or_despawn call must tolerate. Assert the guard makes it
	# a no-op that neither errors nor mutates the model.
	_set_cap(1)
	var b := _make_board()
	var idx := b.peg_index(2, 1)
	b.place_deflector(idx, Enums.Direction.RIGHT)
	b.notify_deflector_resolved(2, 1, Enums.Direction.RIGHT)
	b.notify_deflector_resolved(2, 1, Enums.Direction.LEFT)
	b.notify_deflector_resolved(0, 0, Enums.Direction.RIGHT)
	assert_equal(b.deflector_count(), 1, "notify never mutates the deflector model")
	assert_true(b.has_deflector(idx), "deflector untouched by notify")
	b.free()


func test_cap_includes_prestige_permanent() -> void:
	print("test_cap_includes_prestige_permanent")
	_set_cap(2)
	PrestigeManager._prestige_counts.clear()
	var b := _make_board()
	assert_equal(b.get_deflector_cap(), 2, "cap = upgrade level, no prestige")
	# The FIRST (gold-board) prestige records the ORANGE tier — must NOT grant.
	PrestigeManager._prestige_counts[Enums.BoardType.ORANGE] = 1
	assert_equal(PrestigeManager.get_permanent_deflector_count(), 0,
		"first/gold prestige grants no deflector")
	assert_equal(b.get_deflector_cap(), 2, "still just the upgrade level")
	# The SECOND (orange-board) prestige records the tier AFTER orange.
	var after_orange: TierData = TierRegistry.get_next_tier(Enums.BoardType.ORANGE)
	PrestigeManager._prestige_counts[after_orange.board_type] = 1
	assert_equal(PrestigeManager.get_permanent_deflector_count(), 1, "one permanent")
	assert_equal(b.get_deflector_cap(), 3, "orange-board prestige → +1 permanent slot")
	PrestigeManager._prestige_counts.clear()
	b.free()


func test_resolve_click_action() -> void:
	print("test_resolve_click_action")
	_set_cap(1)
	var b := _make_board()
	var a := b.peg_index(1, 0)
	var c := b.peg_index(1, 1)
	assert_equal(b.resolve_click_action(a), PlinkoBoard.ClickAction.PLACE,
		"empty peg with a free slot → PLACE")
	b.place_deflector(a, Enums.Direction.LEFT)
	assert_equal(b.resolve_click_action(a), PlinkoBoard.ClickAction.REMOVE,
		"placed peg → REMOVE")
	assert_equal(b.resolve_click_action(c), PlinkoBoard.ClickAction.IGNORE,
		"no free slot left → IGNORE")
	b.free()


# --- Placement / slot cap ---

func test_place_respects_slot_cap() -> void:
	print("test_place_respects_slot_cap")
	_set_cap(2)
	var b := _make_board()
	assert_true(b.place_deflector(b.peg_index(1, 0), Enums.Direction.LEFT), "1st place ok")
	assert_true(b.place_deflector(b.peg_index(1, 1), Enums.Direction.RIGHT), "2nd place ok")
	assert_false(b.place_deflector(b.peg_index(2, 0), Enums.Direction.LEFT),
		"3rd place rejected (cap 2)")
	assert_equal(b.deflector_count(), 2, "count capped at 2")
	b.free()


func test_global_cap_via_query() -> void:
	print("test_global_cap_via_query")
	# Universal cap is global: a board enforces it against the total placed
	# across ALL boards, supplied by BoardManager via deflector_total_query.
	_set_cap(2)
	var b := _make_board()
	b.deflector_total_query = func() -> int: return 2  # 2 already placed elsewhere
	assert_false(b.place_deflector(b.peg_index(1, 0), Enums.Direction.LEFT),
		"rejected — global pool full though this board is empty")
	assert_equal(b.resolve_click_action(b.peg_index(1, 0)),
		PlinkoBoard.ClickAction.IGNORE, "hover shows nothing when pool full")
	b.deflector_total_query = func() -> int: return 1  # one slot free globally
	assert_true(b.place_deflector(b.peg_index(1, 0), Enums.Direction.RIGHT),
		"allowed when the global pool has a free slot")
	b.free()


func test_place_reaim_does_not_consume_slot() -> void:
	print("test_place_reaim_does_not_consume_slot")
	_set_cap(1)
	var b := _make_board()
	var idx := b.peg_index(1, 0)
	assert_true(b.place_deflector(idx, Enums.Direction.LEFT), "place at cap")
	assert_true(b.place_deflector(idx, Enums.Direction.RIGHT),
		"re-aim same peg allowed even at cap")
	assert_equal(b.get_deflector_dir(idx), Enums.Direction.RIGHT, "direction updated")
	assert_equal(b.deflector_count(), 1, "still one deflector")
	b.free()


func test_remove_and_has() -> void:
	print("test_remove_and_has")
	_set_cap(2)
	var b := _make_board()
	var idx := b.peg_index(3, 2)
	b.place_deflector(idx, Enums.Direction.LEFT)
	assert_true(b.has_deflector(idx), "has after place")
	b.remove_deflector(idx)
	assert_false(b.has_deflector(idx), "gone after remove")
	assert_equal(b.resolve_bounce_direction(3, 2, 0.0), Enums.Direction.RIGHT,
		"removed → random pick restored")
	b.free()


# --- Serialize / restore ---

func test_serialize_restore_round_trip() -> void:
	print("test_serialize_restore_round_trip")
	_set_cap(3)
	var b := _make_board()
	b.place_deflector(b.peg_index(1, 0), Enums.Direction.LEFT)
	b.place_deflector(b.peg_index(3, 2), Enums.Direction.RIGHT)
	var blob := b.serialize_deflectors()

	var b2 := _make_board()
	b2.restore_deflectors(blob)
	assert_equal(b2.deflector_count(), 2, "both restored")
	assert_equal(b2.get_deflector_dir(b2.peg_index(1, 0)), Enums.Direction.LEFT, "dir 1")
	assert_equal(b2.get_deflector_dir(b2.peg_index(3, 2)), Enums.Direction.RIGHT, "dir 2")
	b.free()
	b2.free()


func test_restore_drops_invalid() -> void:
	print("test_restore_drops_invalid")
	_set_cap(2)
	var b := _make_board()  # num_rows 4 → total pegs = 4*5/2 = 10 (idx 0..9)
	b.restore_deflectors([
		{"peg": 3, "dir": Enums.Direction.LEFT},   # valid
		{"peg": 99, "dir": Enums.Direction.RIGHT}, # off-grid → dropped
		{"peg": 5, "dir": 0},                      # bad dir → dropped
		{"peg": 4, "dir": Enums.Direction.RIGHT},  # valid
		{"peg": 6, "dir": Enums.Direction.LEFT},   # beyond cap (2) → dropped
	])
	assert_equal(b.deflector_count(), 2, "only the 2 valid, in-cap entries kept")
	assert_true(b.has_deflector(3), "peg 3 kept")
	assert_true(b.has_deflector(4), "peg 4 kept")
	assert_false(b.has_deflector(99), "off-grid dropped")
	b.free()


func test_restore_cleared_when_cap_zero() -> void:
	print("test_restore_cleared_when_cap_zero")
	# Mirrors the prestige path: upgrade level resets to 0 → no deflectors.
	_set_cap(0)
	var b := _make_board()
	b.restore_deflectors([{"peg": 2, "dir": Enums.Direction.LEFT}])
	assert_equal(b.deflector_count(), 0, "cap 0 ⇒ all placements dropped")
	b.free()


func test_seed_first_peg_deflector() -> void:
	print("test_seed_first_peg_deflector")
	# The orange-prestige reward auto-places one deflector on the first peg.
	_set_cap(1)
	var b := _make_board()
	var first := b.peg_index(0, 0)
	assert_equal(first, 0, "first peg is index 0 (the apex)")
	b.seed_first_peg_deflector()
	assert_true(b.has_deflector(0), "deflector seeded on the first peg")
	assert_equal(b.get_deflector_dir(0), Enums.Direction.RIGHT, "default dir RIGHT")
	# Idempotent — calling again doesn't add or change it.
	b.seed_first_peg_deflector(Enums.Direction.LEFT)
	assert_equal(b.deflector_count(), 1, "still one deflector")
	assert_equal(b.get_deflector_dir(0), Enums.Direction.RIGHT, "unchanged on re-seed")
	b.free()
