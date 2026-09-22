class_name EarringBoard
extends CoinSurface

## One earring: a small triangular lattice hanging beneath one edge bucket of a
## PlinkoBoard. Coins that reach that edge bucket fall through into here and are
## paid out down here instead.
##
## Deliberately NOT a PlinkoBoard: no drop queue, no autodroppers, no upgrade
## rows, no deflectors, no hazards, no challenge bucket marking. It implements
## the CoinSurface contract and nothing else, which is what keeps the earring
## surface small enough to reason about.
##
## Coins handed off to an earring stay parented to the PARENT PlinkoBoard — the
## board's CoinPool mirrors `coin.position` (parent-local) into a MultiMesh, so
## reparenting would render every coin in the wrong place. cell_to_world
## therefore returns parent-local coordinates, via `transform *` so a
## non-identity basis or an intermediate wrapper node still works.
##
## Invariant, mirroring PegField's: a bare `EarringBoard.new()` (unit tests)
## never enters the tree, so `peg_field` / `buckets_container` are null. Every
## call site guards.

const BucketScene: PackedScene = preload("res://entities/bucket/bucket.tscn")

## Y of a coin resting on a peg row. Mirrors PlinkoBoard.COIN_ROW_Y_OFFSET so
## the coin keeps the same peg-to-coin gap across the handoff.
const COIN_ROW_Y_OFFSET := 0.2

## Label on an earring's own (non-transporter) bucket. Earring buckets are all
## worth EARRING_BUCKET_VALUE for now — deliberately unbalanced first pass.
const EARRING_BUCKET_VALUE := 1

@onready var peg_field: PegField = $Pegs
@onready var buckets_container: Node3D = $Buckets

## Which edge bucket this earring hangs from (EarringGeometry.SIDE_*). Decides
## which end of the bottom row faces the board centre.
var side: int = EarringGeometry.SIDE_LEFT

var vertical_spacing: float = 0.0

## Bucket lookup by column. Parallel to the bucket row, but the transporter slot
## holds a bucket this earring does NOT own (see set_transporter), so this is
## the authority rather than buckets_container's child list.
var _buckets: Array[Bucket] = []

## Column whose bucket is the shared transporter, or -1 when this earring has no
## transporter (it hasn't reached the centre yet).
var _transporter_col: int = -1
var _transporter_bucket: Bucket


## Builds (or rebuilds) this earring. Called DOWN by PlinkoBoard after its own
## build_board(). `space` comes from the parent so both lattices stay in step.
func setup(rows: int, earring_side: int, space: float, parent_board_type: Enums.BoardType) -> void:
	num_rows = maxi(rows, 1)
	side = earring_side
	space_between_pegs = space
	vertical_spacing = Lattice.vertical_spacing(space)
	board_type = parent_board_type
	_build()


## Points this earring's inner-corner bucket at a bucket owned by someone else
## (PlinkoBoard's shared transporter). Must be called BEFORE setup(): the build
## skips creating its own bucket at that column.
func set_transporter(col: int, bucket: Bucket) -> void:
	_transporter_col = col
	_transporter_bucket = bucket


func _build() -> void:
	if not peg_field or not buckets_container:
		return  # bare instance (unit tests) — geometry only, no nodes

	var t: VisualTheme = ThemeProvider.theme
	peg_field.build(_compute_peg_positions(), t)

	for child in buckets_container.get_children():
		buckets_container.remove_child(child)
		child.queue_free()

	var num_buckets: int = EarringGeometry.buckets_for_rows(num_rows)
	buckets_container.position = Vector3(
		EarringGeometry.edge_bucket_x(num_buckets, space_between_pegs),
		-vertical_spacing * num_rows + (vertical_spacing / 3.0),
		0)

	_buckets.clear()
	_buckets.resize(num_buckets)
	for i in num_buckets:
		if i == _transporter_col:
			# The transporter is one shared node owned by PlinkoBoard and sitting
			# at board-local x = 0. Both earrings point their inner corner at it;
			# neither builds a bucket of its own there.
			_buckets[i] = _transporter_bucket
			continue
		var bucket: Bucket = BucketScene.instantiate()
		bucket.is_prestige_bucket = false
		buckets_container.add_child(bucket)
		bucket.setup(TierRegistry.primary_currency(board_type),
			Vector3(i * space_between_pegs, 0, 0), EARRING_BUCKET_VALUE)
		_buckets[i] = bucket


