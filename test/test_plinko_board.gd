extends "res://test/test_base.gd"

## PlinkoBoard tests — run with:
##   godot --headless --scene res://test/test_plinko_board.tscn
##
## Tests pure-logic functions on a bare PlinkoBoard instance (no scene tree,
## no @onready nodes). We set member vars directly and call the functions.


func _run_tests() -> void:
	print("\n=== PlinkoBoard Tests ===\n")

	test_bucket_value_basic()
	test_bucket_value_with_multiplier()
	test_bucket_value_no_advanced_offset()
	test_bucket_value_linear_at_all_distances()
	test_bucket_position_key_positive()
	test_bucket_position_key_negative()
	test_bucket_position_key_zero()
	test_get_bounds_geometry()
	test_has_in_flight_coins_empty()
	test_hold_drop_first_press_fires_immediately()
	test_hold_drop_rate_limited_to_interval()
	test_hold_drop_release_resets_accumulator()
	test_hold_drop_advanced_uses_same_accumulator()
	test_reconcile_reward_ignores_wrong_type()
	test_reconcile_reward_ignores_wrong_board()
	test_reconcile_reward_ignores_already_set()
	test_queue_rate_bonus_gold_zero_grants_is_base()
	test_queue_rate_bonus_gold_applies_grant_count()
	test_queue_rate_bonus_non_gold_stays_base()
	test_row_upgrade_start_offset_is_two_vertical_spacings()
	test_row_upgrade_schedule_monotonic()
	test_row_upgrade_glissando_degrees_ascend()
	test_row_upgrade_new_pegs_revealed_left_to_right()
	test_needs_tooltip_show_when_unaffordable()
	test_needs_tooltip_hide_when_affordable()
	test_needs_tooltip_keep_when_hovered_unaffordable()
	test_needs_tooltip_keep_when_hovered_affordable()
	test_bomb_cut_side_left_for_below_center()
	test_bomb_cut_side_center_returns_zero()
	test_bomb_cut_side_right_for_above_center()
	test_cell_in_cut_left_side()
	test_cell_in_cut_right_side()
	test_peg_indices_on_cut_left_cut()
	test_peg_indices_on_cut_center_takes_all()
	test_buckets_on_cut_left_takes_everything_below()
	test_buckets_on_cut_right_takes_everything_above()
	test_buckets_on_cut_center_takes_whole_board()
	test_should_fall_through_static_helper()
	test_void_column_saws_off_one_side()
	test_get_reachable_bucket_indices_no_voids_is_all()
	test_get_reachable_bucket_indices_after_left_cut()
	test_get_targetable_bucket_indices_excludes_edges()
	test_void_column_idempotent()
	test_shift_voided_columns_handles_add_rows()
	test_is_lattice_cell_voided_radius_inside()
	test_is_lattice_cell_voided_radius_outside()
	test_is_lattice_cell_voided_bucket_row_uses_destroyed_set()
	test_is_lattice_cell_voided_unions_column_and_radius()
	test_voided_radii_cleared_with_markings()


# --- Helper ---

## Creates a bare PlinkoBoard with no scene tree. Only member vars are
## available — @onready fields are null. Sufficient for pure-logic tests.
func _make_board(overrides: Dictionary = {}) -> PlinkoBoard:
	var board := PlinkoBoard.new()
	board.board_type = overrides.get("board_type", Enums.BoardType.GOLD)
	board.num_rows = overrides.get("num_rows", 4)
	board.bucket_value_multiplier = overrides.get("bucket_value_multiplier", 1)
	board.distance_for_advanced_buckets = overrides.get("distance_for_advanced_buckets", 3)
	board.should_show_advanced_buckets = overrides.get("should_show_advanced_buckets", false)
	board.space_between_pegs = overrides.get("space_between_pegs", 1.0)
	board.vertical_spacing = overrides.get("vertical_spacing", 1.0)
	return board


# --- Bucket value tests ---

func test_bucket_value_basic() -> void:
	print("test_bucket_value_basic")
	# multiplier=1, distance=2, no advanced buckets
	# val = 1 + 2 * 1 = 3
	var board := _make_board()
	assert_equal(board._bucket_value_for_distance(2), 3, "1 + 2*1 = 3")
	board.free()


func test_bucket_value_with_multiplier() -> void:
	print("test_bucket_value_with_multiplier")
	# multiplier=3, distance=2
	# val = 1 + 2 * 3 = 7
	var board := _make_board({"bucket_value_multiplier": 3})
	assert_equal(board._bucket_value_for_distance(2), 7, "1 + 2*3 = 7")
	board.free()


