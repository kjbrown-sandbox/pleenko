class_name WanderingBucketSelector

## Pure static picker for any system that wanders a "live" target across the
## board's buckets (gameplay-target wander, bomb hazards). Callers own their
## own timer state — this module just answers "given the current target and a
## set of allowed indices, pick a new one." No scene tree, no VisualTheme, no
## autoloads, no per-instance state.
##
## Usage:
##     var allowed := board.get_reachable_bucket_indices()
##     var rng_fn := func(n: int) -> int: return randi() % n
##     var next := WanderingBucketSelector.pick(allowed, current_index, rng_fn)


## Picks a bucket from `allowed` that is not `current_index`. Returns
## `current_index` unchanged when the pool is empty or contains only the
## current value. Pure over `rng_fn` for deterministic testing.
##
## `rng_fn` signature: `(max_exclusive: int) -> int`, e.g. `randi() % n`.
static func pick(allowed: PackedInt32Array, current_index: int, rng_fn: Callable) -> int:
	if allowed.is_empty():
		return current_index
	var candidates: PackedInt32Array = PackedInt32Array()
	for idx in allowed:
		if idx != current_index:
			candidates.append(idx)
	if candidates.is_empty():
		return current_index
	var roll: int = rng_fn.call(candidates.size())
	return candidates[clampi(roll, 0, candidates.size() - 1)]
