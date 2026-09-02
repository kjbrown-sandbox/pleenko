extends "res://test/test_base.gd"

## SpaceBoard tests — run with:
##   godot --headless --scene res://test/test_space_board.tscn
##
## Covers the pure, headless-testable core: the fixed rainbow layout, the
## activation state machine, win detection, the analytic flight math, the
## unbiased fall, save persistence (including the prestige-surviving block and
## the v7 -> v8 migration), the interruptible cinematic, and the merge-safe
## transporter seam.
##
## A bare `SpaceBoard.new()` never enters the tree, so `_ready()` never runs and
## there are no Buckets / pegs / underlays. That is deliberate: every piece of
## bookkeeping runs unguarded so it works on a bare instance, and every
## scene-tree side effect is null-guarded so it silently no-ops.

const GOLD := Enums.CurrencyType.GOLD_COIN
const ORANGE := Enums.CurrencyType.ORANGE_COIN
const RED := Enums.CurrencyType.RED_COIN
const VIOLET := Enums.CurrencyType.VIOLET_COIN
const BLUE := Enums.CurrencyType.BLUE_COIN
const GREEN := Enums.CurrencyType.GREEN_COIN

## Index of the one gold bucket (dead centre).
const GOLD_INDEX := 5


func _run_tests() -> void:
	print("\n=== SpaceBoard Tests ===\n")

	test_layout_is_the_specified_rainbow()
	test_layout_is_symmetric()
	test_gold_is_the_only_unmirrored_colour()

	test_matches_only_its_own_colour()
	test_matches_rejects_out_of_range()

	test_correct_colour_activates()
	test_wrong_colour_is_a_noop()
	test_already_activated_is_a_noop()
	test_activation_emits_once_per_bucket()

	test_is_won_requires_every_bucket()
	test_is_won_rejects_wrong_sized_array()
	test_win_fires_only_when_all_eleven_lit()
	test_win_fires_exactly_once()
	test_win_is_retriggerable_for_filming()
	test_win_waits_for_the_activation_cinematic()

	test_fall_path_stays_in_range()
	test_fall_path_is_unbiased()
	test_step_right_is_a_fair_coin()

	test_arc_starts_at_source()
	test_arc_ends_at_apex()
	test_arc_bows_above_the_straight_line()
	test_hop_endpoints_and_apex()

	test_serialize_round_trip()
	test_serialize_survives_json()
	test_deserialize_of_empty_dict_is_clean()
	test_deserialize_tolerates_short_array()

	test_v8_migration_leaves_space_empty()
	test_v8_migration_preserves_an_existing_space_block()
	test_save_version_is_eight()
	await test_space_state_survives_a_prestige_reset()

	await test_interrupted_cinematic_still_commits()
	await test_concurrent_arrivals_queue_and_never_compound_time_scale()
	await test_teardown_leaves_a_prestige_time_scale_alone()
	await test_teardown_while_exiting_never_restarts_a_cinematic()
	await test_coin_for_activated_bucket_is_freed()
	test_offcamera_arrival_commits_without_a_cinematic()

	test_connect_transporter_is_idempotent()
	test_connect_transporter_without_signal_is_silent()
	test_main_scene_carries_the_space_board()

	test_ring_params_defaults_are_the_legacy_ring()
	test_ring_params_overrides_apply()

	await test_win_overlay_dismisses_and_can_be_rebuilt()

	# Never leave a test suite having changed global engine state.
	Engine.time_scale = 1.0


# --- Helpers ---

func _make_board() -> SpaceBoard:
	# Bare instance: _init() runs (so _activated is valid), _ready() does not.
	return SpaceBoard.new()


func _all_activated() -> Array[bool]:
	var a: Array[bool] = []
	a.resize(SpaceBoard.BUCKET_COLORS.size())
	a.fill(true)
	return a


# --- Fixed layout (locked decision 2) ---