## Single-currency model: advanced (raw-currency edge) buckets are removed, so
## there is no distance offset anymore — every bucket scales linearly with its
## distance from centre, regardless of should_show_advanced_buckets.
func test_bucket_value_no_advanced_offset() -> void:
	print("test_bucket_value_no_advanced_offset")
	# distance=4, multiplier=1 → 1 + 4*1 = 5 (no offset even with the legacy flags set)
	var board := _make_board({
		"distance_for_advanced_buckets": 3,
		"should_show_advanced_buckets": true,
	})
	assert_equal(board._bucket_value_for_distance(4), 5,
		"no advanced offset: 1 + 4*1 = 5")
	board.free()


func test_bucket_value_linear_at_all_distances() -> void:
	print("test_bucket_value_linear_at_all_distances")
	# Linear formula holds at every distance now that advanced buckets are gone.
	var board := _make_board({
		"distance_for_advanced_buckets": 3,
		"should_show_advanced_buckets": true,
	})
	assert_equal(board._bucket_value_for_distance(2), 3, "1 + 2*1 = 3")
	assert_equal(board._bucket_value_for_distance(3), 4, "1 + 3*1 = 4 (was the old threshold)")
	board.free()


# --- Bucket position key tests ---

func test_bucket_position_key_positive() -> void:
	print("test_bucket_position_key_positive")
	var board := _make_board()
	# 1.234 * 1000 = 1234
	assert_equal(board._bucket_position_key(1.234), 1234, "positive x -> 1234")
	board.free()


func test_bucket_position_key_negative() -> void:
	print("test_bucket_position_key_negative")
	var board := _make_board()
	# -0.5 * 1000 = -500
	assert_equal(board._bucket_position_key(-0.5), -500, "negative x -> -500")
	board.free()


func test_bucket_position_key_zero() -> void:
	print("test_bucket_position_key_zero")
	var board := _make_board()
	assert_equal(board._bucket_position_key(0.0), 0, "zero x -> 0")
	board.free()


# --- Bounds geometry test ---

func test_get_bounds_geometry() -> void:
	print("test_get_bounds_geometry")
	# num_rows=4, vertical_spacing=1.0, space_between_pegs=1.0
	# top = 1.0 + 0.5 = 1.5
	# bottom = -1.0 * 4 + (1.0/3) - 0.5 = -4 + 0.333 - 0.5 = -4.167
	# half_width = (4/2.0) * 1.0 + 0.5 = 2.5
	# Rect2(-2.5, -4.167, 5.0, 5.667)
	var board := _make_board({"num_rows": 4, "vertical_spacing": 1.0, "space_between_pegs": 1.0})
	var bounds: Rect2 = board.get_bounds()
	assert_near(bounds.position.x, -2.5, 0.01, "bounds x")
	assert_near(bounds.size.x, 5.0, 0.01, "bounds width")
	assert_true(bounds.position.y < 0.0, "bounds bottom is negative")
	assert_true(bounds.size.y > 0.0, "bounds height is positive")
	board.free()


# --- In-flight coins test ---

func test_has_in_flight_coins_empty() -> void:
	print("test_has_in_flight_coins_empty")
	var board := _make_board()
	assert_false(board.has_in_flight_coins(), "no coins in flight on fresh board")
	board.free()


# --- Hold-to-drop pacing tests ---

func test_hold_drop_first_press_fires_immediately() -> void:
	print("test_hold_drop_first_press_fires_immediately")
	var board := _make_board()
	# Accumulator is primed so a fresh press fires on its first tick.
	assert_true(board._tick_hold_drop_accumulator(0.016, true), "first frame of press fires")
	board.free()


func test_hold_drop_rate_limited_to_interval() -> void:
	print("test_hold_drop_rate_limited_to_interval")
	var board := _make_board()
	# Burn the priming fire so we're measuring from a fresh accumulator at 0.
	assert_true(board._tick_hold_drop_accumulator(0.016, true), "primed fire")
	# 60 fps frames totaling ~99ms: still under the 100ms interval.
	for i in 6:
		assert_false(board._tick_hold_drop_accumulator(0.0165, true), "frame %d should not fire" % i)
	# Next frame crosses 100ms total → fires.
	assert_true(board._tick_hold_drop_accumulator(0.0165, true), "fires after >=100ms accumulated")
	board.free()


func test_hold_drop_release_resets_accumulator() -> void:
	print("test_hold_drop_release_resets_accumulator")
	var board := _make_board()
	# Hold long enough to fire and start a fresh interval.
	board._tick_hold_drop_accumulator(0.016, true)
	board._tick_hold_drop_accumulator(0.05, true)  # accumulator at 0.05, no fire
	# Release: accumulator must reset so the next press fires immediately.
	assert_false(board._tick_hold_drop_accumulator(0.016, false), "release does not fire")
	assert_true(board._tick_hold_drop_accumulator(0.016, true), "next press fires immediately")
	board.free()


