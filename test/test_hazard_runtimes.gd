extends "res://test/test_base.gd"

## Hazard runtime tests — BombHazardRuntime + ForbiddenBucketHazardRuntime.
## Use Callable seams (rng / reachable / fail / void) to drive deterministic
## state transitions without instantiating a real PlinkoBoard.
## Run with: godot --headless --scene res://test/test_hazard_runtimes.tscn


func _run_tests() -> void:
	print("\n=== Hazard Runtime Tests ===\n")

	# Forbidden bucket
	test_forbidden_landing_at_matching_bucket_fails()
	test_forbidden_landing_elsewhere_does_not_fail()
	test_forbidden_wrong_board_does_not_fail()
	test_forbidden_failure_string_preserved()

	# Bomb
	test_bomb_spawns_in_reachable_only()
	test_bomb_detonates_when_timer_hits_zero()
	test_bomb_defuse_on_coin_land()
	test_bombs_dont_overlap()
	test_bomb_idle_when_no_reachable_buckets()
	test_bomb_countdown_label_updates_on_integer_seconds()
	test_bomb_does_not_tick_until_started()


# ── Helpers ─────────────────────────────────────────────────────────

# Picks index 0 from the candidate pool — keeps assertions deterministic.
func _first_rng() -> Callable:
	return func(_n: int) -> int: return 0


# Tracks every (board_type, bucket_index) void_column_fn was called with.
class VoidRecorder:
	var calls: Array[Dictionary] = []
	func record(board_type: int, bucket_index: int) -> void:
		calls.append({"board_type": board_type, "bucket_index": bucket_index})


# Tracks every fail_challenge_fn call.
class FailRecorder:
	var reasons: PackedStringArray = PackedStringArray()
	func record(reason: String) -> void:
		reasons.append(reason)


# Returns a constant set of reachable bucket indices on every query.
func _const_reachable(indices: Array) -> Callable:
	var arr: PackedInt32Array = PackedInt32Array(indices)
	return func(_board_type: int) -> PackedInt32Array: return arr.duplicate()


# Builds a ForbiddenBucketHazardRuntime wired with injected seams. board_manager
# is left null so the runtime's optional visual-marking calls early-return.
func _forbidden_runtime(board_type: int, bucket_index: int, fail_rec: FailRecorder) -> ForbiddenBucketHazardRuntime:
	var hazard := ForbiddenBucketHazard.new()
	hazard.board_type = board_type
	hazard.bucket_index = bucket_index
	var rt := ForbiddenBucketHazardRuntime.new()
	rt.hazard = hazard
	rt.fail_challenge_fn = Callable(fail_rec, "record")
	rt.setup(null)
	return rt


# Builds a BombHazardRuntime with reachable + RNG + void recorders injected.
func _bomb_runtime(reachable: Array, void_rec: VoidRecorder, count: int = 1, timer: float = 5.0, mult: float = 2.0) -> BombHazardRuntime:
	var hazard := BombHazard.new()
	hazard.board_type = Enums.BoardType.GOLD
	hazard.bomb_count = count
	hazard.timer_seconds = timer
	hazard.defuse_multiplier = mult
	var rt := BombHazardRuntime.new()
	rt.hazard = hazard
	rt.rng_fn = _first_rng()
	rt.get_reachable_buckets_fn = _const_reachable(reachable)
	rt.void_column_fn = Callable(void_rec, "record")
	rt.setup(null)
	return rt


# ── Forbidden bucket ────────────────────────────────────────────────

func test_forbidden_landing_at_matching_bucket_fails() -> void:
	print("test_forbidden_landing_at_matching_bucket_fails")
	var rec := FailRecorder.new()
	var rt := _forbidden_runtime(Enums.BoardType.GOLD, 3, rec)
	rt.on_coin_landed(Enums.BoardType.GOLD, 3, Enums.CurrencyType.GOLD_COIN, 5, 1.0)
	assert_equal(rec.reasons.size(), 1, "exactly one fail")
	rt.free()


func test_forbidden_landing_elsewhere_does_not_fail() -> void:
	print("test_forbidden_landing_elsewhere_does_not_fail")
	var rec := FailRecorder.new()
	var rt := _forbidden_runtime(Enums.BoardType.GOLD, 3, rec)
	rt.on_coin_landed(Enums.BoardType.GOLD, 4, Enums.CurrencyType.GOLD_COIN, 5, 1.0)
	assert_equal(rec.reasons.size(), 0, "no fail when bucket index differs")
	rt.free()


func test_forbidden_wrong_board_does_not_fail() -> void:
	print("test_forbidden_wrong_board_does_not_fail")
	var rec := FailRecorder.new()
	var rt := _forbidden_runtime(Enums.BoardType.GOLD, 3, rec)
	rt.on_coin_landed(Enums.BoardType.ORANGE, 3, Enums.CurrencyType.ORANGE_COIN, 5, 1.0)
	assert_equal(rec.reasons.size(), 0, "no fail when board type differs")
	rt.free()


func test_forbidden_failure_string_preserved() -> void:
	print("test_forbidden_failure_string_preserved")
	# UX (and presumably saved replays / analytics) depend on the literal string
	# from the legacy NeverTouchBucket constraint. Don't let it drift.
	var rec := FailRecorder.new()
	var rt := _forbidden_runtime(Enums.BoardType.GOLD, 0, rec)
	rt.on_coin_landed(Enums.BoardType.GOLD, 0, Enums.CurrencyType.GOLD_COIN, 5, 1.0)
	assert_equal(rec.reasons[0], "Landed in forbidden bucket!", "literal legacy string")
	rt.free()


