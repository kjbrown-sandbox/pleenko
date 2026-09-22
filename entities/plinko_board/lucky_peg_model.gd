class_name LuckyPegModel
extends RefCounted

## Wander state for one board's lucky pegs: which lattice pegs are live, how long
## each has left, and which ones are waiting out a respawn gap.
##
## Pure RefCounted — no scene tree, no autoloads, no VisualTheme, no painting.
## The board owns the visuals and reads `live`/`fade_progress` to paint; the
## model owns only timing and selection. That split is what makes the whole
## mechanic testable headless (the DeflectorModel precedent), including the parts
## that used to need a real board.
##
## Everything the model can't know is injected as a Callable:
##   target_count_fn: () -> int          how many pegs this board should run
##   is_voided_fn:    (row, col) -> bool whether a bomb destroyed that cell
##   rng_fn:          (n) -> int         index picker, for deterministic tests

## Seconds a peg stays live before giving up and moving elsewhere. The board
## aliases its golden-bucket constants onto these so the two wandering systems
## can't drift apart.
var duration: float = 8.0

## Begin fading with this long left.
var fade_start: float = 1.0

## Gap between a peg being consumed and its replacement appearing. Load-bearing
## for the split-rate bound — see the note on `max_splits_per_second`.
var respawn_delay: float = 0.5

var target_count_fn: Callable = func() -> int: return 0
var is_voided_fn: Callable = func(_row: int, _col: int) -> bool: return false
var rng_fn: Callable = func(n: int) -> int: return randi() % maxi(1, n)

## peg_index -> seconds remaining.
var _live: Dictionary = {}

## Countdowns for pegs awaiting a respawn. Plain floats — which peg comes next is
## decided when the timer fires, not when it is queued.
var _respawns: Array[float] = []


## One peg per upgrade level, so buying the upgrade immediately puts one on every
## board rather than only raising a chance.
static func count_for_level(level: int) -> int:
	return maxi(0, level)


## Upper bound on splits per second for one board, since every split consumes a
## peg and pegs only come back at `respawn_delay`.
##
## This is the real reason uncapped splitting is safe. The intuitive argument
## ("a peg is consumed, so one descent crosses at most `level` of them") is FALSE
## — respawns mean a multi-second descent can cross far more than `level`. The
## rate bound holds regardless of board size, descent length, or how deep the
## split tree goes, which the per-descent argument does not.
static func max_splits_per_second(level: int, respawn_delay_s: float) -> float:
	if respawn_delay_s <= 0.0:
		return INF
	return count_for_level(level) / respawn_delay_s


## Peg indices a lucky peg may occupy: every peg on the lattice except those in a
## voided column and those already holding one. Pure over `is_voided_fn` so it is
## testable without a board or a bomb.
static func candidates(num_rows: int, taken: Array, is_voided_fn: Callable) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for row in num_rows:
		for col in row + 1:
			if is_voided_fn.call(row, col):
				continue
			if Lattice.peg_index(row, col) in taken:
				continue
			out.append(Lattice.peg_index(row, col))
	return out


## Live peg indices. A copy, so callers may mutate the model while iterating.
func live() -> Array:
	return _live.keys()


func count() -> int:
	return _live.size()


func has(peg_idx: int) -> bool:
	return _live.has(peg_idx)


func pending_respawns() -> int:
	return _respawns.size()


## 0.0 -> 1.0 as a peg approaches expiry; the board lerps its marker back toward
## the ordinary peg colour by this. Returns 0.0 for a peg that isn't fading yet,
## so the common case needs no branch at the call site.
func fade_progress(peg_idx: int) -> float:
	if not _live.has(peg_idx) or fade_start <= 0.0:
		return 0.0
	var remaining: float = _live[peg_idx]
	if remaining >= fade_start:
		return 0.0
	return clampf(1.0 - remaining / fade_start, 0.0, 1.0)


## Consumes the peg at `peg_idx` if it is live, queuing its replacement. Returns
## whether it was. Consuming is what stops a second coin arriving in the same
## frame from claiming the same payout twice.
func try_consume(peg_idx: int) -> bool:
	if not _live.has(peg_idx):
		return false
	_retire(peg_idx)
	return true


## Advances every timer and tops the board back up to its target count. Returns
## `{"spawned": [...], "retired": [...]}` so the board can repaint exactly the
## pegs that changed rather than rewriting the whole MultiMesh each frame.
func tick(delta: float, num_rows: int) -> Dictionary:
	var spawned: Array[int] = []
	var retired: Array[int] = []

	var target: int = target_count_fn.call()
	if target <= 0:
		# Upgrade unowned, or reset away (prestige, challenge entry). Tear down.
		retired.assign(_live.keys())
		_live.clear()
		_respawns.clear()
		return {"spawned": spawned, "retired": retired}

	# .keys() is a snapshot — we erase inside this loop, and iterating the
	# Dictionary directly would invalidate the iterator.
	for peg_idx: int in _live.keys():
		_live[peg_idx] = _live[peg_idx] - delta
		if _live[peg_idx] <= 0.0:
			_retire(peg_idx)
			retired.append(peg_idx)

	var i: int = _respawns.size() - 1
	while i >= 0:
		_respawns[i] -= delta
		if _respawns[i] <= 0.0:
			_respawns.remove_at(i)
		i -= 1

	# Top up whatever the level allows that is neither live nor waiting out a gap.
	var wanted: int = target - _live.size() - _respawns.size()
	for _n in maxi(0, wanted):
		var peg_idx: int = _pick(num_rows)
		if peg_idx < 0:
			break
		_live[peg_idx] = duration
		spawned.append(peg_idx)

	return {"spawned": spawned, "retired": retired}


## Drops live pegs that the lattice no longer has room for after a rebuild, so a
## marker can never end up pointing at a different peg than the one it lit.
## Returns the dropped indices for the board to unpaint.
func drop_pegs_beyond(num_rows: int) -> Array[int]:
	var dropped: Array[int] = []
	var limit: int = Lattice.peg_count(num_rows)
	for peg_idx: int in _live.keys():
		if peg_idx >= limit:
			_retire(peg_idx)
			dropped.append(peg_idx)
	return dropped


## Releases pegs a bomb has just destroyed. The spawn filter already refuses
## voided cells; this is the symmetric half, for a column voided UNDER a live
## peg — otherwise the marker goes invisible but keeps holding a slot.
func release_pegs(peg_indices: PackedInt32Array) -> Array[int]:
	var released: Array[int] = []
	for peg_idx in peg_indices:
		if _live.has(peg_idx):
			_retire(peg_idx)
			released.append(peg_idx)
	return released


func clear() -> void:
	_live.clear()
	_respawns.clear()


func _retire(peg_idx: int) -> void:
	_live.erase(peg_idx)
	_respawns.append(respawn_delay)


func _pick(num_rows: int) -> int:
	var pool: PackedInt32Array = candidates(num_rows, _live.keys(), is_voided_fn)
	if pool.is_empty():
		return -1
	var roll: int = rng_fn.call(pool.size())
	return pool[clampi(roll, 0, pool.size() - 1)]