func test_layout_is_the_specified_rainbow() -> void:
	print("test_layout_is_the_specified_rainbow")
	var expected: Array = [GREEN, BLUE, VIOLET, RED, ORANGE, GOLD, ORANGE, RED, VIOLET, BLUE, GREEN]
	assert_equal(SpaceBoard.BUCKET_COLORS.size(), 11, "11 buckets for 10 rows")
	for i in expected.size():
		assert_equal(SpaceBoard.BUCKET_COLORS[i], expected[i], "bucket %d colour" % i)


func test_layout_is_symmetric() -> void:
	print("test_layout_is_symmetric")
	var colors := SpaceBoard.BUCKET_COLORS
	var last: int = colors.size() - 1
	for i in colors.size():
		assert_equal(colors[i], colors[last - i], "bucket %d mirrors %d" % [i, last - i])


func test_gold_is_the_only_unmirrored_colour() -> void:
	print("test_gold_is_the_only_unmirrored_colour")
	var counts := {}
	for c in SpaceBoard.BUCKET_COLORS:
		counts[c] = counts.get(c, 0) + 1
	assert_equal(counts[GOLD], 1, "gold has a single bucket, dead centre")
	assert_equal(SpaceBoard.BUCKET_COLORS[GOLD_INDEX], GOLD, "gold sits at index 5")
	for c in [ORANGE, RED, VIOLET, BLUE, GREEN]:
		assert_equal(counts[c], 2, "every other colour is mirrored")


# --- matches() ---

func test_matches_only_its_own_colour() -> void:
	print("test_matches_only_its_own_colour")
	assert_true(SpaceBoard.matches(GOLD_INDEX, GOLD), "gold matches the centre bucket")
	assert_false(SpaceBoard.matches(GOLD_INDEX, GREEN), "green does not match gold's bucket")
	assert_true(SpaceBoard.matches(0, GREEN), "green matches the left edge")
	assert_true(SpaceBoard.matches(10, GREEN), "green matches the right edge too")


func test_matches_rejects_out_of_range() -> void:
	print("test_matches_rejects_out_of_range")
	assert_false(SpaceBoard.matches(-1, GOLD), "negative index never matches")
	assert_false(SpaceBoard.matches(11, GOLD), "past the last bucket never matches")


# --- try_activate(): the state machine ---

func test_correct_colour_activates() -> void:
	print("test_correct_colour_activates")
	var sb := _make_board()
	assert_true(sb.try_activate(GOLD_INDEX, GOLD), "matching colour activates")
	assert_true(sb.is_activated(GOLD_INDEX), "bucket is now lit")
	sb.free()


func test_wrong_colour_is_a_noop() -> void:
	print("test_wrong_colour_is_a_noop")
	var sb := _make_board()
	assert_false(sb.try_activate(GOLD_INDEX, BLUE), "wrong colour returns false")
	assert_false(sb.is_activated(GOLD_INDEX), "and lights nothing")
	sb.free()


func test_already_activated_is_a_noop() -> void:
	print("test_already_activated_is_a_noop")
	var sb := _make_board()
	assert_true(sb.try_activate(0, GREEN), "first green activates the left edge")
	assert_false(sb.try_activate(0, GREEN), "a second green there changes nothing")
	sb.free()


func test_activation_emits_once_per_bucket() -> void:
	print("test_activation_emits_once_per_bucket")
	var sb := _make_board()
	var seen: Array[int] = []
	sb.bucket_activated.connect(func(i: int) -> void: seen.append(i))
	sb.try_activate(GOLD_INDEX, GOLD)
	sb.try_activate(GOLD_INDEX, GOLD)
	assert_equal(seen, [GOLD_INDEX] as Array[int], "signal fires only on a real change")
	sb.free()


# --- Win detection (locked decision 7) ---

func test_is_won_requires_every_bucket() -> void:
	print("test_is_won_requires_every_bucket")
	var a := _all_activated()
	assert_true(SpaceBoard.is_won(a), "all 11 lit is a win")
	a[7] = false
	assert_false(SpaceBoard.is_won(a), "one dark bucket is not a win")


func test_is_won_rejects_wrong_sized_array() -> void:
	print("test_is_won_rejects_wrong_sized_array")
	var short: Array[bool] = [true, true, true]
	assert_false(SpaceBoard.is_won(short), "a short array is never a win")


