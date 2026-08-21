class_name BurstField
extends RefCounted

## Board-local particle sprays: the drop burst, the bucket-upgrade ripple, and
## the edge splash. All three share one pooled MultiMesh and one update loop —
## they differ only in how they aim their particles.
##
## Motion is analytic (lerp + eased alpha), never physics — coin volume must not
## cost anything here. Positions are PlinkoBoard-local.

const CAPACITY := 64

var _pool := MultiMeshPool.new()
var _live: Array[Dictionary] = []


func create(parent: Node, material: Material) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE  # scaled per-instance via the transform basis
	_pool.create(parent, quad, material, CAPACITY)


func is_created() -> bool:
	return _pool.instance != null


func is_idle() -> bool:
	return _live.is_empty()


## Radial burst from `origin`. Used when a coin is dropped.
func spawn_burst(origin: Vector3, color: Color, t: VisualTheme) -> void:
	for i in t.drop_burst_particle_count:
		var distance: float = t.drop_burst_spread * randf_range(0.5, 1.0)
		_emit(
			origin,
			origin + _scatter(distance),
			0.0,
			t.drop_burst_duration * randf_range(0.7, 1.0),
			t.drop_burst_particle_size,
			color,
		)


## Stream travelling from `from` to `to`, arriving in `travel_time`. Particles
## are staggered and scattered perpendicular to the path so they read as a trail.
func spawn_ripple(from: Vector3, to: Vector3, travel_time: float, color: Color, t: VisualTheme) -> void:
	var count := 3
	var dir: Vector3 = (to - from).normalized()
	var perp := Vector3(-dir.y, dir.x, 0.0)
	for i in count:
		var stagger: float = float(i) / float(count) * travel_time * 0.3
		_emit(
			from,
			to + perp * randf_range(-0.15, 0.15),
			-stagger,
			travel_time,
			t.drop_burst_particle_size * 0.8,
			color,
		)


## Firework at an edge bucket.
func spawn_edge_splash(origin: Vector3, delay: float, color: Color, t: VisualTheme) -> void:
	var spread: float = t.drop_burst_spread * 1.5
	for i in 10:
		_emit(
			origin,
			origin + _scatter(spread * randf_range(0.5, 1.0)),
			-delay - randf_range(0.0, 0.05),
			0.4 * randf_range(0.8, 1.0),
			t.drop_burst_particle_size,
			color,
		)


## Advances every live particle. Negative `elapsed` is a not-yet-started delay.
func update(delta: float) -> void:
	var i := 0
	while i < _live.size():
		var p: Dictionary = _live[i]
		p.elapsed += delta

		if p.elapsed < 0.0:
			_pool.multimesh().set_instance_transform(p.idx, MultiMeshPool.hidden())
			i += 1
			continue

		var k: float = clampf(p.elapsed / p.duration, 0.0, 1.0)
		if k >= 1.0:
			_pool.release(p.idx)
			_live.remove_at(i)
			continue

		var eased: float = 1.0 - (1.0 - k) * (1.0 - k)  # ease-out quad
		var color: Color = p.color
		color.a = 1.0 - k * k  # ease-in quad fade
		var size: float = p.size
		_pool.set_slot(
			p.idx,
			Transform3D(Basis.IDENTITY.scaled(Vector3(size, size, size)), (p.start as Vector3).lerp(p.target, eased)),
			color,
		)
		i += 1


## Random offset in the XY plane at `distance`.
func _scatter(distance: float) -> Vector3:
	var angle: float = randf() * TAU
	return Vector3(cos(angle) * distance, sin(angle) * distance, 0.0)


## Claims a slot. Silently drops the particle when the pool is exhausted — a
## missing particle is invisible, a grown pool would cost a frame hitch.
func _emit(start: Vector3, target: Vector3, elapsed: float, duration: float, size: float, color: Color) -> void:
	var idx := _pool.acquire()
	if idx < 0:
		return
	_live.append({
		"idx": idx,
		"start": start,
		"target": target,
		"elapsed": elapsed,
		"duration": duration,
		"size": size,
		"color": color,
	})
