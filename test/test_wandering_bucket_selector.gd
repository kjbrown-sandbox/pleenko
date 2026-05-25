extends "res://test/test_base.gd"

## WanderingBucketSelector.pick() tests — pure picker logic, no scene tree.
## Run with: godot --headless --scene res://test/test_wandering_bucket_selector.tscn


func _run_tests() -> void:
	print("\n=== WanderingBucketSelector Tests ===\n")

	test_picks_from_allowed()
	test_avoids_current_index()
	test_returns_current_when_allowed_empty()
	test_returns_current_when_allowed_is_only_current()
	test_rng_clamped_when_out_of_range()


# Deterministic RNG seam — always returns the same index.
func _const_rng(value: int) -> Callable:
	return func(_n: int) -> int: return value


func test_picks_from_allowed() -> void:
	print("test_picks_from_allowed")
	var allowed: PackedInt32Array = PackedInt32Array([3, 7, 9])
	# rng returns 1 → candidates after filtering current=0 are [3,7,9]; pick index 1 = 7
	var picked: int = WanderingBucketSelector.pick(allowed, 0, _const_rng(1))
	assert_equal(picked, 7, "rng=1 over [3,7,9] returns 7")


func test_avoids_current_index() -> void:
	print("test_avoids_current_index")
	# current=5 is in allowed; the picker filters it out, so candidates = [1, 9]
	var allowed: PackedInt32Array = PackedInt32Array([1, 5, 9])
	var picked0: int = WanderingBucketSelector.pick(allowed, 5, _const_rng(0))
	var picked1: int = WanderingBucketSelector.pick(allowed, 5, _const_rng(1))
	assert_equal(picked0, 1, "rng=0 over [1,9] returns 1")
	assert_equal(picked1, 9, "rng=1 over [1,9] returns 9")


func test_returns_current_when_allowed_empty() -> void:
	print("test_returns_current_when_allowed_empty")
	# No reachable buckets → keep the current target (which itself is a no-op
	# at the call site since the bomb runtime treats -1 specially).
	var picked: int = WanderingBucketSelector.pick(PackedInt32Array(), 3, _const_rng(0))
	assert_equal(picked, 3, "empty allowed → returns current unchanged")


func test_returns_current_when_allowed_is_only_current() -> void:
	print("test_returns_current_when_allowed_is_only_current")
	# Only candidate is the current → filter strips it → nothing to pick → current.
	var allowed: PackedInt32Array = PackedInt32Array([4])
	var picked: int = WanderingBucketSelector.pick(allowed, 4, _const_rng(0))
	assert_equal(picked, 4, "single-candidate matching current → returns current")


func test_rng_clamped_when_out_of_range() -> void:
	print("test_rng_clamped_when_out_of_range")
	# Defensive: if rng_fn returns something out of [0, n), clamp to range so
	# we never index past the candidates array (would crash otherwise).
	var allowed: PackedInt32Array = PackedInt32Array([1, 2, 3])
	var picked_high: int = WanderingBucketSelector.pick(allowed, 0, _const_rng(99))
	var picked_low: int = WanderingBucketSelector.pick(allowed, 0, _const_rng(-5))
	assert_equal(picked_high, 3, "rng=99 clamped to last candidate")
	assert_equal(picked_low, 1, "rng=-5 clamped to first candidate")
