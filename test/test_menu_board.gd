extends "res://test/test_base.gd"

## MenuBoard / Lattice geometry tests — run with:
##   godot --headless --scene res://test/test_menu_board.tscn
##
## Pure-logic tests on the shared Lattice module and bare PlinkoBoard /
## MenuBoard instances (no scene tree). The parity tests are the drift
## tripwire: the decorative menu board must stay formula-identical to the real
## game board (and a PlinkoBoard change that bypasses Lattice fails here too).

const SPACE := 1.0
const VS := 1.0


func _run_tests() -> void:
	print("\n=== MenuBoard / Lattice Tests ===\n")
	test_lattice_matches_documented_formula()
	test_lattice_parity_with_plinko_board()
	test_menu_board_mirrors_plinko_board()
	test_menu_board_walk_terminates_in_bounds()
	test_pure_method_signatures_unchanged()
	test_chime_progression_is_well_formed()
	test_peg_tick_pitches_are_valid()


# --- Lattice module: pure formula ---

func test_lattice_matches_documented_formula() -> void:
	print("test_lattice_matches_documented_formula")
	for space in [0.5, 1.0, 1.7]:
		assert_near(Lattice.vertical_spacing(space), space * sqrt(3.0) / 2.0,
			0.0001, "vertical_spacing(%s)" % space)
		for row in range(0, 7):
			for col in range(0, row + 1):
				assert_near(Lattice.x_for(row, col, space),
					-row * space / 2.0 + col * space, 0.0001,
					"x_for(%d,%d,%s)" % [row, col, space])
	assert_equal(Lattice.next_cell(2, 1, Enums.Direction.RIGHT), Vector2i(3, 2),
		"next_cell RIGHT → (row+1, col+1)")
	assert_equal(Lattice.next_cell(2, 1, Enums.Direction.LEFT), Vector2i(3, 1),
		"next_cell LEFT → (row+1, col)")
	var w := Lattice.cell_to_world(2, 1, SPACE, VS, 0.2)
	assert_near(w.x, Lattice.x_for(2, 1, SPACE), 0.0001, "cell_to_world.x")
	assert_near(w.y, 0.2 - 2.0 * VS, 0.0001, "cell_to_world.y (offset - vs*row)")
	assert_near(w.z, 0.0, 0.0001, "cell_to_world.z stays 0")


# --- Parity: PlinkoBoard forwarders must equal Lattice ---

func test_lattice_parity_with_plinko_board() -> void:
	print("test_lattice_parity_with_plinko_board")
	var b := PlinkoBoard.new()
	b.board_type = Enums.BoardType.GOLD
	b.num_rows = 8
	b.space_between_pegs = SPACE
	b.vertical_spacing = VS
	for row in range(0, 9):
		for col in range(0, row + 1):
			assert_near(b.position_x_for(row, col),
				Lattice.x_for(row, col, b.space_between_pegs), 0.0001,
				"position_x_for == Lattice.x_for (%d,%d)" % [row, col])
			var bw := b.cell_to_world(row, col)
			var lw := Lattice.cell_to_world(row, col, b.space_between_pegs,
				b.vertical_spacing, PlinkoBoard.COIN_ROW_Y_OFFSET)
			assert_near(bw.x, lw.x, 0.0001, "cell_to_world.x parity (%d,%d)" % [row, col])
			assert_near(bw.y, lw.y, 0.0001, "cell_to_world.y parity (%d,%d)" % [row, col])
	assert_equal(b.next_lattice_cell(3, 2, Enums.Direction.RIGHT),
		Lattice.next_cell(3, 2, Enums.Direction.RIGHT), "next_lattice_cell parity RIGHT")
	assert_equal(b.next_lattice_cell(3, 2, Enums.Direction.LEFT),
		Lattice.next_cell(3, 2, Enums.Direction.LEFT), "next_lattice_cell parity LEFT")
	b.free()


# --- Parity: MenuBoard mirrors PlinkoBoard cell-for-cell ---

func test_menu_board_mirrors_plinko_board() -> void:
	print("test_menu_board_mirrors_plinko_board")
	var mb := MenuBoard.new()
	mb.space_between_pegs = SPACE
	mb.num_rows = 8
	var b := PlinkoBoard.new()
	b.board_type = Enums.BoardType.GOLD
	b.num_rows = 8
	b.space_between_pegs = SPACE
	b.vertical_spacing = VS
	for row in range(0, 9):
		for col in range(0, row + 1):
			assert_near(mb.position_x_for(row, col), b.position_x_for(row, col),
				0.0001, "MenuBoard.position_x_for == PlinkoBoard (%d,%d)" % [row, col])
	assert_equal(mb.next_lattice_cell(4, 2, Enums.Direction.RIGHT),
		b.next_lattice_cell(4, 2, Enums.Direction.RIGHT), "next_lattice_cell parity")
	assert_false(mb.is_terminal_cell(7, 0), "row 7 of 8 is not terminal")
	assert_true(mb.is_terminal_cell(8, 0), "row 8 of 8 is terminal")
	mb.free()
	b.free()