func _compute_peg_positions() -> PackedVector3Array:
	@warning_ignore("integer_division")
	var total: int = num_rows * (num_rows + 1) / 2
	var out := PackedVector3Array()
	out.resize(total)
	var idx := 0
	for row in range(num_rows):
		var y: float = -vertical_spacing * row
		for col in range(row + 1):
			out[idx] = Vector3(Lattice.x_for(row, col, space_between_pegs), y, 0)
			idx += 1
	return out


## Parent-local position of the top peg — where a handed-off coin is dropped in.
func get_top_peg_local() -> Vector3:
	return cell_to_world(0, 0)


## The bucket this coin is about to land in, resolved from the coin's own
## lattice cursor.
##
## Deliberately NOT a nearest-x lookup: the transporter sits at board-local
## x = 0, which on a 9-bucket main board is exactly the centre bucket's x, so an
## x-keyed match would collide with the main board.
func bucket_for_coin(coin: Coin) -> Bucket:
	var cell: Vector2i = coin.get_lattice_cell()
	return get_bucket(predicted_bucket_index(cell.x, cell.y))


## True when `bucket` is this earring's transporter (rather than one of its own
## paying buckets).
func is_transporter(bucket: Bucket) -> bool:
	return _transporter_col >= 0 and bucket != null and bucket == _transporter_bucket


## Local-space bounding rect of this earring's pegs + buckets. PlinkoBoard
## offsets it by `position` to fold it into its own camera-fit bounds.
func get_local_bounds() -> Rect2:
	var half_width: float = (num_rows / 2.0) * space_between_pegs + space_between_pegs * 0.5
	var top: float = COIN_ROW_Y_OFFSET + 0.5
	var bottom: float = -vertical_spacing * num_rows + (vertical_spacing / 3.0) - 0.5
	return Rect2(-half_width, bottom, half_width * 2.0, top - bottom)


# ── CoinSurface contract ──────────────────────────────────────────────────────

## Parent-local (NOT earring-local): handed-off coins stay children of the
## PlinkoBoard. `transform *` rather than `position + ...` so a non-identity
## basis or an intermediate wrapper node survives.
func cell_to_world(row: int, col: int) -> Vector3:
	return transform * Lattice.cell_to_world(row, col, space_between_pegs,
		vertical_spacing, COIN_ROW_Y_OFFSET)


func next_lattice_cell(row: int, col: int, direction: int) -> Vector2i:
	return Lattice.next_cell(row, col, direction)


func is_terminal_cell(row: int, _col: int) -> bool:
	return row >= num_rows


func predicted_bucket_index(_row: int, col: int) -> int:
	return col


## Plain 50/50 — earrings carry no deflectors by design (keeps the new surface
## small; deflector slots stay a main-board concern).
func resolve_bounce_direction(_row: int, _col: int, roll: float) -> int:
	return DeflectorModel.random_dir(roll)


## Earrings are excluded from bombs and forbidden-bucket hazards, so no cell of
## theirs is ever voided.
func is_lattice_cell_voided(_row: int, _col: int) -> bool:
	return false


func get_bucket(index: int) -> Bucket:
	if index < 0 or index >= _buckets.size():
		return null
	return _buckets[index]


## Earrings have their own PegField for rendering but no contact VFX — the flash
## / halo / sparkle path stays main-board-only.
func flash_nearest_peg(_coin_pos: Vector3, _currency_type: int) -> void:
	pass


func notify_deflector_resolved(_row: int, _col: int, _direction: int) -> void:
	pass


## Earrings run plain 50/50 bounces — no deflectors, no hazards, no lucky pegs.
## The wander only ever picks pegs on the main board's lattice, so a coin that
## has dropped through a gateway is past the point where one could apply.
func try_lucky_split(_origin: Coin, _row: int, _col: int) -> int:
	return 0


## Coins pooled by the parent PlinkoBoard are ejected there; an earring owns no
## pool of its own.
func eject_coin_from_multimesh(_coin: Coin) -> void:
	pass
