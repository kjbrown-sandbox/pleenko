extends "res://test/test_base.gd"

## Dud chute tests — run with:
##   godot --headless --scene res://test/test_dud_chute.tscn
##
## The chute turns every board's dead-centre bucket (pinned to value 1 by
## _bucket_value_for_distance) into a lottery: the coin falls through to the
## board BEHIND, worth DUD_CHUTE_MULTIPLIER times whatever it lands in there,
## and can chain backwards tier by tier with the multiplier compounding.
##
## Everything here runs on bare instances — the decision half
## (should_open_dud_chute) is deliberately free of emits and coin mutation, and
## the roll is injected, so no RNG and no scene tree are involved.


func _run_tests() -> void:
	print("\n=== Dud Chute Tests ===\n")

	test_chance_is_zero_when_unowned()
	test_chance_scales_with_level()
	test_chance_clamps_to_one()
	test_never_fires_at_zero_chance()
	test_fires_strictly_below_chance()
	test_centre_index_is_the_only_middle_bucket()
	test_centre_index_across_board_growth()
	test_opens_on_centre_landing()
	test_ignores_non_centre_landing()
	test_ignores_prestige_coin()
	test_gateway_wins_over_centre()
	test_board_behind_is_previous_tier()
	test_gold_has_no_board_behind()
	test_board_behind_unknown_board()
	test_multiplier_compounds_per_hop()

	print("\n=== Done ===\n")


func _make_board(num_rows: int = 4, board_type: Enums.BoardType = Enums.BoardType.VIOLET) -> PlinkoBoard:
	var board := PlinkoBoard.new()
	board.board_type = board_type
	board.num_rows = num_rows
	return board


func _set_level(n: int) -> void:
	UpgradeManager.get_state(PlinkoBoard.DUD_CHUTE_BOARD, Enums.UpgradeType.DUD_CHUTE).level = n


# --- Chance curve (pure) ---

func test_chance_is_zero_when_unowned() -> void:
	print("test_chance_is_zero_when_unowned")
	assert_equal(PlinkoBoard.dud_chute_chance_for_level(0), 0.0,
		"level 0 (not owned) is a 0% chance")


func test_chance_scales_with_level() -> void:
	print("test_chance_scales_with_level")
	# The upgrade raises the CHANCE only — the multiplier is fixed, so a long
	# chain is what makes a payout big, not a high level.
	assert_true(is_equal_approx(PlinkoBoard.dud_chute_chance_for_level(1), 0.02),
		"level 1 is 2%")
	assert_true(is_equal_approx(PlinkoBoard.dud_chute_chance_for_level(5), 0.10),
		"level 5 is 10%")
	assert_true(PlinkoBoard.dud_chute_chance_for_level(3) > PlinkoBoard.dud_chute_chance_for_level(2),
		"each level strictly increases the chance")


func test_chance_clamps_to_one() -> void:
	print("test_chance_clamps_to_one")
	# Cap raises can push levels far past the .tres max_level, and a chance
	# above 1.0 would make dud_chute_fires always true in a way the odds text
	# could not honestly describe.
	assert_equal(PlinkoBoard.dud_chute_chance_for_level(9999), 1.0,
		"chance never exceeds 100%")


# --- Roll comparison (pure) ---

func test_never_fires_at_zero_chance() -> void:
	print("test_never_fires_at_zero_chance")
	# The guard that matters: randf() can return exactly 0.0, and `roll < chance`
	# alone would still be false at chance 0 — but only because 0 < 0 is false.
	# Assert it explicitly so an unowned upgrade can never fire.
	assert_false(PlinkoBoard.dud_chute_fires(0.0, 0.0),
		"a roll of exactly 0.0 does not fire an unowned chute")


func test_fires_strictly_below_chance() -> void:
	print("test_fires_strictly_below_chance")
	assert_true(PlinkoBoard.dud_chute_fires(0.01, 0.02), "roll below chance fires")
	assert_false(PlinkoBoard.dud_chute_fires(0.02, 0.02), "roll equal to chance does not fire")
	assert_false(PlinkoBoard.dud_chute_fires(0.5, 0.02), "roll above chance does not fire")


# --- Centre bucket identification ---

func test_centre_index_is_the_only_middle_bucket() -> void:
	print("test_centre_index_is_the_only_middle_bucket")
	# 5 buckets -> distances [2,1,0,1,2]; index 2 is the unique distance-0 slot.
	assert_equal(PlinkoBoard.centre_bucket_index(5), 2, "5 buckets -> centre index 2")
	assert_equal(PlinkoBoard.centre_bucket_index(3), 1, "3 buckets -> centre index 1")