# --- A decorative coin always stays in bounds and terminates ---

func test_menu_board_walk_terminates_in_bounds() -> void:
	print("test_menu_board_walk_terminates_in_bounds")
	var mb := MenuBoard.new()
	mb.space_between_pegs = SPACE
	mb.num_rows = MenuBoard.MENU_BOARD_ROWS
	var row := 0
	var col := 0
	var steps := 0
	while not mb.is_terminal_cell(row, col):
		assert_true(col >= 0 and col <= row, "col within 0..row at step %d" % steps)
		var dir: int = Enums.Direction.RIGHT if steps % 2 == 0 else Enums.Direction.LEFT
		var next: Vector2i = mb.next_lattice_cell(row, col, dir)
		row = next.x
		col = next.y
		steps += 1
		assert_true(steps <= mb.num_rows + 1, "walk terminates within num_rows steps")
	assert_equal(row, mb.num_rows, "walk ends exactly at the terminal row")
	mb.free()


# --- Authored chime sequence: data shape ---

func test_chime_progression_is_well_formed() -> void:
	print("test_chime_progression_is_well_formed")
	# Every chord has a name and a non-empty notes array; every note parses to a
	# positive pitch_mult (the sequencer expects parallel pitch arrays in _ready).
	assert_true(MenuBoard.PEG_CHIME_PROGRESSION.size() > 0, "progression is non-empty")
	for chord_entry: Dictionary in MenuBoard.PEG_CHIME_PROGRESSION:
		assert_true(chord_entry.has("name") and chord_entry["name"] != "",
			"chord entry has a name")
		var notes: Array = chord_entry["notes"]
		assert_true(notes.size() > 0, "chord %s has notes" % chord_entry["name"])
		for note: String in notes:
			var pitch: float = SoftChime.note_name_to_pitch_mult(note)
			assert_true(pitch > 0.0,
				"note %s in %s parses to a positive pitch_mult" % [note, chord_entry["name"]])


## Peg-tick contract: `_try_play_peg_tick` picks a random note from the
## currently-active chord and shifts it by PEG_TICK_PITCH_MULT before handing
## off to the PegTick noise instrument (whose pre-rendered sample sounds
## sluggish/muddy at sub-1.0 pitch_scales). This regression-guards the
## "shifted chord note → positive pitch_mult" contract: any future progression
## edit that authored a 0 or negative pitch, or any flip of PEG_TICK_PITCH_MULT
## to a non-positive value, fails here before it can produce a silent or
## reversed playback.
func test_peg_tick_pitches_are_valid() -> void:
	print("test_peg_tick_pitches_are_valid")
	assert_true(MenuBoard.PEG_TICK_PITCH_MULT > 0.0,
		"PEG_TICK_PITCH_MULT is a positive multiplier")
	assert_true(MenuBoard.PEG_TICK_VOLUME_OFFSET_DB < 0.0,
		"PEG_TICK_VOLUME_OFFSET_DB is negative (tick sits under the chord bed)")
	for chord_entry: Dictionary in MenuBoard.PEG_CHIME_PROGRESSION:
		var notes: Array = chord_entry["notes"]
		for note: String in notes:
			var pitch: float = SoftChime.note_name_to_pitch_mult(note) \
				* MenuBoard.PEG_TICK_PITCH_MULT
			assert_true(pitch > 0.0,
				"shifted pitch for %s in %s is positive" % [note, chord_entry["name"]])


## Tripwire: the wobble/`direction` rework must not break the bare-instance
## pure contract the other tests (and PlinkoBoard parity) rely on — these
## methods stay callable on `MenuBoard.new()` with no tree/_ready/ThemeProvider.
func test_pure_method_signatures_unchanged() -> void:
	print("test_pure_method_signatures_unchanged")
	var mb := MenuBoard.new()
	mb.space_between_pegs = SPACE
	mb.num_rows = 5
	assert_near(mb.position_x_for(2, 1), -2 * SPACE / 2.0 + 1 * SPACE, 0.0001,
		"position_x_for callable & correct on bare instance")
	assert_equal(mb.next_lattice_cell(2, 1, Enums.Direction.RIGHT), Vector2i(3, 2),
		"next_lattice_cell callable & correct")
	assert_false(mb.is_terminal_cell(4, 0), "is_terminal_cell 4<5")
	assert_true(mb.is_terminal_cell(5, 0), "is_terminal_cell 5>=5")
	assert_equal(mb._peg_index(2, 1), 4, "_peg_index triangular formula")
	mb.free()
