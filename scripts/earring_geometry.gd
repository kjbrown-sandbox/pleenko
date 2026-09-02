class_name EarringGeometry

## Pure static geometry + gating for the "earrings" board extension — the single
## source of truth for how one ADD_ROW purchase changes a board's size.
##
## Once the main triangle is full (MAIN_MAX_ROWS rows), further purchases stop
## growing it and instead grow two smaller triangles hanging beneath its two
## edge buckets. Those grow down and inward until their inner edges meet at the
## board's centre line, at which point the meeting point becomes a transporter.
##
##      /\            main board, frozen at MAIN_MAX_ROWS rows
##     /__\           its bucket row; edge buckets at +/- s*(buckets-1)/2
##    /\  /\          the two earrings, growing down and inward
##   /__\/__\
##       ^  transporter, at x = 0
##
## Pure static module (same shape as Lattice / OfflineCalculator): no scene tree,
## no autoloads, no VisualTheme. Positions are derived from `Lattice`, never
## hardcoded, so PlinkoBoard, EarringBoard and the tests cannot drift apart.
##
## `earrings_enabled` is threaded through as a parameter rather than read from an
## autoload. Normal-play boards always have it true; a challenge board takes it
## from `ChallengeData.grows_earrings`, and when false the board is UNCAPPED
## (StartingBoards grows challenge boards by looping add_two_rows, so an
## unconditional cap would silently shrink every authored challenge board).

## Rows a board starts with, matching CoinSurface.num_rows' default.
const STARTING_ROWS := 2
## Rows a single ADD_ROW purchase is worth.
const ROWS_PER_PURCHASE := 2
## The main triangle stops growing here: 8 rows -> 9 buckets. Every further
## ADD_ROW purchase grows the earrings instead.
const MAIN_MAX_ROWS := 8

## Which edge bucket an earring hangs from. Also selects which end of the
## earring's bottom row faces the board centre.
const SIDE_LEFT := -1
const SIDE_RIGHT := 1


## A triangular lattice with `rows` peg rows lands coins in `rows + 1` buckets.
static func buckets_for_rows(rows: int) -> int:
	return rows + 1


## Rows an earring needs before its inner edge reaches x = 0.
##
## Derived, never a literal: an earring apexed at an edge bucket sits at
## |x| = s * (buckets - 1) / 2, and each extra row walks its bottom row's inner
## corner s/2 further toward the centre, so it arrives after exactly
## (buckets - 1) rows. On a 9-bucket main board that is 8.
static func max_earring_rows() -> int:
	return buckets_for_rows(MAIN_MAX_ROWS) - 1


## Total rows an ADD_ROW level is worth, before the main/earring split.
static func total_rows_for_level(add_row_level: int) -> int:
	return STARTING_ROWS + maxi(0, add_row_level) * ROWS_PER_PURCHASE


## Peg rows of the MAIN triangle at this ADD_ROW level. The one formula behind
## both the save/reload path and the runtime growth path.
static func main_rows_for_level(add_row_level: int, earrings_enabled: bool) -> int:
	var total: int = total_rows_for_level(add_row_level)
	if not earrings_enabled:
		return total
	return mini(total, MAIN_MAX_ROWS)


## Peg rows of EACH earring at this ADD_ROW level (both earrings are always the
## same size). 0 until the main triangle is full; clamped at max_earring_rows().
static func earring_rows_for_level(add_row_level: int, earrings_enabled: bool) -> int:
	if not earrings_enabled:
		return 0
	var total: int = total_rows_for_level(add_row_level)
	return clampi(total - MAIN_MAX_ROWS, 0, max_earring_rows())


## Inverse of the size table: how many ADD_ROW levels a board of this size
## represents. Every level adds exactly ROWS_PER_PURCHASE rows somewhere, so the
## rows past the starting size divided by that step is the level.
static func growth_level_for(main_rows: int, earring_rows: int) -> int:
	@warning_ignore("integer_division")
	return maxi(0, main_rows + earring_rows - STARTING_ROWS) / ROWS_PER_PURCHASE