func test_hold_drop_advanced_uses_same_accumulator() -> void:
	print("test_hold_drop_advanced_uses_same_accumulator")
	# Normal and advanced hold both pass is_pressed=true to _tick_hold_drop_accumulator.
	# Verify the pacing is identical — no separate accumulator was introduced.
	var board := _make_board()
	assert_true(board._tick_hold_drop_accumulator(0.016, true), "advanced: first press fires immediately")
	board._tick_hold_drop_accumulator(0.05, true)  # partial interval
	assert_false(board._tick_hold_drop_accumulator(0.016, true), "advanced: mid-interval does not fire")
	assert_true(board._tick_hold_drop_accumulator(0.035, true), "advanced: fires after 100ms total")
	board.free()


# --- Reconcile reward guard tests ---
# _on_reconcile_reward must early-return for wrong type / wrong board / already-
# set, since the happy path calls build_board() which touches @onready nodes
# and would crash a bare-instance test. Manual integration test covers the
# happy path on a real scene.

func test_reconcile_reward_ignores_wrong_type() -> void:
	print("test_reconcile_reward_ignores_wrong_type")
	var board := _make_board({"board_type": Enums.BoardType.GOLD})
	var reward := RewardData.new()
	reward.type = RewardData.RewardType.UNLOCK_UPGRADE
	reward.board_type = Enums.BoardType.GOLD
	reward.target_board = Enums.BoardType.GOLD
	board._on_reconcile_reward(reward)
	assert_false(board.should_show_advanced_buckets,
		"non-UNLOCK_ADVANCED_BUCKET reward must not flip the flag")
	board.free()


func test_reconcile_reward_ignores_wrong_board() -> void:
	print("test_reconcile_reward_ignores_wrong_board")
	var board := _make_board({"board_type": Enums.BoardType.GOLD})
	var reward := RewardData.new()
	reward.type = RewardData.RewardType.UNLOCK_ADVANCED_BUCKET
	reward.target_board = Enums.BoardType.ORANGE  # wrong board
	board._on_reconcile_reward(reward)
	assert_false(board.should_show_advanced_buckets,
		"reward targeting different board must not flip the flag")
	board.free()


func test_reconcile_reward_ignores_already_set() -> void:
	print("test_reconcile_reward_ignores_already_set")
	# If the flag is already set, the handler must early-return *before* build_board()
	# (which would crash without @onready nodes). Reaching this assertion proves it.
	var board := _make_board({
		"board_type": Enums.BoardType.GOLD,
		"should_show_advanced_buckets": true,
	})
	var reward := RewardData.new()
	reward.type = RewardData.RewardType.UNLOCK_ADVANCED_BUCKET
	reward.target_board = Enums.BoardType.GOLD
	board._on_reconcile_reward(reward)
	assert_true(board.should_show_advanced_buckets, "flag remains set")
	board.free()


# --- Queue rate bonus: gold-only challenge reward ---

## Resets ChallengeProgressManager and grants `n` QUEUE_RATE_BONUS rewards
## (one per synthetic challenge so the one-time-per-challenge guard allows all).
func _grant_queue_rate_rewards(n: int) -> void:
	ChallengeProgressManager.deserialize({})
	for i in n:
		var reward := ChallengeRewardData.new()
		reward.type = ChallengeRewardData.RewardType.STARTING_MODIFIER
		reward.modifier_type = ChallengeRewardData.ModifierType.QUEUE_RATE_BONUS
		ChallengeProgressManager.complete_challenge("qrb_%d" % i, [], [reward])


func test_queue_rate_bonus_gold_zero_grants_is_base() -> void:
	print("test_queue_rate_bonus_gold_zero_grants_is_base")
	_grant_queue_rate_rewards(0)
	var board := _make_board({"board_type": Enums.BoardType.GOLD})
	assert_near(board._queue_rate_bonus_for_board(Enums.BoardType.GOLD),
		PlinkoBoard.QUEUE_RATE_BONUS_PER_COIN, 0.0001, "no grants → base bonus")
	board.free()