func test_win_fires_only_when_all_eleven_lit() -> void:
	print("test_win_fires_only_when_all_eleven_lit")
	var sb := _make_board()
	var wins := [0]
	sb.won.connect(func() -> void: wins[0] += 1)
	for i in SpaceBoard.BUCKET_COLORS.size() - 1:
		sb.try_activate(i, SpaceBoard.BUCKET_COLORS[i])
		assert_equal(wins[0], 0, "no win after %d of 11" % (i + 1))
	var last: int = SpaceBoard.BUCKET_COLORS.size() - 1
	sb.try_activate(last, SpaceBoard.BUCKET_COLORS[last])
	assert_equal(wins[0], 1, "win fires on the eleventh")
	sb.free()


func test_win_fires_exactly_once() -> void:
	print("test_win_fires_exactly_once")
	var sb := _make_board()
	var wins := [0]
	sb.won.connect(func() -> void: wins[0] += 1)
	for i in SpaceBoard.BUCKET_COLORS.size():
		sb.try_activate(i, SpaceBoard.BUCKET_COLORS[i])
	# Re-landing on already-lit buckets must not re-fire the latch.
	for i in SpaceBoard.BUCKET_COLORS.size():
		sb.try_activate(i, SpaceBoard.BUCKET_COLORS[i])
	assert_equal(wins[0], 1, "the win latch fires exactly once")
	assert_true(sb.has_won(), "the won flag is set")
	sb.free()


func test_win_is_retriggerable_for_filming() -> void:
	print("test_win_is_retriggerable_for_filming")
	# Locked decision 7: the overlay must be re-showable after dismissal.
	var sb := _make_board()
	var wins := [0]
	sb.won.connect(func() -> void: wins[0] += 1)
	sb.dev_activate_all()
	assert_equal(wins[0], 1, "dev_activate_all lights everything and wins")
	sb.dev_activate_all()
	assert_equal(wins[0], 2, "and can re-fire the win beat on demand")
	sb.free()


func test_win_waits_for_the_activation_cinematic() -> void:
	print("test_win_waits_for_the_activation_cinematic")
	# The eleventh bucket is the money shot. The overlay must not cover it.
	var sb := _make_board()
	for i in range(1, SpaceBoard.BUCKET_COLORS.size()):
		sb.try_activate(i, SpaceBoard.BUCKET_COLORS[i])
	var wins := [0]
	sb.won.connect(func() -> void: wins[0] += 1)

	var coin := MeshInstance3D.new()
	sb._enqueue_landing(coin, GREEN, 0)
	assert_true(sb.is_activated(0), "the eleventh bucket lights immediately")
	assert_equal(wins[0], 0, "but the win is held back while the cinematic plays")

	sb.abort_cinematic()
	assert_equal(wins[0], 1, "and fires once the cinematic is done")
	Engine.time_scale = 1.0
	if is_instance_valid(coin):
		coin.queue_free()
	sb.free()


# --- Odds stay honest (locked decision 8) ---

func test_fall_path_stays_in_range() -> void:
	print("test_fall_path_stays_in_range")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for _i in 200:
		var col: int = SpaceBoard.fall_path(rng, SpaceBoard.NUM_ROWS)
		assert_true(col >= 0 and col <= SpaceBoard.NUM_ROWS,
			"landing column %d within 0..%d" % [col, SpaceBoard.NUM_ROWS])


func test_fall_path_is_unbiased() -> void:
	print("test_fall_path_is_unbiased")
	# A fair 10-row Galton fall centres on column 5. The lattice is never
	# weighted toward a colour — the dev hotkeys exist precisely so the odds
	# don't have to be touched for filming.
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654321
	var samples := 20000
	var total := 0
	for _i in samples:
		total += SpaceBoard.fall_path(rng, SpaceBoard.NUM_ROWS)
	var mean: float = float(total) / float(samples)
	assert_near(mean, SpaceBoard.NUM_ROWS / 2.0, 0.15, "mean landing column is centred")


