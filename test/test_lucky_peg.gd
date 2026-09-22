extends "res://test/test_base.gd"

## Lucky peg tests — run with:
##   godot --headless --scene res://test/test_lucky_peg.tscn
##
## A wandering peg that splits any coin striking it into two, one each way, both
## at full value. Splits are ordinary coins so they can split again.
##
## Timing and selection live in LuckyPegModel, which is a plain RefCounted with
## injected Callables — so the wander, the respawn gap, the rebuild trim and the
## bomb eviction are all exercised here for real, with a pinned RNG and no scene
## tree. Earlier versions of this suite could only assert around the edges of a
## board-owned implementation, which is how a tautology test slipped through.


func _run_tests() -> void:
	print("\n=== Lucky Peg Tests ===\n")

	test_count_follows_level()
	test_split_rate_is_bounded_by_the_respawn_gap()
	test_candidates_cover_every_peg()
	test_candidates_skip_voided_cells()
	test_candidates_skip_taken_pegs()
	test_candidates_empty_when_everything_taken()
	test_tick_spawns_up_to_the_target()
	test_tick_reports_what_it_spawned()
	test_tick_never_double_books_a_peg()
	test_peg_expires_after_its_duration()
	test_fade_progress_runs_forward_as_it_expires()
	test_consume_is_one_shot()
	test_consume_ignores_other_pegs()
	test_consume_queues_a_respawn_and_holds_the_slot()
	test_respawn_gap_elapses_then_refills()
	test_target_zero_tears_everything_down()
	test_rebuild_drops_pegs_off_the_new_lattice()
	test_bomb_releases_a_peg_under_a_voided_column()
	test_peg_index_round_trips_with_the_board()
	test_tres_description_matches_the_per_level_slope()

	print("\n=== Done ===\n")


## A model with deterministic RNG (always the first candidate) and no voids.
func _make_model(level: int = 1) -> LuckyPegModel:
	var m := LuckyPegModel.new()
	m.target_count_fn = func() -> int: return LuckyPegModel.count_for_level(level)
	m.rng_fn = func(_n: int) -> int: return 0
	return m


# --- Level -> count ---

func test_count_follows_level() -> void:
	print("test_count_follows_level")
	# One peg per level, so buying the upgrade immediately puts one on every
	# board rather than only raising a chance.
	assert_equal(LuckyPegModel.count_for_level(0), 0, "unowned means no pegs")
	assert_equal(LuckyPegModel.count_for_level(1), 1, "level 1 is one peg")
	assert_equal(LuckyPegModel.count_for_level(4), 4, "level 4 is four pegs")
	# Defensive: only corrupt state produces a negative, but it would make the
	# top-up loop misbehave rather than no-op.
	assert_equal(LuckyPegModel.count_for_level(-3), 0, "negative clamps to none")


func test_split_rate_is_bounded_by_the_respawn_gap() -> void:
	print("test_split_rate_is_bounded_by_the_respawn_gap")
	# THE reason uncapped splitting is safe, and worth pinning because the
	# intuitive argument is wrong: "a peg is consumed, so one descent crosses at
	# most `level` pegs" is FALSE — respawns refill mid-descent. What actually
	# holds is a rate: every split consumes a peg, and pegs only return after
	# respawn_delay, so a board cannot exceed level/respawn_delay splits/sec
	# however large the board or however deep the split tree.
	assert_near(LuckyPegModel.max_splits_per_second(5, 0.5), 10.0, 0.0001,
		"max level at a 0.5s gap is 10 splits/sec per board")
	assert_near(LuckyPegModel.max_splits_per_second(1, 0.5), 2.0, 0.0001,
		"level 1 is 2 splits/sec per board")
	assert_equal(LuckyPegModel.max_splits_per_second(0, 0.5), 0.0,
		"an unowned upgrade produces no splits at all")
	# Halving the gap doubles the ceiling — the knob to reach for if it ever
	# does need bounding.
	assert_true(LuckyPegModel.max_splits_per_second(5, 0.25)
			> LuckyPegModel.max_splits_per_second(5, 0.5),
		"a shorter respawn gap raises the ceiling")