func test_queue_rate_bonus_gold_applies_grant_count() -> void:
	print("test_queue_rate_bonus_gold_applies_grant_count")
	_grant_queue_rate_rewards(2)
	var board := _make_board({"board_type": Enums.BoardType.GOLD})
	var expected: float = PlinkoBoard.QUEUE_RATE_BONUS_PER_COIN \
		+ 2 * PlinkoBoard.QUEUE_RATE_BONUS_PER_UNLOCK
	assert_near(board._queue_rate_bonus_for_board(Enums.BoardType.GOLD),
		expected, 0.0001, "gold board stacks 2 grants onto the base")
	board.free()


func test_queue_rate_bonus_non_gold_stays_base() -> void:
	print("test_queue_rate_bonus_non_gold_stays_base")
	_grant_queue_rate_rewards(2)
	var board := _make_board({"board_type": Enums.BoardType.ORANGE})
	assert_near(board._queue_rate_bonus_for_board(Enums.BoardType.ORANGE),
		PlinkoBoard.QUEUE_RATE_BONUS_PER_COIN, 0.0001,
		"non-gold board ignores the gold-only reward")
	board.free()


# --- Add-rows glissando scheduler ---
# Pure-logic tests for _compute_row_upgrade_schedule. The actual tween, audio,
# and camera orchestration is integration-only (matches the bucket-value ripple
# precedent — its visuals are also untested headlessly).

func test_row_upgrade_start_offset_is_two_vertical_spacings() -> void:
	print("test_row_upgrade_start_offset_is_two_vertical_spacings")
	# Lifts the new bucket row by EXACTLY 2 * vertical_spacing so it visually
	# spawns at the OLD row height. If the buckets_container y-offset formula
	# ever changes, this is what catches the silent regression.
	var board := _make_board()
	var sched: Dictionary = board._compute_row_upgrade_schedule(2, 4, 5, 1.0, 1.0, 0.25)
	assert_near(sched["start_offset"], 2.0, 0.0001, "vs=1.0 → offset=2.0")
	var sched2: Dictionary = board._compute_row_upgrade_schedule(2, 4, 5, 1.0, 0.866, 0.25)
	assert_near(sched2["start_offset"], 1.732, 0.001, "vs=0.866 → offset≈1.732")
	board.free()


func test_row_upgrade_schedule_monotonic() -> void:
	print("test_row_upgrade_schedule_monotonic")
	# 5 buckets at 0.25s interval → sweep_duration = (5-1) * 0.25 = 1.0s.
	# Column indices run 0..N-1 in order — the left→right wavefront.
	var board := _make_board()
	var sched: Dictionary = board._compute_row_upgrade_schedule(2, 4, 5, 1.0, 1.0, 0.25)
	assert_near(sched["sweep_duration"], 1.0, 0.0001, "(N-1)*interval = 1.0")
	var cols: Array = sched["columns"]
	assert_equal(cols.size(), 5, "one column entry per bucket")
	for i in cols.size():
		assert_equal(cols[i]["index"], i, "column index ascends")
	# Degenerate: 1 bucket → 0 sweep duration (guards the maxf clamp).
	var sched_one: Dictionary = board._compute_row_upgrade_schedule(0, 0, 1, 1.0, 1.0, 0.25)
	assert_near(sched_one["sweep_duration"], 0.0, 0.0001, "num_buckets=1 → 0")
	board.free()


func test_row_upgrade_glissando_degrees_ascend() -> void:
	print("test_row_upgrade_glissando_degrees_ascend")
	# degree = column index when passed to AudioManager.force_play_bucket. Pitch
	# = chord[degree % chord.size()], so a 0..N-1 degree sequence becomes an
	# ascending diatonic run (a harp-style glissando) — and importantly NOT the
	# V-shaped distance-from-center pattern normal landings use.
	var board := _make_board()
	var sched: Dictionary = board._compute_row_upgrade_schedule(2, 4, 5, 1.0, 1.0, 0.25)
	var cols: Array = sched["columns"]
	for i in cols.size():
		assert_equal(cols[i]["glissando_degree"], i, "degree == column index")
	board.free()