## One ADD_ROW purchase applied to a board of this size, as (main_rows,
## earring_rows).
##
## Expressed through growth_level_for + the two *_for_level functions on
## purpose: the runtime growth path and the save/reload path then run literally
## the same formula and cannot drift. add_two_rows must NOT read the live
## upgrade level instead — challenge setup grows boards by looping add_two_rows
## without buying anything, so the level would stay 0.
static func grow(main_rows: int, earring_rows: int, earrings_enabled: bool) -> Vector2i:
	var next_level: int = growth_level_for(main_rows, earring_rows) + 1
	return Vector2i(
		main_rows_for_level(next_level, earrings_enabled),
		earring_rows_for_level(next_level, earrings_enabled))


## Hard ceiling on the ADD_ROW upgrade level: the level at which the earrings
## meet and there is nothing left to grow. Derived from the size table, so it
## moves automatically if MAIN_MAX_ROWS does.
##
## Applies ONLY when earrings are enabled — an uncapped (challenge) board keeps
## today's max_level + cap-raise behaviour with no ceiling. Every purchasability
## gate must read this one number: max_level can be RAISED by cap raises, so a
## soft cap alone would let a player spend higher-tier currency on a dead cap.
static func max_add_row_level() -> int:
	return growth_level_for(MAIN_MAX_ROWS, max_earring_rows())


## Board-local x of the LEFT edge bucket. Mirrors build_board()'s
## `bucket_x_offset = -space * (num_buckets - 1) / 2` exactly; the right edge is
## the negation.
static func edge_bucket_x(num_buckets: int, space: float) -> float:
	return -space * float(num_buckets - 1) / 2.0


## Board-local x of the edge bucket an earring on `side` hangs from — i.e. that
## earring's apex.
static func apex_x_for_side(num_buckets: int, space: float, side: int) -> float:
	var left: float = edge_bucket_x(num_buckets, space)
	return left if side == SIDE_LEFT else -left


## Which side of the board an apex at `apex_x` sits on. Board centre (0) counts
## as left; the only caller that could pass it is a degenerate 1-bucket board.
static func side_of_apex(apex_x: float) -> int:
	return SIDE_LEFT if apex_x <= 0.0 else SIDE_RIGHT


## Column of the bottom-row cell nearest the board centre. The bottom row of an
## R-row earring spans cols 0..R; a left earring's inner corner is its rightmost
## column, a right earring's is its leftmost.
static func innermost_bottom_col(earring_rows: int, side: int) -> int:
	return earring_rows if side == SIDE_LEFT else 0


## Earring-parent-local x of that inner corner. Side is taken from the sign of
## `apex_x`, so callers pass the apex they already computed.
static func innermost_bottom_x(apex_x: float, earring_rows: int, space: float) -> float:
	var col: int = innermost_bottom_col(earring_rows, side_of_apex(apex_x))
	return apex_x + Lattice.x_for(earring_rows, col, space)


## True once both earrings' inner corners have arrived at the board centre.
##
## Asked of the geometry, never of a row count: `is_zero_approx` on the derived
## x, never `== 0.0` and never `earring_rows == 8`. Spacing cancels out of the
## comparison, so a unit spacing is used internally.
static func earrings_meet(earring_rows: int, num_buckets: int) -> bool:
	if earring_rows <= 0:
		return false
	var apex: float = edge_bucket_x(num_buckets, 1.0)
	return is_zero_approx(innermost_bottom_x(apex, earring_rows, 1.0))


## True for the two main-board edge buckets once earrings exist beneath them.
## Gateways pay nothing: a coin landing there falls through into the earring and
## is paid down there instead.
static func is_gateway_bucket(index: int, num_buckets: int, earring_rows: int) -> bool:
	if earring_rows <= 0:
		return false
	return index == 0 or index == num_buckets - 1


## True when this board's earrings have met, so the shared transporter bucket
## exists at board-local x = 0.
static func has_transporter(add_row_level: int, num_buckets: int, earrings_enabled: bool) -> bool:
	return earrings_meet(earring_rows_for_level(add_row_level, earrings_enabled), num_buckets)


## True for the earring lattice cell that lands in the transporter — the bucket
## row's inner corner. Only meaningful once `earrings_meet`; callers gate on
## that, because a not-yet-met earring still has an inner corner (it just isn't
## at the centre).
static func is_transporter_cell(row: int, col: int, earring_rows: int, side: int) -> bool:
	if earring_rows <= 0:
		return false
	return row == earring_rows and col == innermost_bottom_col(earring_rows, side)