func test_step_right_is_a_fair_coin() -> void:
	print("test_step_right_is_a_fair_coin")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var rights := 0
	var samples := 20000
	for _i in samples:
		rights += SpaceBoard.step_right(rng)
	assert_near(float(rights) / float(samples), 0.5, 0.02, "row step is 50/50")


# --- Analytic flight math ---

func test_arc_starts_at_source() -> void:
	print("test_arc_starts_at_source")
	var from := Vector3(3, -30, 0)
	var apex := Vector3(0, 0, 0)
	assert_true(SpaceBoard.arc_position_at(from, apex, 0.0).is_equal_approx(from),
		"t=0 is the transporter position")


func test_arc_ends_at_apex() -> void:
	print("test_arc_ends_at_apex")
	var from := Vector3(3, -30, 0)
	var apex := Vector3(0, 0, 0)
	assert_true(SpaceBoard.arc_position_at(from, apex, 1.0).is_equal_approx(apex),
		"t=1 is the apex peg")
	assert_true(SpaceBoard.arc_position_at(from, apex, 2.0).is_equal_approx(apex),
		"t is clamped past 1")


func test_arc_bows_above_the_straight_line() -> void:
	print("test_arc_bows_above_the_straight_line")
	var from := Vector3(0, -30, 0)
	var apex := Vector3(10, 0, 0)
	var mid: Vector3 = SpaceBoard.arc_position_at(from, apex, 0.5)
	var straight: Vector3 = from.lerp(apex, 0.5)
	assert_true(mid.y > straight.y, "the lob rises above the straight line")
	assert_true(mid.x < straight.x, "horizontal eases in, so it leaves near-vertically")


func test_hop_endpoints_and_apex() -> void:
	print("test_hop_endpoints_and_apex")
	var a := Vector3(0, 0, 0)
	var b := Vector3(1, -1, 0)
	assert_true(SpaceBoard.hop_position_at(a, b, 0.0, 0.5).is_equal_approx(a), "hop starts at a")
	assert_true(SpaceBoard.hop_position_at(a, b, 1.0, 0.5).is_equal_approx(b), "hop ends at b")
	var mid: Vector3 = SpaceBoard.hop_position_at(a, b, 0.5, 0.5)
	assert_near(mid.y, a.lerp(b, 0.5).y + 0.5, 0.0001, "hop peaks `height` above the midpoint")


# --- Save ---

func test_serialize_round_trip() -> void:
	print("test_serialize_round_trip")
	var sb := _make_board()
	sb.try_activate(GOLD_INDEX, GOLD)
	sb.try_activate(0, GREEN)
	var blob := sb.serialize()

	var restored := _make_board()
	restored.deserialize(blob)
	assert_true(restored.is_activated(GOLD_INDEX), "gold bucket restored")
	assert_true(restored.is_activated(0), "left green bucket restored")
	assert_false(restored.is_activated(1), "untouched bucket stays dark")
	assert_false(restored.has_won(), "not a win yet")
	sb.free()
	restored.free()


func test_serialize_survives_json() -> void:
	print("test_serialize_survives_json")
	# The save file is JSON — typed Array[bool] must survive stringify/parse.
	var sb := _make_board()
	sb.dev_activate_all()
	var text := JSON.stringify(sb.serialize())
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "space block is valid JSON")

	var restored := _make_board()
	restored.deserialize(parsed)
	assert_true(SpaceBoard.is_won(restored.get_activated()), "all 11 survive JSON")
	assert_true(restored.has_won(), "won flag survives JSON")
	sb.free()
	restored.free()


func test_deserialize_of_empty_dict_is_clean() -> void:
	print("test_deserialize_of_empty_dict_is_clean")
	var sb := _make_board()
	sb.dev_activate_all()
	sb.deserialize({})
	for i in SpaceBoard.BUCKET_COLORS.size():
		assert_false(sb.is_activated(i), "bucket %d cleared by an empty block" % i)
	assert_false(sb.has_won(), "empty block means not won")
	sb.free()