func test_row_upgrade_new_pegs_revealed_left_to_right() -> void:
	print("test_row_upgrade_new_pegs_revealed_left_to_right")
	# num_rows_before=2 (3 pegs in rows 0+1, flat 0..2); num_rows_after=4 adds
	# row 2 (3 pegs, flat 3..5) and row 3 (4 pegs, flat 6..9) — 7 new pegs.
	# space=1.0 → bucket_x_offset = -2.0, bucket xs = -2,-1,0,+1,+2.
	# Each new peg maps to the bucket column immediately to its left:
	#   col 0: row3 col0 (peg_x=-1.5, flat 6)
	#   col 1: row2 col0 (-1.0, flat 3), row3 col1 (-0.5, flat 7)
	#   col 2: row2 col1 ( 0.0, flat 4), row3 col2 (+0.5, flat 8)
	#   col 3: row2 col2 (+1.0, flat 5), row3 col3 (+1.5, flat 9)
	#   col 4: ∅ (no peg sits to the right of bucket 3)
	var board := _make_board()
	var sched: Dictionary = board._compute_row_upgrade_schedule(2, 4, 5, 1.0, 1.0, 0.25)
	var cols: Array = sched["columns"]
	var total_revealed: int = 0
	for col_data in cols:
		for idx in col_data["reveal_peg_indices"]:
			assert_true(idx >= 3, "every revealed peg is in a new row (idx >= 3)")
			total_revealed += 1
	assert_equal(total_revealed, 7, "all 7 new pegs are scheduled exactly once")
	# The leftmost peg (row 3 col 0, flat idx 6) reveals on column 0; the
	# rightmost (row 3 col 3, flat idx 9) reveals on column 3, never col 4.
	var col0: PackedInt32Array = cols[0]["reveal_peg_indices"]
	var col4: PackedInt32Array = cols[4]["reveal_peg_indices"]
	assert_equal(col0.size(), 1, "col 0 reveals exactly 1 new peg (leftmost)")
	assert_equal(col0[0], 6, "col 0 reveals row 3 col 0 (flat idx 6)")
	assert_equal(col4.size(), 0, "col 4 (rightmost) reveals no new pegs")
	# Spot-check col 3 contains both row-2-col-2 (flat 5) and row-3-col-3 (flat 9).
	var col3: PackedInt32Array = cols[3]["reveal_peg_indices"]
	assert_equal(col3.size(), 2, "col 3 reveals 2 pegs")
	assert_true(col3.has(5) and col3.has(9), "col 3 reveals flat indices 5 and 9")
	board.free()


# --- Needs-tooltip decision tests ---
# _needs_tooltip_action(affordable, hovered) drives the per-button persistent
# "Needs X" tooltip. Cooldown is intentionally not an input — the warning must
# stay steady while the drop timer cycles. Hover yields KEEP so the per-frame
# refresh never clobbers the hover cost tooltip.

func test_needs_tooltip_show_when_unaffordable() -> void:
	print("test_needs_tooltip_show_when_unaffordable")
	var board := _make_board()
	assert_equal(board._needs_tooltip_action(false, false), PlinkoBoard.NeedsTooltipAction.SHOW,
		"SHOW when unaffordable and not hovered")
	board.free()


func test_needs_tooltip_hide_when_affordable() -> void:
	print("test_needs_tooltip_hide_when_affordable")
	var board := _make_board()
	assert_equal(board._needs_tooltip_action(true, false), PlinkoBoard.NeedsTooltipAction.HIDE,
		"HIDE when the drop is affordable and not hovered")
	board.free()


func test_needs_tooltip_keep_when_hovered_unaffordable() -> void:
	print("test_needs_tooltip_keep_when_hovered_unaffordable")
	var board := _make_board()
	assert_equal(board._needs_tooltip_action(false, true), PlinkoBoard.NeedsTooltipAction.KEEP,
		"KEEP when hovered (hover handler owns the tooltip), even if unaffordable")
	board.free()


func test_needs_tooltip_keep_when_hovered_affordable() -> void:
	print("test_needs_tooltip_keep_when_hovered_affordable")
	var board := _make_board()
	assert_equal(board._needs_tooltip_action(true, true), PlinkoBoard.NeedsTooltipAction.KEEP,
		"KEEP when hovered regardless of affordability")
	board.free()


# --- Bomb hazard saw-off semantics ---
# A bomb at bucket B "saws off the limb" — every bucket and peg on the cut
# side of B (the side nearest the board edge) falls away. Each test below
# exercises one piece of that math on a 5-bucket board (num_rows=4).

func test_bomb_cut_side_left_for_below_center() -> void:
	print("test_bomb_cut_side_left_for_below_center")
	# 5 buckets, indices 0..4. Off-centre returns -1=LEFT or +1=RIGHT.
	# Exact centre (odd bucket count) returns 0 — whole board falls.
	assert_equal(PlinkoBoard.bomb_cut_side(0, 5), -1, "B=0 → cuts LEFT")
	assert_equal(PlinkoBoard.bomb_cut_side(1, 5), -1, "B=1 → cuts LEFT")


