extends "res://test/test_base.gd"

## Board tilt tests — run with:
##   godot --headless --scene res://test/test_board_tilt.tscn
##
## Blue's signature upgrade: a per-board slider biasing each bounce toward the
## board's centre column or away from it.
##
## BoardTilt is a pure static module, so the maths runs with no board at all.
## The one thing that genuinely needs a board — that a default slider leaves the
## legacy 50/50 bit-identical — is asserted against a real PlinkoBoard, because
## that is the property the existing trajectory tests depend on.


func _run_tests() -> void:
	print("\n=== Board Tilt Tests ===\n")

	test_unowned_upgrade_is_a_fair_coin()
	test_extreme_bias_starts_at_55()
	test_extreme_bias_climbs_per_level()
	test_extreme_bias_is_capped()
	test_half_notches_apply_half_the_strength()
	test_default_notch_is_always_fair()
	test_toward_centre_depends_on_which_side()
	test_toward_centre_is_exact_at_dead_centre()
	test_centre_setting_pulls_both_sides_inward()
	test_edges_setting_pushes_both_sides_outward()
	test_roll_boundary_follows_the_bias()
	test_no_opinion_when_untilted_or_unowned()
	test_notch_is_clamped()
	test_default_notch_preserves_legacy_bounce()
	test_deflector_wins_over_tilt()
	test_labels_name_only_the_ends()
	test_tres_description_matches_the_constants()

	print("\n=== Done ===\n")


# --- Strength curve ---

func test_unowned_upgrade_is_a_fair_coin() -> void:
	print("test_unowned_upgrade_is_a_fair_coin")
	assert_near(BoardTilt.bias_at_extreme(0), 0.5, 0.0001,
		"level 0 is a fair coin even at a full slider")
	assert_near(BoardTilt.bias_for(0, BoardTilt.NOTCH_CENTRE), 0.5, 0.0001,
		"and the slider can't bias what isn't owned")


func test_extreme_bias_starts_at_55() -> void:
	print("test_extreme_bias_starts_at_55")
	assert_near(BoardTilt.bias_at_extreme(1), 0.55, 0.0001,
		"level 1 is a 55/45 split at the extremes")


func test_extreme_bias_climbs_per_level() -> void:
	print("test_extreme_bias_climbs_per_level")
	assert_near(BoardTilt.bias_at_extreme(2), 0.575, 0.0001, "level 2 adds 2.5%")
	assert_near(BoardTilt.bias_at_extreme(5), 0.65, 0.0001, "level 5 reaches 65%")
	assert_true(BoardTilt.bias_at_extreme(4) > BoardTilt.bias_at_extreme(3),
		"each level strictly increases the strength")


func test_extreme_bias_is_capped() -> void:
	print("test_extreme_bias_is_capped")
	# Cap raises push levels far past the .tres max_level. A board that lands
	# every coin in one bucket stops being a Plinko board.
	assert_near(BoardTilt.bias_at_extreme(9999), 0.75, 0.0001,
		"the bias never exceeds 75/25")


func test_half_notches_apply_half_the_strength() -> void:
	print("test_half_notches_apply_half_the_strength")
	# The two unlabelled stops sit half way, so they get half the distance from
	# fair to the extreme — level 1 is 0.55 at the end, so 0.525 here.
	assert_near(BoardTilt.bias_for(1, -1), 0.525, 0.0001, "one notch toward centre")
	assert_near(BoardTilt.bias_for(1, 1), 0.525, 0.0001, "one notch toward edges")
	assert_near(BoardTilt.bias_for(1, BoardTilt.NOTCH_CENTRE), 0.55, 0.0001,
		"and the full notch gets the full strength")


func test_default_notch_is_always_fair() -> void:
	print("test_default_notch_is_always_fair")
	for level in [0, 1, 5, 50]:
		assert_near(BoardTilt.bias_for(level, BoardTilt.NOTCH_DEFAULT), 0.5, 0.0001,
			"the default stop is a fair coin at level %d" % level)


# --- Which way is inward ---

func test_toward_centre_depends_on_which_side() -> void:
	print("test_toward_centre_depends_on_which_side")
	# THE property that makes this a centre-seeking tilt rather than a fixed
	# left/right bias: the same setting pulls opposite sides opposite ways.
	# Row 4, col 0 is the far left of that row; col 4 is the far right.
	assert_equal(BoardTilt.toward_centre(4, 0), int(Enums.Direction.RIGHT),
		"a coin left of centre goes RIGHT to come inward")
	assert_equal(BoardTilt.toward_centre(4, 4), int(Enums.Direction.LEFT),
		"a coin right of centre goes LEFT to come inward")


