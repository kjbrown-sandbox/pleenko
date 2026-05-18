extends "res://test/test_base.gd"

## Deflector trajectory tests — run with:
##   godot --headless --scene res://test/test_deflector_trajectory.tscn
##
## Simulates a full lattice descent using ONLY the pure board methods (the same
## sequence Coin._bounce_or_despawn drives), so we can assert the deflector's
## effect on the actual landing bucket without tweens / the scene tree.

const SPACE := 1.0
const VS := 1.0


func _run_tests() -> void:
	print("\n=== Deflector Trajectory Tests ===\n")
	test_all_left_lands_in_bucket_zero()
	test_all_right_lands_in_last_bucket()
	test_tracked_cell_matches_build_index()
	test_deflector_shifts_landing_vs_control()
	test_full_right_deflector_funnel()


func _make_board(rows: int) -> PlinkoBoard:
	var board := PlinkoBoard.new()
	board.board_type = Enums.BoardType.GOLD
	board.num_rows = rows
	board.space_between_pegs = SPACE
	board.vertical_spacing = VS
	return board


## Drives the exact lattice walk Coin does and returns the landing bucket index.
func _simulate(board: PlinkoBoard, rolls: Array) -> int:
	var row := 0
	var col := 0
	var k := 0
	while not board.is_terminal_cell(row, col):
		var roll: float = rolls[k % rolls.size()]
		var dir: int = board.resolve_bounce_direction(row, col, roll)
		var nc: Vector2i = board.next_lattice_cell(row, col, dir)
		row = nc.x
		col = nc.y
		k += 1
	return board.predicted_bucket_index(row, col)


func test_all_left_lands_in_bucket_zero() -> void:
	print("test_all_left_lands_in_bucket_zero")
	var b := _make_board(6)
	# roll >= 0.5 → LEFT every row.
	assert_equal(_simulate(b, [0.9]), 0, "all-left descent lands in bucket 0")
	b.free()


func test_all_right_lands_in_last_bucket() -> void:
	print("test_all_right_lands_in_last_bucket")
	var b := _make_board(6)
	# roll < 0.5 → RIGHT every row. num_rows rights → bucket num_rows.
	assert_equal(_simulate(b, [0.0]), 6, "all-right descent lands in last bucket")
	b.free()


func test_tracked_cell_matches_build_index() -> void:
	print("test_tracked_cell_matches_build_index")
	# Walking the lattice keeps (row,col) consistent with build_board()'s flat
	# index — proves the coin's tracked cell can't drift from the peg layout.
	var b := _make_board(5)
	var row := 0
	var col := 0
	var rolls := [0.0, 0.9, 0.0, 0.9, 0.0]  # R, L, R, L, R
	var k := 0
	while not b.is_terminal_cell(row, col):
		assert_true(col >= 0 and col <= row, "col within [0,row] at row %d" % row)
		assert_equal(b.peg_index(row, col), row * (row + 1) / 2 + col,
			"peg_index matches triangular formula at (%d,%d)" % [row, col])
		var dir: int = b.resolve_bounce_direction(row, col, rolls[k % rolls.size()])
		var nc: Vector2i = b.next_lattice_cell(row, col, dir)
		row = nc.x
		col = nc.y
		k += 1
	b.free()


func test_deflector_shifts_landing_vs_control() -> void:
	print("test_deflector_shifts_landing_vs_control")
	UpgradeManager.reset()
	UpgradeManager.get_state(PlinkoBoard.DEFLECTOR_BOARD, Enums.UpgradeType.PEG_DEFLECTOR).level = 1
	# roll 0.55: legacy (no deflector) → LEFT (>=0.5); but < bias 6/7 so a
	# deflector IS followed. Lets one deflector visibly shift the landing.
	var rolls := [0.55]

	var control := _make_board(6)
	var control_land := _simulate(control, rolls)
	assert_equal(control_land, 0, "control (no deflector) lands in bucket 0")
	control.free()

	var b := _make_board(6)
	# Deflect RIGHT at the very first peg; the rest still rolls LEFT.
	b.place_deflector(b.peg_index(0, 0), Enums.Direction.RIGHT)
	var land := _simulate(b, rolls)
	assert_equal(land, 1, "one RIGHT deflector then all LEFT → bucket 1 (shifted)")
	b.free()


func test_full_right_deflector_funnel() -> void:
	print("test_full_right_deflector_funnel")
	UpgradeManager.reset()
	UpgradeManager.get_state(PlinkoBoard.DEFLECTOR_BOARD, Enums.UpgradeType.PEG_DEFLECTOR).level = 99
	var b := _make_board(5)
	# Deflect RIGHT along the actual all-RIGHT diagonal the coin will walk:
	# (0,0) → (1,1) → (2,2) → (3,3) → (4,4).
	for row in range(0, 5):
		b.place_deflector(b.peg_index(row, row), Enums.Direction.RIGHT)
	# roll 0.55 < bias (6/7): every visited deflector is followed RIGHT, so the
	# funnel beats the otherwise-LEFT legacy roll → last bucket.
	assert_equal(_simulate(b, [0.55]), 5, "deflector funnel steers rolls → bucket 5")
	b.free()