func test_bomb_cut_side_center_returns_zero() -> void:
	print("test_bomb_cut_side_center_returns_zero")
	# Odd bucket count has a real centre. Bomb there takes the whole board.
	assert_equal(PlinkoBoard.bomb_cut_side(2, 5), 0, "B=2 of 5 is centre → CENTER")
	# Even bucket count has no exact centre — every bucket is one side or
	# the other, no 0 returned.
	assert_true(PlinkoBoard.bomb_cut_side(1, 4) != 0, "no centre on 4-bucket board, B=1")
	assert_true(PlinkoBoard.bomb_cut_side(2, 4) != 0, "no centre on 4-bucket board, B=2")


func test_bomb_cut_side_right_for_above_center() -> void:
	print("test_bomb_cut_side_right_for_above_center")
	assert_equal(PlinkoBoard.bomb_cut_side(3, 5), 1, "B=3 → cuts RIGHT")
	assert_equal(PlinkoBoard.bomb_cut_side(4, 5), 1, "B=4 → cuts RIGHT")


func test_buckets_on_cut_center_takes_whole_board() -> void:
	print("test_buckets_on_cut_center_takes_whole_board")
	# Bomb at the exact-centre bucket detonates the whole board rather than
	# half. num_rows=4 → 5 buckets, centre B=2.
	var sawed: PackedInt32Array = PlinkoBoard.buckets_on_cut(2, 4)
	assert_equal(sawed.size(), 5, "centre detonation voids every bucket")
	for b in [0, 1, 2, 3, 4]:
		assert_true(sawed.has(b), "bucket %d included" % b)


func test_cell_in_cut_left_side() -> void:
	print("test_cell_in_cut_left_side")
	# Bomb at bucket 2 (cuts LEFT). Cells with x ≤ bucket_2.x are in the cut.
	# Bucket 2 has normalised x = 2 - 4/2 = 0; cell (0,0).x = 0 - 0 = 0 → on
	# the boundary → IN the cut.
	assert_true(PlinkoBoard.cell_in_cut(0, 0, 2, 4, -1), "(0,0) at boundary, LEFT")
	assert_true(PlinkoBoard.cell_in_cut(1, 0, 2, 4, -1), "(1,0) strictly LEFT of bucket 2")
	assert_false(PlinkoBoard.cell_in_cut(1, 1, 2, 4, -1), "(1,1) strictly RIGHT of bucket 2")


func test_cell_in_cut_right_side() -> void:
	print("test_cell_in_cut_right_side")
	# Bomb at bucket 3 (cuts RIGHT). bucket_3.x_norm = 1.
	assert_true(PlinkoBoard.cell_in_cut(3, 3, 3, 4, 1), "(3,3) x=1.5 ≥ 1")
	assert_true(PlinkoBoard.cell_in_cut(0, 0, 3, 4, 1) == false, "(0,0) x=0 < 1")
	assert_false(PlinkoBoard.cell_in_cut(2, 1, 3, 4, 1), "(2,1) x=0 < 1")


func test_peg_indices_on_cut_left_cut() -> void:
	print("test_peg_indices_on_cut_left_cut")
	# Bomb at bucket 1 on a 5-bucket (num_rows=4) board is a LEFT cut
	# (bucket_x_norm = 1 - 2 = -1). The destroyed peg set is every peg with
	# x ≤ -1. By inspection (row, col, x_norm):
	#   (2, 0)  x=-1.0  ✓
	#   (3, 0)  x=-1.5  ✓
	# → 2 destroyed pegs (the leftmost column at rows 2 and 3).
	var indices: PackedInt32Array = PlinkoBoard.peg_indices_on_cut(1, 4)
	assert_equal(indices.size(), 2, "2 pegs destroyed in a LEFT cut at bucket 1")
	# (2,0) flat idx = 2*3/2 + 0 = 3.
	assert_true(indices.has(3), "the (2,0) peg is included")


func test_peg_indices_on_cut_center_takes_all() -> void:
	print("test_peg_indices_on_cut_center_takes_all")
	# Bomb at the centre bucket 2 on a 5-bucket board is a CENTER cut — saws the
	# whole board, so EVERY peg is destroyed (rows 0..3 → 1+2+3+4 = 10 pegs).
	var indices: PackedInt32Array = PlinkoBoard.peg_indices_on_cut(2, 4)
	assert_equal(indices.size(), 10, "centre cut destroys all 10 pegs")


func test_buckets_on_cut_left_takes_everything_below() -> void:
	print("test_buckets_on_cut_left_takes_everything_below")
	# Bomb at bucket 1 (LEFT) saws off 0, 1.
	var sawed: PackedInt32Array = PlinkoBoard.buckets_on_cut(1, 4)
	assert_equal(sawed.size(), 2, "2 buckets sawn off")
	for b in [0, 1]:
		assert_true(sawed.has(b), "bucket %d sawn" % b)