# --- Candidate set ---

func test_candidates_cover_every_peg() -> void:
	print("test_candidates_cover_every_peg")
	# A 4-row lattice holds 1+2+3+4 = 10 pegs, and all of them are fair game.
	var c: PackedInt32Array = LuckyPegModel.candidates(4, [],
		func(_r: int, _c: int) -> bool: return false)
	assert_equal(c.size(), 10, "every peg on a 4-row lattice is a candidate")
	assert_true(0 in c, "the apex peg is included")
	assert_true(9 in c, "the last peg of the bottom row is included")


func test_candidates_skip_voided_cells() -> void:
	print("test_candidates_skip_voided_cells")
	# A bomb destroys a column; a lucky peg must never light up on a peg that is
	# no longer there. The wander inherits this by asking the board rather than
	# tracking voids itself.
	var voided := func(row: int, col: int) -> bool: return row == 1 and col == 0
	var c: PackedInt32Array = LuckyPegModel.candidates(4, [], voided)
	assert_equal(c.size(), 9, "the voided peg is excluded")
	assert_false(1 in c, "peg index 1 is (row 1, col 0) and is voided")
	assert_true(2 in c, "its neighbour is unaffected")


func test_candidates_skip_taken_pegs() -> void:
	print("test_candidates_skip_taken_pegs")
	# Two lucky pegs must never share a peg, or consuming one would silently
	# drop the other.
	var c: PackedInt32Array = LuckyPegModel.candidates(4, [0, 5],
		func(_r: int, _c: int) -> bool: return false)
	assert_equal(c.size(), 8, "both taken pegs are excluded")
	assert_false(0 in c, "an occupied peg is not a candidate")
	assert_false(5 in c, "nor is the second")


func test_candidates_empty_when_everything_taken() -> void:
	print("test_candidates_empty_when_everything_taken")
	# A tiny board with every peg occupied must yield nothing rather than
	# looping or handing back an occupied index.
	var c: PackedInt32Array = LuckyPegModel.candidates(1, [0],
		func(_r: int, _c: int) -> bool: return false)
	assert_equal(c.size(), 0, "no candidates left")


# --- Wander ---

func test_tick_spawns_up_to_the_target() -> void:
	print("test_tick_spawns_up_to_the_target")
	var m := _make_model(3)
	m.tick(0.016, 4)
	assert_equal(m.count(), 3, "the board fills to the level's count on the first tick")
	m.tick(0.016, 4)
	assert_equal(m.count(), 3, "and does not keep adding once full")


func test_tick_reports_what_it_spawned() -> void:
	print("test_tick_reports_what_it_spawned")
	# The board repaints only what changed, so tick must report it accurately —
	# a missed index is a marker that never appears.
	var m := _make_model(2)
	var events: Dictionary = m.tick(0.016, 4)
	assert_equal(events["spawned"].size(), 2, "both new pegs are reported")
	assert_equal(events["retired"].size(), 0, "nothing retired on the first tick")
	for peg_idx: int in events["spawned"]:
		assert_true(m.has(peg_idx), "a reported peg is actually live")


func test_tick_never_double_books_a_peg() -> void:
	print("test_tick_never_double_books_a_peg")
	# RNG pinned to index 0 every time: without the taken-filter both pegs would
	# land on the same index and one would be lost.
	var m := _make_model(3)
	m.tick(0.016, 4)
	assert_equal(m.live().size(), 3, "three distinct pegs are live")
	var seen: Dictionary = {}
	for peg_idx: int in m.live():
		assert_false(seen.has(peg_idx), "peg %d is not booked twice" % peg_idx)
		seen[peg_idx] = true


