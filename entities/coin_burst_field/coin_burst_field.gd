class_name CoinBurstField
extends MultiMeshInstance3D

## Pooled, downward "falling spray" particle burst played when a coin lands in
## a bucket. Self-contained: owns one MultiMesh, a fixed slot pool, its own
## per-second rate limit, and the per-frame animation. The parent (PlinkoBoard)
## just calls spawn(world_pos, color) — signals up, calls down.
##
## Performance: zero per-spawn allocation, one draw call, O(active) per-frame
## update. Cost is bounded at ANY coin volume by the fixed pool
## (coin_burst_pool_size) plus the per-second emission cap
## (coin_burst_max_per_second) — exactly the proven drop_burst mechanism.
##
## Motion is analytic (no physics engine, per the project's Core Physics rule):
## each particle gets a downward-cone velocity and falls under constant gravity.
##
## The pure helpers (seed_particle / position_at / alpha_at) are static and
## RNG-injectable so they unit-test headlessly without a MultiMesh or scene.

# Speed/lifetime jitter so particles in one burst don't move in lockstep.
const _SPEED_JITTER_MIN := 0.7   # fraction of coin_burst_speed (downward)
const _DURATION_JITTER_MIN := 0.8  # fraction of coin_burst_duration

# Reused for any pooled slot that isn't currently a live particle.
const _HIDDEN_XFORM := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3(0, -9999, 0))

# Timestamps (seconds) of recent bursts; only the last ~1s is kept. Used to
# rate-limit emissions to coin_burst_max_per_second.
var _emit_times: Array[float] = []

# Free-index stack into the MultiMesh; pop on spawn, append on expiry.
var _free_indices: Array[int] = []
# One dict per live particle: { idx, start, vel, gravity, elapsed, duration, size, color }.
var _active: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var pool_size: int = maxi(1, t.coin_burst_pool_size)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE  # scaled per-instance via the transform basis

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = pool_size
	for i in pool_size:
		mm.set_instance_transform(i, _HIDDEN_XFORM)
	multimesh = mm

	# Same trivial unshaded/no-depth-write shader the drop burst uses — it just
	# pipes per-instance COLOR straight to ALBEDO/ALPHA. No need for a second copy.
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://entities/plinko_board/drop_burst_multimesh.gdshader")
	material_override = mat

	for i in range(pool_size - 1, -1, -1):
		_free_indices.append(i)


## Bursts a downward spray of `color` particles at the given WORLD position.
## No-op when disabled, rate-limited, or the pool is exhausted (the caller's
## coin still scores and frees normally either way).
func spawn(world_pos: Vector3, color: Color) -> void:
	var t: VisualTheme = ThemeProvider.theme
	if not t.coin_burst_enabled:
		return

	var now: float = Time.get_ticks_msec() / 1000.0
	while not _emit_times.is_empty() and now - _emit_times[0] >= 1.0:
		_emit_times.remove_at(0)
	if _emit_times.size() >= t.coin_burst_max_per_second:
		return
	_emit_times.append(now)

	var local_pos: Vector3 = to_local(world_pos)
	var count: int = t.coin_burst_particle_count
	for i in count:
		var idx: int = _acquire_slot()
		if idx < 0:
			return  # pool saturated — drop the rest of this burst, no error
		var seed: Dictionary = seed_particle(_rng, t.coin_burst_speed, t.coin_burst_spread, t.coin_burst_duration)
		_active.append({
			"idx": idx,
			"start": local_pos,
			"vel": seed["vel"],
			"gravity": t.coin_burst_gravity,
			"elapsed": 0.0,
			"duration": seed["duration"],
			"size": t.coin_burst_particle_size,
			"color": color,
		})


func _process(delta: float) -> void:
	if _active.is_empty():
		return
	# Advance in real time: process `delta` is already scaled by
	# Engine.time_scale, so divide it back out (the prestige slow-mo pattern
	# used by prestige_animator / audio_manager). Keeps bursts raining at
	# normal speed even while the board is in slow-mo.
	var d: float = delta / maxf(Engine.time_scale, 0.0001)
	var mm := multimesh
	var i: int = 0
	while i < _active.size():
		var p: Dictionary = _active[i]
		p.elapsed += d
		if p.elapsed >= p.duration:
			mm.set_instance_transform(p.idx, _HIDDEN_XFORM)
			_release_slot(p.idx)
			_active.remove_at(i)
			continue
		var pos: Vector3 = position_at(p.start, p.vel, p.gravity, p.elapsed)
		var s: float = p.size
		mm.set_instance_transform(p.idx, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), pos))
		var c: Color = p.color
		c.a = alpha_at(p.elapsed, p.duration)
		mm.set_instance_color(p.idx, c)
		i += 1


# ── Slot pool (free-index stack; LIFO, graceful exhaustion) ──────────────────

## Pops a free MultiMesh slot, or -1 when the pool is exhausted.
func _acquire_slot() -> int:
	if _free_indices.is_empty():
		return -1
	return _free_indices.pop_back()


## Returns a slot to the pool so a future particle can reuse it.
func _release_slot(idx: int) -> void:
	_free_indices.append(idx)


# ── Pure helpers (static, RNG-injectable — headlessly unit-testable) ──────────

## Builds one particle's initial velocity + lifetime. The velocity is a
## DOWNWARD cone: vertical component is always negative (falls), horizontal is
## a small ± jitter. This is the "follows the coin's momentum, sprays down,
## not a radial firework" behavior — the y-component is never positive.
static func seed_particle(rng: RandomNumberGenerator, speed: float, spread: float, duration: float) -> Dictionary:
	var vx: float = rng.randf_range(-spread, spread)
	var vy: float = -speed * rng.randf_range(_SPEED_JITTER_MIN, 1.0)
	var dur: float = duration * rng.randf_range(_DURATION_JITTER_MIN, 1.0)
	return {"vel": Vector3(vx, vy, 0.0), "duration": dur}


## Analytic kinematics: pos(t) = start + vel*t + ½*a*t², with a = (0,-g,0).
## Gravity acts in -Y only, so particles accelerate downward over their life.
static func position_at(start: Vector3, vel: Vector3, gravity: float, t: float) -> Vector3:
	return start + vel * t + Vector3(0.0, -0.5 * gravity * t * t, 0.0)


## Quadratic fade: 1.0 at spawn → 0.0 at end of life, monotonically decreasing
## (same curve the drop burst uses).
static func alpha_at(elapsed: float, duration: float) -> float:
	var k: float = clampf(elapsed / duration, 0.0, 1.0)
	return 1.0 - k * k