# ── Bomb hazard ─────────────────────────────────────────────────────

func test_bomb_spawns_in_reachable_only() -> void:
	print("test_bomb_spawns_in_reachable_only")
	var void_rec := VoidRecorder.new()
	# Only buckets 2 and 5 are reachable; rng=0 → pick the first allowed.
	var rt := _bomb_runtime([2, 5], void_rec)
	assert_equal(rt._bombs.size(), 1, "one bomb spawned")
	# bomb_count=1, current_index starts at -1 (not in allowed) → candidates = [2, 5]
	# pick index 0 → 2.
	assert_equal(rt._bombs[0]["bucket_index"], 2, "bomb spawned at the first reachable")
	rt.free()


func test_bomb_detonates_when_timer_hits_zero() -> void:
	print("test_bomb_detonates_when_timer_hits_zero")
	var void_rec := VoidRecorder.new()
	var rt := _bomb_runtime([2, 5], void_rec, 1, 1.0)
	rt.start_ticking()  # production flow: tracker arms ticking on first drop
	# Advance past the timer in one tick — should detonate and repick.
	rt._process(1.5)
	assert_equal(void_rec.calls.size(), 1, "exactly one void_column call")
	assert_equal(void_rec.calls[0]["bucket_index"], 2, "voided the original bomb bucket")
	# After detonation the bomb should repick (still at bucket 5 left or [2] if 2 still reachable in the seam).
	# Our seam doesn't know about voiding, so reachable still returns [2,5]. With prev=-1 (cleared) → first non-current = 2.
	# Either way the bomb is alive again.
	assert_true(rt._bombs[0]["bucket_index"] >= 0, "bomb repicked after detonation")
	rt.free()


func test_bomb_defuse_on_coin_land() -> void:
	print("test_bomb_defuse_on_coin_land")
	var void_rec := VoidRecorder.new()
	var rt := _bomb_runtime([2, 5], void_rec, 1, 5.0)
	var original_index: int = rt._bombs[0]["bucket_index"]
	# Land a coin in the bomb's bucket → defuse.
	rt.on_coin_landed(Enums.BoardType.GOLD, original_index, Enums.CurrencyType.GOLD_COIN, 10, 1.0)
	assert_equal(void_rec.calls.size(), 0, "defuse must NOT detonate")
	# After defuse the bomb either migrated to a new position or stayed; either way it should be alive.
	assert_true(rt._bombs[0]["bucket_index"] >= 0, "bomb still active after defuse (repicked)")
	rt.free()


func test_bombs_dont_overlap() -> void:
	print("test_bombs_dont_overlap")
	var void_rec := VoidRecorder.new()
	# 2 reachable, 2 bombs — each bomb must occupy a distinct bucket.
	var rt := _bomb_runtime([3, 7], void_rec, 2, 5.0)
	var b0: int = rt._bombs[0]["bucket_index"]
	var b1: int = rt._bombs[1]["bucket_index"]
	assert_true(b0 >= 0, "bomb 0 placed")
	assert_true(b1 >= 0, "bomb 1 placed")
	assert_true(b0 != b1, "two bombs occupy two distinct buckets")
	rt.free()


func test_bomb_idle_when_no_reachable_buckets() -> void:
	print("test_bomb_idle_when_no_reachable_buckets")
	var void_rec := VoidRecorder.new()
	# Whole board voided → no reachable → bomb sits at -1 with no timer activity.
	var rt := _bomb_runtime([], void_rec)
	rt.start_ticking()
	assert_equal(rt._bombs[0]["bucket_index"], -1, "no placement when nothing reachable")
	# Process for several ticks; nothing should detonate.
	for i in 5:
		rt._process(1.0)
	assert_equal(void_rec.calls.size(), 0, "no detonation when there's nothing to be on")
	rt.free()


func test_bomb_countdown_label_updates_on_integer_seconds() -> void:
	print("test_bomb_countdown_label_updates_on_integer_seconds")
	# Spawn with timer=5.0. last_int_second seeds at 5 (ceil). After +0.4s,
	# time_remaining=4.6 → ceil=5 (no change). After +1.5s, time_remaining=3.1
	# → ceil=4 (change). The runtime only re-emits the label on each integer
	# crossing — this prevents flooding set_bomb_countdown every frame.
	var void_rec := VoidRecorder.new()
	var rt := _bomb_runtime([2, 5], void_rec, 1, 5.0)
	rt.start_ticking()
	assert_equal(rt._bombs[0]["last_int_second"], 5, "starts at ceil(timer_seconds)")
	rt._process(0.4)
	assert_equal(rt._bombs[0]["last_int_second"], 5, "no change inside the same integer second")
	rt._process(1.5)  # total = 1.9s elapsed → 3.1 remaining → ceil=4
	assert_equal(rt._bombs[0]["last_int_second"], 4, "crossed integer boundary → label step")
	rt.free()


func test_bomb_does_not_tick_until_started() -> void:
	print("test_bomb_does_not_tick_until_started")
	# Production rule: countdown is paused until the player's first drop. The
	# runtime sets up + places visuals at challenge start, but no time passes
	# until ChallengeTracker calls start_ticking on coin_dropped.
	var void_rec := VoidRecorder.new()
	var rt := _bomb_runtime([2, 5], void_rec, 1, 2.0)
	rt._process(10.0)  # plenty of time to detonate IF it were ticking
	assert_equal(void_rec.calls.size(), 0, "no detonation while _ticking is false")
	rt.start_ticking()
	rt._process(2.5)
	assert_equal(void_rec.calls.size(), 1, "detonates once ticking is armed")
	rt.free()