func test_buckets_on_cut_right_takes_everything_above() -> void:
	print("test_buckets_on_cut_right_takes_everything_above")
	# Bomb at bucket 3 (RIGHT) saws off 3, 4.
	var sawed: PackedInt32Array = PlinkoBoard.buckets_on_cut(3, 4)
	assert_equal(sawed.size(), 2, "2 buckets sawn off")
	for b in [3, 4]:
		assert_true(sawed.has(b), "bucket %d sawn" % b)


func test_should_fall_through_static_helper() -> void:
	print("test_should_fall_through_static_helper")
	# Bomb at bucket 1 on a 5-bucket (num_rows=4) board is a LEFT cut at
	# bucket_x_norm = -1. Cells at x ≤ -1 fall through; everything else survives.
	var voided: PackedInt32Array = PackedInt32Array([1])
	assert_true(PlinkoBoard.should_fall_through(2, 0, voided, 4), "(2,0) x=-1 LEFT-cut")
	assert_true(PlinkoBoard.should_fall_through(3, 0, voided, 4), "(3,0) x=-1.5 LEFT-cut")
	assert_false(PlinkoBoard.should_fall_through(0, 0, voided, 4), "(0,0) x=0 survives")
	assert_false(PlinkoBoard.should_fall_through(1, 1, voided, 4), "(1,1) x=0.5 survives")
	# No voided columns → never fall through.
	assert_false(PlinkoBoard.should_fall_through(0, 0, PackedInt32Array(), 4), "empty voided → never")


func test_void_column_saws_off_one_side() -> void:
	print("test_void_column_saws_off_one_side")
	# Bomb at bucket 1 (LEFT) voids buckets 0 AND 1 in one call.
	var board := _make_board({"num_rows": 4})
	board.void_column(1)
	assert_true(board.is_column_voided(0), "bucket 0 voided by saw")
	assert_true(board.is_column_voided(1), "bucket 1 (the bomb itself) voided")
	assert_false(board.is_column_voided(2), "bucket 2 (inside surviving range) still alive")
	board.free()


func test_get_reachable_bucket_indices_no_voids_is_all() -> void:
	print("test_get_reachable_bucket_indices_no_voids_is_all")
	# num_rows=4 → 5 buckets. With no voids, reachable is [0..4].
	var board := _make_board({"num_rows": 4})
	var reachable: PackedInt32Array = board.get_reachable_bucket_indices()
	assert_equal(reachable.size(), 5, "5 buckets reachable on a fresh num_rows=4 board")
	for i in 5:
		assert_true(reachable.has(i), "bucket %d reachable" % i)
	board.free()


func test_get_reachable_bucket_indices_after_left_cut() -> void:
	print("test_get_reachable_bucket_indices_after_left_cut")
	# Bomb at bucket 1 saws off 0 and 1; reachable = [2, 3, 4].
	var board := _make_board({"num_rows": 4})
	board.void_column(1)
	var reachable: PackedInt32Array = board.get_reachable_bucket_indices()
	assert_equal(reachable.size(), 3, "3 buckets reachable after a saw at 1")
	for b in [2, 3, 4]:
		assert_true(reachable.has(b), "bucket %d still reachable" % b)
	board.free()


func test_get_targetable_bucket_indices_excludes_edges() -> void:
	print("test_get_targetable_bucket_indices_excludes_edges")
	# num_rows=4 → reachable [0..4]; targetable trims the edges → [1, 2, 3].
	var board := _make_board({"num_rows": 4})
	var targetable: PackedInt32Array = board.get_targetable_bucket_indices()
	assert_equal(targetable.size(), 3, "edges excluded — only interior buckets")
	for b in [1, 2, 3]:
		assert_true(targetable.has(b), "bucket %d targetable" % b)
	assert_false(targetable.has(0), "edge bucket 0 excluded")
	assert_false(targetable.has(4), "edge bucket 4 excluded")
	board.free()


func test_void_column_idempotent() -> void:
	print("test_void_column_idempotent")
	# Re-detonating into an already-voided bucket re-enters and no-ops, so
	# state stays clean.
	var board := _make_board({"num_rows": 4})
	board.void_column(1)
	var first_size: int = board.get_reachable_bucket_indices().size()
	board.void_column(1)
	assert_equal(board.get_reachable_bucket_indices().size(), first_size,
		"second call to void_column(1) is a no-op")
	board.free()