func test_peg_expires_after_its_duration() -> void:
	print("test_peg_expires_after_its_duration")
	var m := _make_model(1)
	m.duration = 1.0
	# Long gap so this tick can't also drain the respawn and refill: with the RNG
	# pinned to the first candidate, an immediate refill would re-pick the very
	# peg that just expired and the assertion below would read as a failure to
	# retire. (That refill IS correct when the gap really has elapsed — see
	# test_respawn_gap_elapses_then_refills.)
	m.respawn_delay = 60.0
	m.tick(0.016, 4)
	var original: int = m.live()[0]
	var events: Dictionary = m.tick(1.0, 4)
	assert_true(original in events["retired"], "the expired peg is reported retired")
	assert_false(m.has(original), "and is no longer live")


func test_fade_progress_runs_forward_as_it_expires() -> void:
	print("test_fade_progress_runs_forward_as_it_expires")
	# 0 -> 1 as the peg dies, so the board can lerp marker -> peg colour by it.
	# Getting this backwards would make a peg BRIGHTEN as it was about to vanish.
	var m := _make_model(1)
	m.duration = 4.0
	m.fade_start = 1.0
	m.tick(0.016, 4)
	var peg_idx: int = m.live()[0]
	assert_equal(m.fade_progress(peg_idx), 0.0, "a fresh peg is not fading")
	m.tick(3.5, 4)  # ~0.5s left, half way into the fade window
	var mid: float = m.fade_progress(peg_idx)
	assert_true(mid > 0.0 and mid < 1.0, "mid-fade is strictly between 0 and 1, got %f" % mid)
	m.tick(0.4, 4)  # ~0.1s left
	assert_true(m.fade_progress(peg_idx) > mid, "fade progress increases as it expires")
	assert_equal(m.fade_progress(9999), 0.0, "an unknown peg is never fading")


# --- Consume ---

func test_consume_is_one_shot() -> void:
	print("test_consume_is_one_shot")
	# Consuming is what stops a second coin arriving in the same frame from
	# claiming the same peg twice — and it is what makes the rate bound hold.
	var m := _make_model(1)
	m.tick(0.016, 4)
	var peg_idx: int = m.live()[0]
	assert_true(m.try_consume(peg_idx), "the first coin splits")
	assert_false(m.try_consume(peg_idx), "the second coin does not")


func test_consume_ignores_other_pegs() -> void:
	print("test_consume_ignores_other_pegs")
	var m := _make_model(1)
	m.tick(0.016, 4)
	var peg_idx: int = m.live()[0]
	assert_false(m.try_consume(peg_idx + 1), "a neighbouring peg is not lucky")
	assert_true(m.has(peg_idx), "and the real one is untouched")


func test_consume_queues_a_respawn_and_holds_the_slot() -> void:
	print("test_consume_queues_a_respawn_and_holds_the_slot")
	# The board must be lucky-peg-free for the gap rather than re-lighting
	# instantly, or the peg would look like it never moved. The queued respawn
	# also has to hold the slot, or the top-up would refill it the same frame.
	var m := _make_model(1)
	m.tick(0.016, 4)
	m.try_consume(m.live()[0])
	assert_equal(m.count(), 0, "the peg is gone immediately")
	assert_equal(m.pending_respawns(), 1, "a respawn is queued")
	m.tick(0.016, 4)
	assert_equal(m.count(), 0, "and the slot stays empty during the gap")


func test_respawn_gap_elapses_then_refills() -> void:
	print("test_respawn_gap_elapses_then_refills")
	var m := _make_model(1)
	m.respawn_delay = 0.5
	m.tick(0.016, 4)
	m.try_consume(m.live()[0])
	m.tick(0.6, 4)   # gap elapses on this tick
	assert_equal(m.pending_respawns(), 0, "the gap has elapsed")
	m.tick(0.016, 4)
	assert_equal(m.count(), 1, "the board refills to its target")