func test_deserialize_tolerates_short_array() -> void:
	print("test_deserialize_tolerates_short_array")
	var sb := _make_board()
	sb.deserialize({"activated": [true, true]})
	assert_true(sb.is_activated(0), "leading entries applied")
	assert_true(sb.is_activated(1), "leading entries applied")
	assert_false(sb.is_activated(10), "missing entries default to dark")
	sb.free()


func test_save_version_is_eight() -> void:
	print("test_save_version_is_eight")
	assert_equal(SaveManager.SAVE_VERSION, 8, "space board owns the 7 -> 8 bump")


func test_v8_migration_leaves_space_empty() -> void:
	print("test_v8_migration_leaves_space_empty")
	# An existing v7 save has no space block at all; the load path defaults it,
	# so a returning player starts with zero activated buckets and not-won.
	var v7 := {"version": 7, "level": {"current_level": 3}}
	var out := SaveManager._migrate(v7, 7)
	assert_equal(out["version"], SaveManager.SAVE_VERSION, "stamped v8")
	var sb := _make_board()
	sb.deserialize(out.get("space", {}))
	for i in SpaceBoard.BUCKET_COLORS.size():
		assert_false(sb.is_activated(i), "migrated save has bucket %d dark" % i)
	assert_false(sb.has_won(), "migrated save is not won")
	sb.free()


func test_v8_migration_preserves_an_existing_space_block() -> void:
	print("test_v8_migration_preserves_an_existing_space_block")
	var save := {"version": 8, "space": {"activated": [true], "won": false}}
	var out := SaveManager._migrate(save, 8)
	assert_equal(out["space"]["activated"], [true], "migration never rewrites the space block")


func test_space_state_survives_a_prestige_reset() -> void:
	print("test_space_state_survives_a_prestige_reset")
	# The space board is the endgame: reset_game fires on EVERY prestige, and
	# wiping 11 hard-won buckets routinely would make the win unreachable.
	var path: String = SaveManager.SAVE_PATH
	var had_save := FileAccess.file_exists(path)
	var original := ""
	if had_save:
		var bf := FileAccess.open(path, FileAccess.READ)
		original = bf.get_as_text()
		bf.close()

	var sb := _make_board()
	sb.try_activate(GOLD_INDEX, GOLD)
	SaveManager.setup(null, false, sb)
	SaveManager.reset_game_without_reload()

	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(parsed is Dictionary, "minimal save is valid JSON")
	var minimal: Dictionary = parsed if parsed is Dictionary else {}
	assert_true(minimal.has("space"), "space block preserved across a prestige reset")

	var restored := _make_board()
	restored.deserialize(minimal.get("space", {}))
	assert_true(restored.is_activated(GOLD_INDEX), "the lit gold bucket survives")

	# ...and the fallback path: reset_game_without_reload can also run from the
	# prestige screen, where main.tscn (and the node) no longer exists.
	SaveManager.setup(null, false, null)
	SaveManager.reset_game_without_reload()
	var f2 := FileAccess.open(path, FileAccess.READ)
	var parsed2: Variant = JSON.parse_string(f2.get_as_text())
	f2.close()
	var minimal2: Dictionary = parsed2 if parsed2 is Dictionary else {}
	var carried := SpaceBoard.new()
	carried.deserialize(minimal2.get("space", {}))
	assert_true(carried.is_activated(GOLD_INDEX),
		"space state is carried forward from disk when the node is gone")

	sb.free()
	restored.free()
	carried.free()
	await get_tree().process_frame

	if had_save:
		var wf := FileAccess.open(path, FileAccess.WRITE)
		wf.store_string(original)
		wf.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# --- Cinematic lifecycle ---