func test_toward_centre_is_exact_at_dead_centre() -> void:
	print("test_toward_centre_is_exact_at_dead_centre")
	# Compared as integers (2*col - row) rather than against a float x, so dead
	# centre is exact instead of an epsilon away from it.
	assert_equal(BoardTilt.toward_centre(4, 2), 0, "row 4 col 2 is dead centre")
	assert_equal(BoardTilt.toward_centre(0, 0), 0, "the apex peg is dead centre")
	# Odd rows have no dead-centre cell at all — every column is on one side.
	assert_true(BoardTilt.toward_centre(3, 1) != 0, "odd rows have no centre cell")
	assert_true(BoardTilt.toward_centre(3, 2) != 0, "and neither column is neutral")


func test_centre_setting_pulls_both_sides_inward() -> void:
	print("test_centre_setting_pulls_both_sides_inward")
	assert_equal(BoardTilt.favoured_direction(4, 0, BoardTilt.NOTCH_CENTRE),
		int(Enums.Direction.RIGHT), "left side is pulled right")
	assert_equal(BoardTilt.favoured_direction(4, 4, BoardTilt.NOTCH_CENTRE),
		int(Enums.Direction.LEFT), "right side is pulled left")


func test_edges_setting_pushes_both_sides_outward() -> void:
	print("test_edges_setting_pushes_both_sides_outward")
	assert_equal(BoardTilt.favoured_direction(4, 0, BoardTilt.NOTCH_EDGES),
		int(Enums.Direction.LEFT), "left side is pushed further left")
	assert_equal(BoardTilt.favoured_direction(4, 4, BoardTilt.NOTCH_EDGES),
		int(Enums.Direction.RIGHT), "right side is pushed further right")


# --- Resolution ---

func test_roll_boundary_follows_the_bias() -> void:
	print("test_roll_boundary_follows_the_bias")
	# Level 1 at a full centre notch is 0.55, so rolls under that go inward.
	var inward: int = int(Enums.Direction.RIGHT)  # row 4 col 0 is left of centre
	assert_equal(BoardTilt.direction_for(4, 0, BoardTilt.NOTCH_CENTRE, 1, 0.54), inward,
		"a roll under the bias goes the favoured way")
	assert_equal(BoardTilt.direction_for(4, 0, BoardTilt.NOTCH_CENTRE, 1, 0.56), -inward,
		"a roll over it goes the other way")
	assert_equal(BoardTilt.direction_for(4, 0, BoardTilt.NOTCH_CENTRE, 1, 0.55), -inward,
		"the boundary itself is exclusive, matching the deflector's convention")


func test_no_opinion_when_untilted_or_unowned() -> void:
	print("test_no_opinion_when_untilted_or_unowned")
	# 0 means "fall through to the normal path" — see the legacy test below for
	# why returning a coin flip here would be wrong.
	assert_equal(BoardTilt.direction_for(4, 0, BoardTilt.NOTCH_DEFAULT, 5, 0.1), 0,
		"a default slider has no opinion")
	assert_equal(BoardTilt.direction_for(4, 0, BoardTilt.NOTCH_CENTRE, 0, 0.1), 0,
		"an unowned upgrade has no opinion")
	assert_equal(BoardTilt.direction_for(4, 2, BoardTilt.NOTCH_CENTRE, 5, 0.1), 0,
		"a dead-centre coin has no inward direction to favour")


func test_notch_is_clamped() -> void:
	print("test_notch_is_clamped")
	# Saves are the untrusted source: a corrupt notch must not scale the bias
	# past the extreme.
	assert_equal(BoardTilt.clamp_notch(-99), BoardTilt.NOTCH_CENTRE, "clamps low")
	assert_equal(BoardTilt.clamp_notch(99), BoardTilt.NOTCH_EDGES, "clamps high")
	assert_near(BoardTilt.bias_for(1, 99), BoardTilt.bias_for(1, BoardTilt.NOTCH_EDGES),
		0.0001, "an out-of-range notch is no stronger than the real extreme")


# --- Board integration ---

func _make_board() -> PlinkoBoard:
	var board := PlinkoBoard.new()
	board.board_type = Enums.BoardType.BLUE
	board.num_rows = 4
	return board


