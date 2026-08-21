class_name DeflectorModel
extends RefCounted

## Peg-deflector state and rules for one board: which pegs hold a deflector,
## which way each points, and whether another may be placed.
##
## Pure model — no scene tree, no autoloads, no saving. The slot cap and the
## global placed-count are injected as Callables so a bare model is testable and
## so the cap can stay a cross-board concern (the upgrade is universal).
## PlinkoBoard owns the public vocabulary (ClickAction / DeflectorOutcome) and
## maps these primitives onto it.

## A deflector *encourages* its direction rather than forcing it: the coin
## follows with probability (s+1)/(s+2), giving a 6:1 split at strength 5.
const BASE_STRENGTH := 5

## peg_index -> Enums.Direction
var _dirs: Dictionary = {}

## () -> int, total slots the player owns. Defaults to zero (nothing placeable).
var cap_fn: Callable = func() -> int: return 0

## () -> int, deflectors placed across ALL boards. Defaults to this board's own
## count, which is correct for a single-board test.
var placed_total_fn: Callable


func _init() -> void:
	placed_total_fn = count


static func bias_for_strength(s: int) -> float:
	return float(s + 1) / float(s + 2)


func bias() -> float:
	return bias_for_strength(BASE_STRENGTH)


func count() -> int:
	return _dirs.size()


func has(peg_idx: int) -> bool:
	return _dirs.has(peg_idx)


## Enums.Direction, or 0 when this peg has no deflector.
func dir_of(peg_idx: int) -> int:
	return _dirs.get(peg_idx, 0)


func keys() -> Array:
	return _dirs.keys()


func cap() -> int:
	return cap_fn.call()


func placed_total() -> int:
	return placed_total_fn.call()


## True when a *new* deflector fits. Re-aiming an existing peg is always allowed
## and never consumes a slot, so callers check `has()` first.
func can_place(peg_idx: int) -> bool:
	return has(peg_idx) or placed_total() < cap()


func place(peg_idx: int, dir: int) -> bool:
	if not can_place(peg_idx):
		return false
	_dirs[peg_idx] = dir
	return true


func remove(peg_idx: int) -> void:
	_dirs.erase(peg_idx)


func clear() -> void:
	_dirs.clear()


## Legacy 50/50 pick — bit-identical to the old `1 if randf() < 0.5 else -1`.
static func random_dir(roll: float) -> int:
	return Enums.Direction.RIGHT if roll < 0.5 else Enums.Direction.LEFT


## Direction a coin leaves this peg. Bit-identical to the legacy 50/50 when no
## deflector is present — the trajectory tests depend on that.
func resolve_bounce(peg_idx: int, roll: float) -> int:
	if _dirs.is_empty():
		return random_dir(roll)
	if _dirs.has(peg_idx):
		var d: int = _dirs[peg_idx]
		return d if roll < bias() else -d
	return random_dir(roll)


func serialize() -> Array:
	var out: Array = []
	for idx in _dirs:
		out.append({"peg": idx, "dir": _dirs[idx]})
	return out


## Drops entries off the current grid or beyond the slot cap. Boards restore
## sequentially, so the global cap is enforced as we go.
func restore(raw: Array, total_pegs: int) -> void:
	_dirs.clear()
	var slots: int = cap()
	for entry in raw:
		if not (entry is Dictionary):
			continue
		var idx: int = int(entry.get("peg", -1))
		var dir: int = int(entry.get("dir", 0))
		if idx < 0 or idx >= total_pegs:
			continue
		if dir != Enums.Direction.LEFT and dir != Enums.Direction.RIGHT:
			continue
		if placed_total() >= slots:
			break
		_dirs[idx] = dir
