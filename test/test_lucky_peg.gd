extends "res://test/test_base.gd"

## Lucky peg tests — run with:
##   godot --headless --scene res://test/test_lucky_peg.tscn
##
## A wandering peg that splits any coin striking it into two, one each way, both
## at full value. Splits are ordinary coins so they can split again.
##
## The pure halves (candidate set, the flat-index <-> lattice-cell mapping, the
## level -> count contract) run on no board at all; the wander/consume state runs
## on a bare PlinkoBoard.


func _run_tests() -> void:
	print("\n=== Lucky Peg Tests ===\n")

	test_count_follows_level()
	test_candidates_cover_every_peg()
	test_candidates_skip_voided_cells()
	test_candidates_skip_taken_pegs()
	test_candidates_empty_when_everything_taken()
	test_lattice_cell_round_trips_through_peg_index()
	test_lattice_cell_rejects_out_of_range()
	test_consume_returns_false_without_a_lucky_peg()
	test_consume_is_one_shot()
	test_consume_ignores_other_pegs()
	test_retired_peg_queues_a_respawn()
	test_split_directions_are_opposites()

	print("\n=== Done ===\n")


func _make_board(num_rows: int = 4) -> PlinkoBoard:
	var board := PlinkoBoard.new()
	board.board_type = Enums.BoardType.GREEN
	board.num_rows = num_rows
	return board


## Nothing is voided unless a test says so.
func _no_voids() -> Callable:
	return func(_row: int, _col: int) -> bool: return false


# --- Level -> count ---

func test_count_follows_level() -> void:
	print("test_count_follows_level")
	# One peg per level, so buying the upgrade immediately puts one on every
	# board rather than only raising a chance.
	assert_equal(PlinkoBoard.lucky_peg_count_for_level(0), 0, "unowned means no pegs")
	assert_equal(PlinkoBoard.lucky_peg_count_for_level(1), 1, "level 1 is one peg")
	assert_equal(PlinkoBoard.lucky_peg_count_for_level(4), 4, "level 4 is four pegs")
	# Defensive: a negative can only come from corrupt state, but it would make
	# the top-up loop misbehave rather than no-op.
	assert_equal(PlinkoBoard.lucky_peg_count_for_level(-3), 0, "negative clamps to none")


# --- Candidate set ---

func test_candidates_cover_every_peg() -> void:
	print("test_candidates_cover_every_peg")
	# A 4-row lattice holds 1+2+3+4 = 10 pegs, and all of them are fair game.
	var c: PackedInt32Array = PlinkoBoard.lucky_peg_candidates(4, [], _no_voids())
	assert_equal(c.size(), 10, "every peg on a 4-row lattice is a candidate")
	assert_true(0 in c, "the apex peg is included")
	assert_true(9 in c, "the last peg of the bottom row is included")


func test_candidates_skip_voided_cells() -> void:
	print("test_candidates_skip_voided_cells")
	# A bomb destroys a column; a lucky peg must never light up on a peg that is
	# no longer there. The wander inherits this by asking the board rather than
	# tracking voids itself.
	var voided := func(row: int, col: int) -> bool: return row == 1 and col == 0
	var c: PackedInt32Array = PlinkoBoard.lucky_peg_candidates(4, [], voided)
	assert_equal(c.size(), 9, "the voided peg is excluded")
	assert_false(1 in c, "peg index 1 is (row 1, col 0) and is voided")
	assert_true(2 in c, "its neighbour is unaffected")


func test_candidates_skip_taken_pegs() -> void:
	print("test_candidates_skip_taken_pegs")
	# Two lucky pegs must never share a peg, or consuming one would silently
	# drop the other.
	var c: PackedInt32Array = PlinkoBoard.lucky_peg_candidates(4, [0, 5], _no_voids())
	assert_equal(c.size(), 8, "both taken pegs are excluded")
	assert_false(0 in c, "an occupied peg is not a candidate")
	assert_false(5 in c, "nor is the second")