func test_default_notch_preserves_legacy_bounce() -> void:
	print("test_default_notch_preserves_legacy_bounce")
	# The trajectory tests pin `roll < 0.5 -> RIGHT`. A tilt that returned a coin
	# flip at the default stop would invert every left-favouring cell and break
	# them silently, which is exactly why direction_for returns 0 instead.
	UpgradeManager.reset()
	UpgradeManager.get_state(PlinkoBoard.BOARD_TILT_BOARD,
		Enums.UpgradeType.BOARD_TILT).level = 5
	var board := _make_board()
	assert_equal(board.get_tilt_notch(), BoardTilt.NOTCH_DEFAULT,
		"a fresh board starts untilted")
	for cell in [Vector2i(4, 0), Vector2i(4, 2), Vector2i(4, 4), Vector2i(1, 0)]:
		assert_equal(board.resolve_bounce_direction(cell.x, cell.y, 0.4),
			int(Enums.Direction.RIGHT),
			"roll 0.4 still goes RIGHT at (%d, %d)" % [cell.x, cell.y])
		assert_equal(board.resolve_bounce_direction(cell.x, cell.y, 0.6),
			int(Enums.Direction.LEFT),
			"roll 0.6 still goes LEFT at (%d, %d)" % [cell.x, cell.y])
	board.free()
	UpgradeManager.reset()


func test_deflector_wins_over_tilt() -> void:
	print("test_deflector_wins_over_tilt")
	# A deflector is a deliberate placement on a specific peg; the board-wide
	# tilt must not override it, or the player's own choice stops mattering.
	UpgradeManager.reset()
	UpgradeManager.get_state(PlinkoBoard.BOARD_TILT_BOARD,
		Enums.UpgradeType.BOARD_TILT).level = 5
	UpgradeManager.get_state(PlinkoBoard.DEFLECTOR_BOARD,
		Enums.UpgradeType.PEG_DEFLECTOR).level = 1
	var board := _make_board()
	board.set_tilt_notch(BoardTilt.NOTCH_CENTRE)
	# Row 4 col 0 is left of centre, so the tilt favours RIGHT. Point a deflector
	# LEFT there and the deflector's direction must win on a following roll.
	board.place_deflector(board.peg_index(4, 0), Enums.Direction.LEFT)
	assert_equal(board.resolve_bounce_direction(4, 0, 0.0), int(Enums.Direction.LEFT),
		"the deflector's direction beats the tilt's")
	# A peg with no deflector on the same board still tilts.
	assert_equal(board.resolve_bounce_direction(4, 4, 0.0), int(Enums.Direction.LEFT),
		"an undeflected right-side peg still tilts inward")
	board.free()
	UpgradeManager.reset()


func test_labels_name_only_the_ends() -> void:
	print("test_labels_name_only_the_ends")
	# The middle is the neutral default and the half stops are deliberately
	# unlabelled, so the slider reads as a spectrum rather than five states.
	assert_equal(BoardTilt.notch_label(BoardTilt.NOTCH_CENTRE), "Centre", "left end")
	assert_equal(BoardTilt.notch_label(BoardTilt.NOTCH_EDGES), "Edges", "right end")
	assert_equal(BoardTilt.notch_label(BoardTilt.NOTCH_DEFAULT), "", "the middle is unlabelled")
	assert_equal(BoardTilt.notch_label(-1), "", "and so are the half stops")
	assert_equal(BoardTilt.notch_label(1), "", "on both sides")


## board_tilt.tres quotes the per-level step and the level-1 extreme in prose.
## Pin them so the player-facing text can't quietly become a lie.
func test_tres_description_matches_the_constants() -> void:
	print("test_tres_description_matches_the_constants")
	var data: BaseUpgradeData = UpgradeManager.get_upgrade(Enums.UpgradeType.BOARD_TILT)
	assert_true(data != null, "the board tilt upgrade resource is registered")
	if data:
		var step: String = "%.1f%%" % (BoardTilt.BIAS_PER_EXTRA_LEVEL * 100.0)
		assert_true(data.description.contains(step),
			"description quotes the live per-level step (%s)" % step)
		var first: int = roundi(BoardTilt.LEVEL_1_EXTREME_BIAS * 100.0)
		assert_true(data.description.contains("%d/%d" % [first, 100 - first]),
			"description quotes the live level-1 split (%d/%d)" % [first, 100 - first])
