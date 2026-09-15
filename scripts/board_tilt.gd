class_name BoardTilt

## Centre-seeking bounce bias for one board — blue's signature upgrade.
##
## The player sets a per-board slider from "Centre" to "Edges". Left of default
## biases each bounce TOWARD board-local x = 0; right biases AWAY. The upgrade
## level sets how strong the extremes are; the slider chooses direction and how
## much of that strength to apply.
##
## Crucially this is NOT a fixed left/right bias. Which way is "toward centre"
## depends on which side of the board the coin is currently on, so the same
## setting pulls a left-side coin right and a right-side coin left.
##
## Pure static module (the Lattice / EarringGeometry shape): no scene tree, no
## autoloads, no VisualTheme. The board owns the notch and the level lookup.

## Slider positions. NOTCH_DEFAULT is the untilted middle; the labelled ends are
## the extremes, and the two unlabelled stops apply half the strength.
const NOTCH_CENTRE := -2
const NOTCH_DEFAULT := 0
const NOTCH_EDGES := 2

## An untilted coin is a fair coin.
const FAIR := 0.5

## Probability of following the favoured direction at an extreme, at level 1.
const LEVEL_1_EXTREME_BIAS := 0.55

## Each level beyond the first adds this much at the extremes.
const BIAS_PER_EXTRA_LEVEL := 0.025

## Hard ceiling. Cap raises can push the level far past the .tres max_level, and
## a board that lands every coin in the same bucket stops being a Plinko board.
const MAX_EXTREME_BIAS := 0.75


## Clamps a notch into the slider's range. Saves are the untrusted source here.
static func clamp_notch(notch: int) -> int:
	return clampi(notch, NOTCH_CENTRE, NOTCH_EDGES)


## Strength at a fully-pushed slider, for this upgrade level. Level 0 (unowned)
## is a fair coin no matter where the slider sits.
static func bias_at_extreme(level: int) -> float:
	if level <= 0:
		return FAIR
	return minf(LEVEL_1_EXTREME_BIAS + (level - 1) * BIAS_PER_EXTRA_LEVEL, MAX_EXTREME_BIAS)


## Probability of following the favoured direction at this notch and level.
## Scales linearly from FAIR at the default stop to bias_at_extreme at the ends.
static func bias_for(level: int, notch: int) -> float:
	var extreme: float = bias_at_extreme(level)
	var magnitude: float = absi(clamp_notch(notch)) / float(NOTCH_EDGES)
	return FAIR + (extreme - FAIR) * magnitude


## Which way is TOWARD board-local x = 0 from lattice cell (row, col), or 0 when
## the coin is already dead-centre and neither way is "inward".
##
## Lattice.x_for is `space * (col - row/2)`, so the sign of `2*col - row` is the
## side the coin is on — compared as integers so a dead-centre cell is exact
## rather than a float epsilon away from it.
static func toward_centre(row: int, col: int) -> int:
	var side: int = 2 * col - row
	if side < 0:
		return Enums.Direction.RIGHT
	if side > 0:
		return Enums.Direction.LEFT
	return 0


## The direction this tilt favours at (row, col), or 0 when it has no opinion.
static func favoured_direction(row: int, col: int, notch: int) -> int:
	var clamped: int = clamp_notch(notch)
	if clamped == NOTCH_DEFAULT:
		return 0
	var inward: int = toward_centre(row, col)
	if inward == 0:
		return 0
	return inward if clamped < NOTCH_DEFAULT else -inward


## Resolves a bounce, or returns 0 for "no opinion — use the normal path".
##
## Returning 0 rather than a coin flip is what preserves bit-identical legacy
## behaviour at the default slider position: DeflectorModel.resolve_bounce maps
## `roll < 0.5` to RIGHT, and a tilt that favoured LEFT would silently invert
## every trajectory the existing tests pin.
static func direction_for(row: int, col: int, notch: int, level: int, roll: float) -> int:
	if level <= 0:
		return 0
	var favoured: int = favoured_direction(row, col, notch)
	if favoured == 0:
		return 0
	return favoured if roll < bias_for(level, notch) else -favoured


## Player-facing label for a notch. Only the ends are named — the middle is the
## neutral default and the two half stops are deliberately unlabelled.
static func notch_label(notch: int) -> String:
	match clamp_notch(notch):
		NOTCH_CENTRE:
			return "Centre"
		NOTCH_EDGES:
			return "Edges"
		_:
			return ""