func test_interrupted_cinematic_still_commits() -> void:
	print("test_interrupted_cinematic_still_commits")
	# Anti-soft-lock: an abort mid-shot must never leave a half-filled circle,
	# a slowed clock, or a locked HUD.
	var sb := _make_board()
	var locks: Array[bool] = []
	sb.apply_input_lock_fn = func(locked: bool) -> void: locks.append(locked)
	var coin := MeshInstance3D.new()

	sb._enqueue_landing(coin, GOLD, GOLD_INDEX)
	assert_true(sb._cinematic != SpaceBoard.Cinematic.OFF, "cinematic is running")
	assert_near(Engine.time_scale, ThemeProvider.theme.space_activation_slow_mo_scale,
		0.0001, "slow-mo engaged")
	assert_equal(locks, [true] as Array[bool], "input locked for the shot")

	sb.abort_cinematic()
	assert_equal(sb._cinematic, SpaceBoard.Cinematic.OFF, "cinematic torn down")
	assert_near(Engine.time_scale, 1.0, 0.0001, "time scale restored")
	assert_equal(locks, [true, false] as Array[bool], "input unlocked again")
	assert_true(sb.is_activated(GOLD_INDEX), "the activation is still committed")
	assert_true(sb.serialize()["activated"][GOLD_INDEX], "and is still saveable")

	sb.abort_cinematic()  # idempotent
	assert_near(Engine.time_scale, 1.0, 0.0001, "second teardown is a no-op")

	if is_instance_valid(coin):
		coin.queue_free()
	sb.free()
	await get_tree().process_frame


func test_concurrent_arrivals_queue_and_never_compound_time_scale() -> void:
	print("test_concurrent_arrivals_queue_and_never_compound_time_scale")
	# Six boards can transport at once. A dropped arrival is a lost activation,
	# so landings queue behind the running cinematic instead of stacking.
	var sb := _make_board()
	var slow: float = ThemeProvider.theme.space_activation_slow_mo_scale
	var coin_a := MeshInstance3D.new()
	var coin_b := MeshInstance3D.new()
	var coin_c := MeshInstance3D.new()

	sb._enqueue_landing(coin_a, GOLD, GOLD_INDEX)
	sb._enqueue_landing(coin_b, ORANGE, 4)
	sb._enqueue_landing(coin_c, GREEN, 0)
	assert_equal(sb._landing_queue.size(), 2, "later arrivals are queued, not dropped")
	assert_near(Engine.time_scale, slow, 0.0001, "time scale never compounds")
	assert_false(sb.is_activated(4), "queued arrival waits its turn")

	sb.abort_cinematic()
	assert_true(sb.is_activated(GOLD_INDEX), "first arrival committed")
	assert_true(sb.is_activated(4), "second arrival plays next")
	assert_near(Engine.time_scale, slow, 0.0001, "still exactly one slow-mo, not squared")

	sb.abort_cinematic()
	assert_true(sb.is_activated(0), "third arrival plays after that")
	sb.abort_cinematic()
	assert_equal(sb._landing_queue.size(), 0, "queue fully drained")
	assert_near(Engine.time_scale, 1.0, 0.0001, "time scale restored once the queue empties")

	sb.free()


## Regression: PrestigeManager.enter_phase sets Engine.time_scale and THEN emits
## prestige_phase_changed, which reaches us as an abort. Teardown used to force
## 1.0 unconditionally, wiping prestige's slow-mo one line after it was set —
## reachable any time a prestige fired while the player was parked in space.
func test_teardown_leaves_a_prestige_time_scale_alone() -> void:
	print("test_teardown_leaves_a_prestige_time_scale_alone")
	var sb := _make_board()
	var coin := MeshInstance3D.new()
	sb._enqueue_landing(coin, GOLD, GOLD_INDEX)
	assert_true(sb._cinematic != SpaceBoard.Cinematic.OFF, "cinematic is running")

	# Stand in for enter_phase(SLOW_MO): the scale is already prestige's when the
	# abort arrives. Set directly so no autoload signal handlers run.
	var prestige_scale := 0.15
	PrestigeManager.current_phase = PrestigeManager.PrestigePhase.SLOW_MO
	Engine.time_scale = prestige_scale

	sb.abort_cinematic()
	assert_equal(sb._cinematic, SpaceBoard.Cinematic.OFF, "cinematic still tears down")
	assert_true(sb.is_activated(GOLD_INDEX), "and still commits the activation")
	assert_near(Engine.time_scale, prestige_scale, 0.0001,
		"prestige owns the clock — teardown must not reset it to 1.0")

	PrestigeManager.current_phase = PrestigeManager.PrestigePhase.NONE
	Engine.time_scale = 1.0
	if is_instance_valid(coin):
		coin.queue_free()
	sb.free()
	await get_tree().process_frame