func test_target_zero_tears_everything_down() -> void:
	print("test_target_zero_tears_everything_down")
	# Prestige and challenge entry both reset UpgradeManager to level 0; live
	# markers must come down rather than linger on a board that no longer owns
	# the upgrade.
	# GDScript lambdas capture by VALUE, so the level has to live behind a
	# reference type for the test to be able to change it mid-run.
	var level: Array[int] = [2]
	var m := LuckyPegModel.new()
	m.target_count_fn = func() -> int: return LuckyPegModel.count_for_level(level[0])
	m.rng_fn = func(_n: int) -> int: return 0
	m.tick(0.016, 4)
	assert_equal(m.count(), 2, "two pegs while owned")

	level[0] = 0
	var events: Dictionary = m.tick(0.016, 4)
	assert_equal(m.count(), 0, "everything is torn down")
	assert_equal(events["retired"].size(), 2, "both are reported so the board unpaints them")
	assert_equal(m.pending_respawns(), 0, "and no respawn is left queued")


# --- Rebuild + bomb interaction ---

func test_rebuild_drops_pegs_off_the_new_lattice() -> void:
	print("test_rebuild_drops_pegs_off_the_new_lattice")
	# Peg indices are rebuilt from scratch by build_board. An index past the end
	# of the new lattice must be dropped, not left pointing at whatever peg now
	# occupies that slot.
	var m := _make_model(1)
	m._live[99] = 5.0
	var dropped: Array[int] = m.drop_pegs_beyond(4)  # 10 pegs, so 99 is off the end
	assert_true(99 in dropped, "the off-lattice peg is dropped")
	assert_false(m.has(99), "and is no longer live")
	assert_equal(m.pending_respawns(), 1, "its slot is queued for a replacement")


func test_bomb_releases_a_peg_under_a_voided_column() -> void:
	print("test_bomb_releases_a_peg_under_a_voided_column")
	# The spawn filter refuses voided cells; this is the symmetric half, for a
	# column voided UNDER a live peg. Without it the marker goes invisible but
	# keeps holding a slot until it expires.
	var m := _make_model(1)
	m.tick(0.016, 4)
	var peg_idx: int = m.live()[0]
	var released: Array[int] = m.release_pegs(PackedInt32Array([peg_idx]))
	assert_true(peg_idx in released, "the peg under the blast is released")
	assert_false(m.has(peg_idx), "and is no longer live")
	assert_equal(m.pending_respawns(), 1, "a replacement is queued")

	assert_equal(m.release_pegs(PackedInt32Array([peg_idx])).size(), 0,
		"releasing a peg that isn't live is a no-op")


# --- Index mapping ---

func test_peg_index_round_trips_with_the_board() -> void:
	print("test_peg_index_round_trips_with_the_board")
	# The model keys pegs by Lattice.peg_index and the board paints PegField by
	# the same index. If those disagreed a lucky peg would light one peg and pay
	# out on another, so pin them against each other.
	var board := PlinkoBoard.new()
	board.num_rows = 5
	var seen: Dictionary = {}
	for row in 5:
		for col in row + 1:
			var idx: int = Lattice.peg_index(row, col)
			assert_equal(board.peg_index(row, col), idx,
				"board and Lattice agree at (%d, %d)" % [row, col])
			assert_false(seen.has(idx), "index %d is unique" % idx)
			seen[idx] = true
	assert_equal(seen.size(), Lattice.peg_count(5),
		"every peg on the lattice has a distinct index")
	board.free()


## lucky_peg.tres states "+1 lucky peg per board" in player-facing prose, which
## is count_for_level's slope. Pin them so the description can't quietly become
## a lie if the slope ever changes.
func test_tres_description_matches_the_per_level_slope() -> void:
	print("test_tres_description_matches_the_per_level_slope")
	var data: BaseUpgradeData = UpgradeManager.get_upgrade(Enums.UpgradeType.LUCKY_PEG)
	assert_true(data != null, "the lucky peg upgrade resource is registered")
	if data:
		var slope: int = LuckyPegModel.count_for_level(1) - LuckyPegModel.count_for_level(0)
		assert_true(data.description.contains("+%d lucky peg" % slope),
			"description quotes the live per-level slope (+%d)" % slope)
