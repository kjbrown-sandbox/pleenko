class_name CoinPool
extends RefCounted

## Renders every in-flight coin on one board as instances of a single MultiMesh.
##
## A Coin node still owns its own position and bounce logic; this only mirrors
## that state into a mesh instance each frame, so coin count costs draw calls of
## one. Coins that need to be drawn individually (the prestige coin, which gets
## its own animation) are ejected back to their own mesh.

const INITIAL_CAPACITY := 64

var _pool := MultiMeshPool.new()
var _slots: Dictionary = {}  # Coin -> int
## Rotation applied to every coin mesh, from the theme's coin shape.
var mesh_basis: Basis = Basis.IDENTITY


func create(parent: Node, mesh: Mesh, material: Material) -> void:
	_pool.create(parent, mesh, material, INITIAL_CAPACITY)


func is_created() -> bool:
	return _pool.instance != null


func is_idle() -> bool:
	return _slots.is_empty()


func coins() -> Array:
	return _slots.keys()


func set_visible(vis: bool) -> void:
	if _pool.instance:
		_pool.instance.visible = vis


## Hands the coin a slot and hides its own mesh. Grows the pool if full.
func acquire(coin: Coin) -> void:
	var idx := _pool.acquire(true)
	_slots[coin] = idx
	coin.multimesh_index = idx
	coin.set_mesh_visible(false)
	_pool.multimesh().set_instance_color(idx, coin.cached_color)


func release(coin: Coin) -> void:
	if coin.multimesh_index < 0:
		return
	_pool.release(coin.multimesh_index)
	_slots.erase(coin)
	coin.multimesh_index = -1


## Returns the coin to drawing its own mesh — used by the prestige handover.
func eject(coin: Coin) -> void:
	release(coin)
	coin.set_mesh_visible(true)


## Mirrors every live coin's transform into its slot, applying the impact squash
## Coin flags on peg contact.
func update(delta: float, t: VisualTheme) -> void:
	var impact_duration: float = t.coin_impact_squash_duration
	var impact_peak: Vector3 = t.coin_impact_squash_scale
	var coin_radius: float = t.coin_radius

	for coin: Coin in _slots:
		if not is_instance_valid(coin):
			continue
		var basis: Basis = mesh_basis
		var pos: Vector3 = coin.position

		if coin.impact_squash_remaining > 0.0 and impact_duration > 0.0:
			coin.impact_squash_remaining = maxf(0.0, coin.impact_squash_remaining - delta)
			var k: float = coin.impact_squash_remaining / impact_duration  # 1=peak, 0=done
			var squash: Vector3 = Vector3.ONE.lerp(impact_peak, k)
			# Left-multiply so the squash flattens along world Y no matter how
			# mesh_basis rotates the coin.
			basis = Basis.IDENTITY.scaled(squash) * mesh_basis
			# Sink by the lost radius so the coin stays planted on the peg.
			pos.y -= coin_radius * (1.0 - squash.y)

		_pool.set_slot(_slots[coin], Transform3D(basis, pos), coin.cached_color)