func test_candidates_empty_when_everything_taken() -> void:
	print("test_candidates_empty_when_everything_taken")
	# A tiny board with every peg occupied must yield nothing rather than
	# looping or handing back an occupied index.
	var c: PackedInt32Array = PlinkoBoard.lucky_peg_candidates(1, [0], _no_voids())
	assert_equal(c.size(), 0, "no candidates left")


# --- Flat index <-> lattice cell ---

func test_lattice_cell_round_trips_through_peg_index() -> void:
	print("test_lattice_cell_round_trips_through_peg_index")
	# lattice_cell_for_peg is the inverse of peg_index; if they disagreed a lucky
	# peg would light one peg and pay out on another.
	var board := _make_board(5)
	for idx in 15:  # 1+2+3+4+5
		var cell: Vector2i = PlinkoBoard.lattice_cell_for_peg(idx, 5)
		assert_equal(board.peg_index(cell.x, cell.y), idx,
			"peg %d round-trips through (%d, %d)" % [idx, cell.x, cell.y])
	board.free()


func test_lattice_cell_rejects_out_of_range() -> void:
	print("test_lattice_cell_rejects_out_of_range")
	assert_true(PlinkoBoard.lattice_cell_for_peg(-1, 4) == Vector2i(-1, -1),
		"a negative index has no cell")
	assert_true(PlinkoBoard.lattice_cell_for_peg(10, 4) == Vector2i(-1, -1),
		"index 10 is past the end of a 10-peg lattice")


# --- Consume ---

func test_consume_returns_false_without_a_lucky_peg() -> void:
	print("test_consume_returns_false_without_a_lucky_peg")
	var board := _make_board()
	assert_false(board.try_consume_lucky_peg(2, 1),
		"a board with no lucky pegs never splits")
	board.free()


func test_consume_is_one_shot() -> void:
	print("test_consume_is_one_shot")
	# Consuming is what stops a second coin arriving in the same frame from
	# claiming the same peg twice.
	var board := _make_board()
	board._lucky_pegs[board.peg_index(2, 1)] = 5.0
	assert_true(board.try_consume_lucky_peg(2, 1), "the first coin splits")
	assert_false(board.try_consume_lucky_peg(2, 1), "the second coin does not")
	board.free()


func test_consume_ignores_other_pegs() -> void:
	print("test_consume_ignores_other_pegs")
	var board := _make_board()
	board._lucky_pegs[board.peg_index(2, 1)] = 5.0
	assert_false(board.try_consume_lucky_peg(2, 0), "a neighbouring peg is not lucky")
	assert_true(board._lucky_pegs.has(board.peg_index(2, 1)),
		"and the real one is untouched")
	board.free()


func test_retired_peg_queues_a_respawn() -> void:
	print("test_retired_peg_queues_a_respawn")
	# After a hit the board is lucky-peg-free for the respawn gap rather than
	# re-lighting instantly, or the peg would look like it never moved.
	var board := _make_board()
	board._lucky_pegs[board.peg_index(1, 1)] = 5.0
	board.try_consume_lucky_peg(1, 1)
	assert_equal(board._lucky_pegs.size(), 0, "the peg is gone immediately")
	assert_equal(board._lucky_peg_respawns.size(), 1, "a respawn is queued")
	assert_near(board._lucky_peg_respawns[0], PlinkoBoard.LUCKY_PEG_RESPAWN_DELAY, 0.0001,
		"queued for the full respawn delay")
	board.free()


# --- Split direction ---

func test_split_directions_are_opposites() -> void:
	print("test_split_directions_are_opposites")
	# One each way rather than two random picks: guaranteed divergence is what
	# makes a split read as a split instead of one coin that flickered.
	assert_equal(int(Enums.Direction.RIGHT), -int(Enums.Direction.LEFT),
		"the two directions are exact opposites")