func test_centre_index_across_board_growth() -> void:
	print("test_centre_index_across_board_growth")
	# Bucket counts are always odd (num_buckets = num_rows + 1, rows grow by 2),
	# so there is never a tie to resolve. Walk the real growth sequence.
	for rows in [2, 4, 6, 8, 10]:
		var num_buckets: int = rows + 1
		var centre: int = PlinkoBoard.centre_bucket_index(num_buckets)
		assert_equal(num_buckets % 2, 1, "bucket count stays odd at %d rows" % rows)
		assert_equal(num_buckets - 1 - centre, centre,
			"centre is equidistant from both edges at %d rows" % rows)


# --- Decision (bare board, injected roll) ---

func test_opens_on_centre_landing() -> void:
	print("test_opens_on_centre_landing")
	_set_level(1)
	var board := _make_board(4)  # 5 buckets, centre index 2
	assert_true(board.should_open_dud_chute(2, false, 0.0),
		"a centre landing under the chance opens the chute")
	board.free()
	UpgradeManager.reset()


func test_ignores_non_centre_landing() -> void:
	print("test_ignores_non_centre_landing")
	_set_level(5)
	var board := _make_board(4)
	# Roll 0.0 would fire anywhere the bucket qualified, so a false here is
	# entirely due to the bucket index.
	for idx in [0, 1, 3, 4]:
		assert_false(board.should_open_dud_chute(idx, false, 0.0),
			"bucket %d is not the centre, so the chute stays shut" % idx)
	board.free()
	UpgradeManager.reset()


func test_ignores_prestige_coin() -> void:
	print("test_ignores_prestige_coin")
	# PrestigeAnimator owns a prestige coin's lifecycle; re-dropping one on
	# another board would strand that cinematic.
	_set_level(5)
	var board := _make_board(4)
	assert_false(board.should_open_dud_chute(2, true, 0.0),
		"a prestige coin never falls through the chute")
	board.free()
	UpgradeManager.reset()


func test_gateway_wins_over_centre() -> void:
	print("test_gateway_wins_over_centre")
	# On a 1-bucket board index 0 is both the centre AND an edge. A gateway pays
	# nothing and drops into an earring, so the gateway reading must win.
	_set_level(5)
	var board := _make_board(0)  # 1 bucket
	board._earring_rows = 2
	assert_false(board.should_open_dud_chute(0, false, 0.0),
		"a gateway bucket never opens the chute, even at the centre index")
	board.free()
	UpgradeManager.reset()


# --- Routing (BoardManager owns board-to-board) ---

func _make_board_manager(types: Array) -> BoardManager:
	var bm := BoardManager.new()
	for t in types:
		var b := PlinkoBoard.new()
		b.board_type = t
		bm._boards.append(b)
	return bm


func test_board_behind_is_previous_tier() -> void:
	print("test_board_behind_is_previous_tier")
	var bm := _make_board_manager([
		Enums.BoardType.GOLD, Enums.BoardType.ORANGE, Enums.BoardType.RED])
	var behind: PlinkoBoard = bm.get_board_behind(Enums.BoardType.RED)
	assert_true(behind != null, "red has a board behind it")
	assert_equal(behind.board_type, Enums.BoardType.ORANGE,
		"the board behind red is orange")
	bm.free()


func test_gold_has_no_board_behind() -> void:
	print("test_gold_has_no_board_behind")
	# Gold is the first tier, so a gold centre landing simply ends there.
	var bm := _make_board_manager([Enums.BoardType.GOLD, Enums.BoardType.ORANGE])
	assert_true(bm.get_board_behind(Enums.BoardType.GOLD) == null,
		"gold has nothing behind it")
	bm.free()


func test_board_behind_unknown_board() -> void:
	print("test_board_behind_unknown_board")
	# A board that isn't spawned yet must not resolve to some arbitrary sibling.
	var bm := _make_board_manager([Enums.BoardType.GOLD])
	assert_true(bm.get_board_behind(Enums.BoardType.GREEN) == null,
		"an unspawned board has no board behind it")
	bm.free()


# --- Compounding ---

func test_multiplier_compounds_per_hop() -> void:
	print("test_multiplier_compounds_per_hop")
	# Each hop multiplies the coin's existing multiplier rather than replacing
	# it, which is what makes a long chain explosive: green -> gold is 10^5.
	var mult: float = 1.0
	for hop in 5:
		mult *= PlinkoBoard.DUD_CHUTE_MULTIPLIER
	assert_true(is_equal_approx(mult, 100000.0),
		"five hops compound to 10^5, not 5x10")
	assert_true(is_equal_approx(PlinkoBoard.DUD_CHUTE_MULTIPLIER, 10.0),
		"one hop is 10x")
