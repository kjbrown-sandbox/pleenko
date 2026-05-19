class_name Lattice

## Pure triangular Galton-lattice geometry — the single source of truth for the
## "lattice cell (row, col) -> local position" mapping.
##
## The board is a triangular lattice: row 0 has one peg (col 0); row r has r+1
## pegs (col 0..r). Moving RIGHT off (row, col) lands on (row+1, col+1); LEFT on
## (row+1, col).
##
## Pure static module (same shape as OfflineCalculator / VfxUtils / FormatUtils):
## no scene tree, no VisualTheme, no autoloads — callers pass scalar spacing.
## Both the real PlinkoBoard (build + Coin trajectory, via thin forwarders) and
## the decorative MenuBoard go through here, so the two can't drift apart.


## sqrt-3-over-2: vertical run of a 30/60/90 triangle for horizontal peg
## spacing `space`. The one home for this factor.
static func vertical_spacing(space: float) -> float:
	return space * sqrt(3.0) / 2.0


## Local x of lattice cell (row, col) for horizontal peg spacing `space`.
static func x_for(row: int, col: int, space: float) -> float:
	return -row * space / 2.0 + col * space


## Local-space target a coin tweens to at cell (row, col). `vert_spacing` and
## `row_y_offset` are passed in (NOT derived) so callers that store
## vertical_spacing as an independent field — and tests that set it
## independently — stay exact. Z is left 0; callers apply their own z.
static func cell_to_world(row: int, col: int, space: float,
		vert_spacing: float, row_y_offset: float) -> Vector3:
	return Vector3(x_for(row, col, space), row_y_offset - vert_spacing * row, 0.0)


## Pure integer lattice transition. `direction` is an Enums.Direction (+1 right).
static func next_cell(row: int, col: int, direction: int) -> Vector2i:
	if direction == Enums.Direction.RIGHT:
		return Vector2i(row + 1, col + 1)
	return Vector2i(row + 1, col)