func test_shift_voided_columns_handles_add_rows() -> void:
	print("test_shift_voided_columns_handles_add_rows")
	# add_two_rows shifts each voided bucket index by +1 (new edge bucket
	# inserted on the left bumps every existing bucket up one). Without the
	# shift, destroyed columns would re-anchor to a different geometric x.
	var board := _make_board({"num_rows": 4})
	board.void_column(1)  # voids 0 and 1
	# Apply the shift the way add_two_rows does, without invoking the full
	# build_board (which would touch @onready nodes a bare instance can't
	# satisfy).
	board._shift_voided_columns(1)
	assert_true(board.is_column_voided(1), "old bucket 0 → new bucket 1 still voided")
	assert_true(board.is_column_voided(2), "old bucket 1 → new bucket 2 still voided")
	assert_false(board.is_column_voided(0), "new bucket 0 (added edge) not voided")
	board.free()


# --- Radial void tests (ForbiddenBucketHazard detonation) ---

func test_is_lattice_cell_voided_radius_inside() -> void:
	print("test_is_lattice_cell_voided_radius_inside")
	# A radius centered on peg (row=2, col=2) at world position (1, -2) with
	# radius 0.5 should include the cell itself (distance 0).
	var board := _make_board({"num_rows": 4, "space_between_pegs": 1.0,
		"vertical_spacing": 1.0})
	# cell_to_world(2, 2) -> (-2*1/2 + 2*1, 0.2 - 1*2, 0) = (1, -1.8, 0)
	board._voided_radii = [{"cx": 1.0, "cy": -1.8, "radius": 0.5}]
	assert_true(board.is_lattice_cell_voided(2, 2), "cell at radius centre is voided")
	board.free()


func test_is_lattice_cell_voided_radius_outside() -> void:
	print("test_is_lattice_cell_voided_radius_outside")
	# A small radius shouldn't engulf cells two rows away.
	var board := _make_board({"num_rows": 4, "space_between_pegs": 1.0,
		"vertical_spacing": 1.0})
	board._voided_radii = [{"cx": 1.0, "cy": -1.8, "radius": 0.5}]
	# cell_to_world(0, 0) -> (0, 0.2, 0); distance > 0.5 → not voided.
	assert_false(board.is_lattice_cell_voided(0, 0), "cell well outside radius survives")
	board.free()


func test_is_lattice_cell_voided_bucket_row_uses_destroyed_set() -> void:
	print("test_is_lattice_cell_voided_bucket_row_uses_destroyed_set")
	# At the bucket row, the authoritative answer is the explicit
	# `_destroyed_bucket_indices` set (synchronously populated by
	# detonate_radius). This decouples scoring from the multi-second fall
	# animation — a coin targeting a falling-but-still-visible bucket must
	# still see the cell as voided.
	var board := _make_board({"num_rows": 4})
	board._destroyed_bucket_indices[2] = true
	# Bucket row is row = num_rows.
	assert_true(board.is_lattice_cell_voided(4, 2), "destroyed bucket cell is voided")
	assert_false(board.is_lattice_cell_voided(4, 3), "neighbour bucket cell is not voided")
	board.free()


func test_is_lattice_cell_voided_unions_column_and_radius() -> void:
	print("test_is_lattice_cell_voided_unions_column_and_radius")
	# Column-based bomb cut AND radial detonation both contribute to the void
	# set — coins fall through cells inside EITHER. Regression guard for the
	# is_lattice_cell_voided extension. Uses bucket 2 (centre on a 5-bucket
	# board → CUT_CENTER → voids every cell), matching the pattern in
	# test_should_fall_through_static_helper above.
	var board := _make_board({"num_rows": 4, "space_between_pegs": 1.0,
		"vertical_spacing": 1.0})
	board._voided_columns = PackedInt32Array([2])
	# Radius covers cell (2, 2).
	board._voided_radii = [{"cx": 1.0, "cy": -1.8, "radius": 0.5}]
	assert_true(board.is_lattice_cell_voided(0, 0), "column cut cell still voided")
	assert_true(board.is_lattice_cell_voided(2, 2), "radius cell also voided")
	board.free()


func test_voided_radii_cleared_with_markings() -> void:
	print("test_voided_radii_cleared_with_markings")
	# clear_all_markings is the challenge-end teardown. Radial voids and the
	# destroyed-bucket set MUST be cleared here so the next challenge starts on
	# a pristine board (mirrors the existing _voided_columns lifecycle).
	var board := _make_board({"num_rows": 4})
	board._voided_radii = [{"cx": 0.0, "cy": 0.0, "radius": 1.0}]
	board._destroyed_bucket_indices[2] = true
	board.clear_all_markings()
	assert_equal(board._voided_radii.size(), 0, "_voided_radii cleared")
	assert_equal(board._destroyed_bucket_indices.size(), 0, "_destroyed_bucket_indices cleared")
	board.free()