## Regression: teardown ends by draining the landing queue, and a drained landing
## can START a new cinematic (slowing the clock and clearing _torn_down). Doing
## that from _exit_tree left the next scene running at the slow-mo rate forever.
func test_teardown_while_exiting_never_restarts_a_cinematic() -> void:
	print("test_teardown_while_exiting_never_restarts_a_cinematic")
	var sb := _make_board()
	var coin_a := MeshInstance3D.new()
	var coin_b := MeshInstance3D.new()
	sb._enqueue_landing(coin_a, GOLD, GOLD_INDEX)
	sb._enqueue_landing(coin_b, ORANGE, 4)
	assert_equal(sb._landing_queue.size(), 1, "second arrival is waiting")

	sb._exiting = true
	sb.abort_cinematic()

	assert_equal(sb._cinematic, SpaceBoard.Cinematic.OFF,
		"no new cinematic starts on a node that is leaving the tree")
	assert_near(Engine.time_scale, 1.0, 0.0001,
		"the clock is left at normal speed, not the slow-mo rate")
	assert_true(sb.is_activated(GOLD_INDEX), "the in-flight activation still commits")
	assert_equal(sb._landing_queue.size(), 1, "the queue is left undrained")

	# Engine.time_scale is global and shared across suites: reset it explicitly so
	# a failure here can never leak a slowed clock into the next test.
	Engine.time_scale = 1.0
	if is_instance_valid(coin_a):
		coin_a.queue_free()
	if is_instance_valid(coin_b):
		coin_b.queue_free()
	sb.free()
	await get_tree().process_frame
	await get_tree().process_frame


func test_coin_for_activated_bucket_is_freed() -> void:
	print("test_coin_for_activated_bucket_is_freed")
	var sb := _make_board()
	assert_true(sb.try_activate(GOLD_INDEX, GOLD), "bucket lit up front")
	var coin := MeshInstance3D.new()
	sb._enqueue_landing(coin, GOLD, GOLD_INDEX)
	assert_equal(sb._cinematic, SpaceBoard.Cinematic.OFF,
		"a repeat landing plays no cinematic")
	await get_tree().process_frame
	assert_false(is_instance_valid(coin), "the coin node is freed, not leaked")
	sb.free()


func test_offcamera_arrival_commits_without_a_cinematic() -> void:
	print("test_offcamera_arrival_commits_without_a_cinematic")
	# Coins keep arriving while the player is down on a colour board. Running
	# the cinematic then would steal the shared camera, slow the whole game and
	# lock input for a shot nobody can see.
	var sb := _make_board()
	sb.should_play_cinematic_fn = func() -> bool: return false
	var locks: Array[bool] = []
	sb.apply_input_lock_fn = func(locked: bool) -> void: locks.append(locked)
	var coin := MeshInstance3D.new()

	sb._enqueue_landing(coin, GOLD, GOLD_INDEX)
	assert_true(sb.is_activated(GOLD_INDEX), "the bucket still lights up")
	assert_equal(sb._cinematic, SpaceBoard.Cinematic.OFF, "no cinematic off-camera")
	assert_near(Engine.time_scale, 1.0, 0.0001, "the game is never slowed off-camera")
	assert_true(locks.is_empty(), "input is never locked off-camera")

	if is_instance_valid(coin):
		coin.queue_free()
	sb.free()


# --- The earrings seam ---

func _stub_with_signal() -> Node:
	# A stand-in for a post-earrings PlinkoBoard: it has the signal.
	var n := Node.new()
	n.add_user_signal("coin_transported")
	return n


