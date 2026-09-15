@abstract
class_name CoinSurface
extends Node3D

## The contract a falling Coin drives. Anything a coin can bounce down is a
## CoinSurface: the main PlinkoBoard, and each EarringBoard hanging beneath it.
##
## This exists so Coin.board can stay statically typed. The earrings prototype
## duck-typed this interface and had to strip the type off Coin.board to make it
## compile; declaring the surface explicitly restores type safety and makes the
## contract discoverable instead of implied.
##
## `@abstract` (Godot 4.5+) rather than push_error stubs: an implementer missing
## a method is then a parse-time error, not a runtime message nobody reads.
## Subclasses stay concrete so they can still be instantiated.
##
## The shared state below lives here rather than on each implementer because
## Coin reads it directly; GDScript forbids redeclaring it in a subclass.

## Which tier this surface belongs to. An earring inherits its parent board's
## type — coins landing there pay that board's currency.
var board_type: Enums.BoardType

## Peg rows in this surface's triangular lattice. Row r holds r + 1 pegs, and a
## coin that reaches row `num_rows` has fallen into the bucket row.
@export var num_rows: int = 2

## Horizontal distance between neighbouring pegs in a row. All other lattice
## geometry derives from it via `Lattice`.
var space_between_pegs: float


## True once the coin has fallen past the last peg row into the bucket row.
@abstract func is_terminal_cell(row: int, col: int) -> bool

## Surface-local position a coin tweens to at lattice cell (row, col).
@abstract func cell_to_world(row: int, col: int) -> Vector3

## Integer lattice transition; `direction` is an Enums.Direction (+1 = RIGHT).
@abstract func next_lattice_cell(row: int, col: int, direction: int) -> Vector2i

## Bucket child index a coin at this terminal cell lands in.
@abstract func predicted_bucket_index(row: int, col: int) -> int

## Which way the coin leaves the peg at (row, col) for this [0,1) roll.
@abstract func resolve_bounce_direction(row: int, col: int, roll: float) -> int

## True when the cell has been destroyed (bomb fallout) and the coin should fall
## straight through instead of landing.
@abstract func is_lattice_cell_voided(row: int, col: int) -> bool

## The bucket at a child index, or null when out of range.
@abstract func get_bucket(index: int) -> Bucket

## Peg-contact VFX hook. Pure view — a surface with no peg VFX no-ops.
@abstract func flash_nearest_peg(coin_pos: Vector3, currency_type: int) -> void

## Deflector reaction VFX hook, called right after the bounce direction is
## resolved and while (row, col) still points at the peg just struck.
@abstract func notify_deflector_resolved(row: int, col: int, direction: int) -> void

## True when the peg at (row, col) was a lucky peg — and consumes it, so a peg
## can only ever pay out once. Surfaces without lucky pegs return false.
@abstract func try_consume_lucky_peg(row: int, col: int) -> bool

## Splits the striking coin: spawns the twin half and returns the direction the
## ORIGINAL should take (the twin takes the other). Only called immediately
## after try_consume_lucky_peg returned true.
@abstract func resolve_lucky_split(origin: Coin, row: int, col: int) -> int

## Hands a coin back to its own mesh so it can be animated individually
## (the prestige handover). No-op on surfaces that don't pool coins.
@abstract func eject_coin_from_multimesh(coin: Coin) -> void