func test_connect_transporter_is_idempotent() -> void:
	print("test_connect_transporter_is_idempotent")
	var board := _stub_with_signal()
	var handler := func(_b: int, _c: int, _p: Vector3) -> void: pass
	assert_true(SpaceBoard.connect_transporter(board, handler), "first call connects")
	assert_false(SpaceBoard.connect_transporter(board, handler), "second call is a no-op")
	assert_true(board.is_connected("coin_transported", handler), "exactly one connection")
	board.free()


func test_connect_transporter_without_signal_is_silent() -> void:
	print("test_connect_transporter_without_signal_is_silent")
	# The pre-earrings world: PlinkoBoard has no coin_transported yet. This must
	# be a silent no-op, not an error — and the string API is what keeps main.gd
	# parsing at all before the other branch lands.
	var board := Node.new()
	assert_false(board.has_signal("coin_transported"), "stub has no transporter signal")
	assert_false(SpaceBoard.connect_transporter(board, func() -> void: pass),
		"missing signal is a silent no-op")
	assert_false(SpaceBoard.connect_transporter(null, func() -> void: pass),
		"a null board is a silent no-op")
	board.free()


func test_main_scene_carries_the_space_board() -> void:
	print("test_main_scene_carries_the_space_board")
	# The board is a permanent child of main.tscn, always in the scene and just
	# off-camera at normal framing. Checked through the PackedScene's state
	# rather than by instantiating — instantiating Main would boot the whole
	# game (and its save) inside a unit test.
	var packed: PackedScene = load("res://entities/main/main.tscn")
	assert_true(packed != null, "main.tscn loads")
	var state := packed.get_state()
	var found := false
	for i in state.get_node_count():
		if state.get_node_name(i) == "SpaceBoard":
			found = true
			break
	assert_true(found, "main.tscn contains the SpaceBoard node")


# --- Shockwave tint (VfxUtils) ---

func test_ring_params_defaults_are_the_legacy_ring() -> void:
	print("test_ring_params_defaults_are_the_legacy_ring")
	# Adding a tint must not change a single existing caller's ring.
	var t: VisualTheme = ThemeProvider.theme
	var p := VfxUtils._ring_params({})
	assert_near(p["ring_width"], 0.06, 0.0001, "legacy ring width")
	assert_near(p["distortion_strength"], 0.008, 0.0001, "legacy distortion")
	assert_equal(p["ring_count"], t.prestige_ring_count, "ring count from theme")
	assert_near(p["ring_stagger"], t.prestige_ring_stagger, 0.0001, "stagger from theme")
	assert_near(p["duration"], t.prestige_ring_duration, 0.0001, "duration from theme")
	assert_near(p["color_strength"], 0.0, 0.0001,
		"tint strength defaults to 0 — existing callers are pixel-identical")


func test_ring_params_overrides_apply() -> void:
	print("test_ring_params_overrides_apply")
	var p := VfxUtils._ring_params({
		"color": Color(1, 0, 0),
		"color_strength": 0.5,
		"duration": 1.25,
	})
	assert_equal(p["color"], Color(1, 0, 0), "colour passes through opts")
	assert_near(p["color_strength"], 0.5, 0.0001, "strength passes through opts")
	assert_near(p["duration"], 1.25, 0.0001,
		"explicit duration (the shockwave fires outside slow-mo)")


# --- Win overlay ---

func test_win_overlay_dismisses_and_can_be_rebuilt() -> void:
	print("test_win_overlay_dismisses_and_can_be_rebuilt")
	var overlay := SpaceWinOverlay.new()
	var dismissed := [0]
	overlay.dismissed.connect(func() -> void: dismissed[0] += 1)
	add_child(overlay)
	await get_tree().process_frame
	assert_true(overlay.layer > 90, "win card sits above the shockwave canvas (layer 90)")
	overlay.dismiss()
	assert_equal(dismissed[0], 1, "dismiss emits once")
	await get_tree().process_frame
	assert_false(is_instance_valid(overlay), "overlay frees itself on dismiss")

	# Re-triggerable for filming: a fresh one can always be built.
	var again := SpaceWinOverlay.new()
	add_child(again)
	await get_tree().process_frame
	assert_true(is_instance_valid(again), "a second overlay can be shown")
	again.dismiss()
	await get_tree().process_frame
