class_name SpaceBoard
extends Node3D

## The endgame board. A fixed 10-row / 55-peg lattice with 11 buckets in a
## symmetric currency rainbow, parked high above the six colour boards.
##
## It is NOT a PlinkoBoard: it has no currency, no upgrades, no drop queue, no
## rewards, and BoardManager does not know it exists. Its only inputs are coins
## transported up from the colour boards (see PlinkoBoard.coin_transported and
## Main._connect_space_board) plus the editor-only dev hotkeys in Main.
##
## Landing a coin in the bucket that matches the coin's own colour activates
## that bucket permanently. All 11 activated = the player wins.
##
## HOW A COIN GETS HERE: from GOLD's transporter, and only gold's
## (PlinkoBoard.SPACE_TRANSPORT_BOARD). Every board can grow earrings and build
## the meeting bucket, but on any other tier it is an inert dead end.
##
## A non-gold colour arrives by riding the DUD CHUTE down tier by tier — each hop
## keeps the coin's own currency — until it lands in gold's transporter still
## carrying its colour. That is why green can be activated at all despite never
## growing earrings (TierRegistry.cap_raise_currency returns -1 for the last
## tier, so green never reaches the hard cap). It needs five chute hops at 2%
## each: vanishingly rare, but reachable, and NOT a gap to paper over.
##
## So: do NOT "fix" green by special-casing it or shrinking the bucket layout.
## The route exists; it is meant to be the hardest thing in the game.
##
## Bucket layout (fixed, never rebuilt — gold dead centre, everything else
## mirrored, green at the edges):
##   idx  0     1    2      3   4      5    6      7   8      9    10
##       GREEN BLUE VIOLET RED ORANGE GOLD ORANGE RED VIOLET BLUE GREEN
##
## Ownership: this node owns the peg MultiMesh, the 11 Buckets, the 11
## underlay circles, every in-flight coin, and the activation cinematic. It
## emits `bucket_activated` / `won` UP; Main persists and shows the overlay.
## It never calls SaveManager (Main injects the save, see SaveManager.setup).
##
## Coin motion is analytic (per Core Physics: no physics engine, and no Tweens
## either — a Tween created on `self` outlives a freed coin and throws). Every
## coin is a plain MeshInstance3D advanced from `_process`.

const BucketScene := preload("res://entities/bucket/bucket.tscn")

## 10 peg rows -> 11 buckets for the symmetric rainbow.
const NUM_ROWS := 10

## Y of a coin resting on a peg row — mirrors PlinkoBoard.COIN_ROW_Y_OFFSET.
const COIN_ROW_Y_OFFSET := 0.2

## The fixed bucket layout. A script-level const (NOT authored in the .tscn) so
## a bare `SpaceBoard.new()` can read it in a headless test.
const BUCKET_COLORS: Array[Enums.CurrencyType] = [
	Enums.CurrencyType.GREEN_COIN,
	Enums.CurrencyType.BLUE_COIN,
	Enums.CurrencyType.VIOLET_COIN,
	Enums.CurrencyType.RED_COIN,
	Enums.CurrencyType.ORANGE_COIN,
	Enums.CurrencyType.GOLD_COIN,
	Enums.CurrencyType.ORANGE_COIN,
	Enums.CurrencyType.RED_COIN,
	Enums.CurrencyType.VIOLET_COIN,
	Enums.CurrencyType.BLUE_COIN,
	Enums.CurrencyType.GREEN_COIN,
]

## How far the arrival arc bows above the straight line from the transporter to
## the apex peg, as a fraction of that distance.
const ARRIVAL_ARC_BOW_FRACTION := 0.12

## Per-coin flight phases, advanced in _process.
enum CoinPhase { ARC, FALL }

## Activation cinematic phases. OFF is the resting state.
enum Cinematic { OFF, ZOOM_IN, SINK, FILL, ZOOM_OUT }

signal bucket_activated(bucket_index: int)
signal won()

@onready var pegs_container: Node3D = $Pegs
@onready var buckets_container: Node3D = $Buckets
@onready var coins_container: Node3D = $Coins

## Set by Main before connect/receive. Mirrors PeekAnimator's Callable seams:
## production wires them to Main, tests inject stubs.
var apply_input_lock_fn: Callable
## Fires the screen-space shockwave. Injectable so headless tests can observe
## the burst without a viewport.
var shockwave_fn: Callable
## "Is the player actually looking at this board?" Set by Main to Main's
## is_viewing_space. Coins keep arriving while the player is down on a colour
## board, and a cinematic then would steal the shared camera, slow the whole
## game and lock input for a shot nobody can see — so an off-camera arrival
## commits silently instead. Unset (tests) means "watching".
var should_play_cinematic_fn: Callable

var space_between_pegs: float
var vertical_spacing: float

var _rng := RandomNumberGenerator.new()
var _camera: Camera3D
var _coin_mesh: Mesh
var _coin_basis: Basis = Basis.IDENTITY  ## Mirrors PlinkoBoard's per-instance rotation
var _coin_material_cache: Dictionary = {}  # CurrencyType -> StandardMaterial3D
var _buckets: Array[Bucket] = []
var _underlay_fills: Array[MeshInstance3D] = []

# ── Bookkeeping (deliberately UNGUARDED by the scene tree so it is unit-testable) ──
var _activated: Array[bool] = []
var _won: bool = false
var _win_pending: bool = false

# ── In-flight coins ──────────────────────────────────────────────────
## One entry per flying coin: {node, currency, phase, elapsed, duration,
## row, col, from, to}. Positions are board-LOCAL.
var _coins: Array[Dictionary] = []
## Coins that have landed and are waiting for the cinematic to free up.
## Concurrent transports from six boards must never drop an activation.
var _landing_queue: Array[Dictionary] = []
## True while _drain_landings is resolving one landing. It holds the `won`
## signal back so the overlay never covers the activation cinematic that lit the
## eleventh bucket — the win flushes from the cinematic teardown instead.
var _draining: bool = false

# ── Activation cinematic ─────────────────────────────────────────────
var _cinematic: Cinematic = Cinematic.OFF
var _cinematic_elapsed: float = 0.0
var _cinematic_coin: MeshInstance3D
var _cinematic_bucket_index: int = -1
var _cinematic_sink_from: Vector3 = Vector3.ZERO
var _cinematic_sink_to: Vector3 = Vector3.ZERO
var _cam_start_pos: Vector3 = Vector3.ZERO
var _cam_start_size: float = 0.0
var _cam_rest_pos: Vector3 = Vector3.ZERO
var _cam_rest_size: float = 0.0
var _input_locked: bool = false
## Set in _exit_tree so teardown skips work that only makes sense in-tree.
var _exiting := false
var _torn_down: bool = true

# ── Contact shake (mirrors PrestigeVFX.start_shake) ──────────────────
var _shake_active: bool = false
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_elapsed: float = 0.0


func _init() -> void:
	# Runs on `.new()` as well as on scene instantiation, so a bare board (no
	# _ready, no children) still has valid activation state for unit tests.
	_activated.resize(BUCKET_COLORS.size())
	_activated.fill(false)
	_rng.randomize()


func _ready() -> void:
	# PROCESS_MODE_ALWAYS so the cinematic keeps ticking at wall-clock speed
	# while it holds Engine.time_scale down (CapRaiseRevealAnimator precedent).
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

	var t: VisualTheme = ThemeProvider.theme
	space_between_pegs = t.space_between_pegs
	vertical_spacing = Lattice.vertical_spacing(space_between_pegs)

	_build_pegs(t)
	_build_buckets(t)
	_build_underlays(t)
	_coin_mesh = t.make_coin_mesh()
	# Cylinder coins ship axis-aligned to +Y — flat on their side from the
	# camera's POV. Rotate 90 degrees on X so the circular face faces us.
	# Mirrors PlinkoBoard.build_board.
	if t.coin_shape == VisualTheme.CoinShape.CYLINDER:
		_coin_basis = Basis.from_euler(Vector3(PI / 2, 0, 0))

	_refresh_bucket_visuals()


func _exit_tree() -> void:
	_exiting = true
	_teardown_cinematic()


## Called DOWN by Main once the camera exists. Null-safe: without it the board
## still works, it just cannot zoom during the activation cinematic.
func setup(camera: Camera3D) -> void:
	_camera = camera


# ── Pure logic (no scene tree — the unit-testable core) ───────────────

## True when a coin of `currency` belongs in bucket `bucket_index`.
static func matches(bucket_index: int, currency: Enums.CurrencyType) -> bool:
	if bucket_index < 0 or bucket_index >= BUCKET_COLORS.size():
		return false
	return BUCKET_COLORS[bucket_index] == currency


## Every bucket lit.
static func is_won(activated: Array[bool]) -> bool:
	if activated.size() != BUCKET_COLORS.size():
		return false
	for a in activated:
		if not a:
			return false
	return true


## One unbiased row step: 1 = RIGHT (col + 1), 0 = LEFT (col unchanged). The
## single source of the odds — `_advance_coin` takes exactly this flip per row.
static func step_right(rng: RandomNumberGenerator) -> int:
	return 1 if rng.randf() < 0.5 else 0


## Pure model of a full `rows`-row fall: the landing bucket index, in [0, rows].
## Composed from step_right, so asserting this is asserting the live odds.
## Locked decision 8 — the lattice is never biased; the dev hotkeys are how a
## specific bucket gets activated for filming.
static func fall_path(rng: RandomNumberGenerator, rows: int) -> int:
	var col := 0
	for _i in rows:
		col += step_right(rng)
	return col


## Analytic arrival arc: the lob from a colour board's transporter up to the
## space board's apex peg. Horizontal eases IN (t^2) so the coin leaves the
## transporter almost straight up before swinging across; vertical eases OUT so
## it gains its height early; the sine bow lifts the whole path off the
## straight line so it reads as a lob rather than a ramp.
static func arc_position_at(from: Vector3, apex: Vector3, t: float) -> Vector3:
	var tt: float = clampf(t, 0.0, 1.0)
	var ex: float = tt * tt
	var ey: float = 1.0 - (1.0 - tt) * (1.0 - tt)
	var bow: float = from.distance_to(apex) * ARRIVAL_ARC_BOW_FRACTION * sin(PI * tt)
	return Vector3(
		lerpf(from.x, apex.x, ex),
		lerpf(from.y, apex.y, ey) + bow,
		lerpf(from.z, apex.z, ex))


## Analytic single-row hop: straight lerp plus a parabolic pop of `height`
## (4*h*t*(1-t) peaks at h halfway). Same shape as a ball bouncing off a peg.
static func hop_position_at(from: Vector3, to: Vector3, t: float, height: float) -> Vector3:
	var tt: float = clampf(t, 0.0, 1.0)
	var p: Vector3 = from.lerp(to, tt)
	p.y += height * 4.0 * tt * (1.0 - tt)
	return p


func is_activated(bucket_index: int) -> bool:
	if bucket_index < 0 or bucket_index >= _activated.size():
		return false
	return _activated[bucket_index]


func get_activated() -> Array[bool]:
	return _activated.duplicate()


func has_won() -> bool:
	return _won


## THE state machine. Returns true only when this coin's colour matches the
## bucket AND the bucket was not already lit — i.e. only when something
## actually changed. Both the cinematic and the save hang off the return value.
func try_activate(bucket_index: int, currency: Enums.CurrencyType) -> bool:
	if not matches(bucket_index, currency):
		return false
	if is_activated(bucket_index):
		return false
	_activated[bucket_index] = true
	_mark_bucket_activated(bucket_index)
	bucket_activated.emit(bucket_index)
	if is_won(_activated) and not _won:
		_won = true
		_win_pending = true
	_flush_win()
	return true


## Emits `won` once the cinematic is out of the way, so the overlay never
## covers the money shot. Idempotent — the pending flag is consumed.
func _flush_win() -> void:
	if not _win_pending or _cinematic != Cinematic.OFF or _draining:
		return
	_win_pending = false
	won.emit()


# ── Save ─────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	return {
		"activated": _activated.duplicate(),
		"won": _won,
	}


func deserialize(data: Dictionary) -> void:
	var saved: Array = data.get("activated", [])
	for i in _activated.size():
		_activated[i] = i < saved.size() and bool(saved[i])
	_won = bool(data.get("won", false))
	_win_pending = false
	_refresh_bucket_visuals()


# ── Coin intake ──────────────────────────────────────────────────────

## Merge-safe wiring for the transporter seam. Called by Main once per board.
##
## Deliberately the STRING-based signal API, and `board` is deliberately typed
## `Node`. A caller holding a statically typed `PlinkoBoard` cannot write
## `board.coin_transported.connect(...)` until the earrings branch lands:
## GDScript resolves member access on a typed value at PARSE time, so main.gd
## would fail to parse and the whole scene would die — and `has_signal()`, a
## runtime check, cannot rescue a parse error. This form compiles and silently
## no-ops before earrings lands, and wires itself up after, with no edit needed
## on either side.
##
## Idempotent. Returns true only when it actually made a new connection.
static func connect_transporter(board: Node, handler: Callable) -> bool:
	if not is_instance_valid(board):
		return false
	if not board.has_signal("coin_transported"):
		return false
	if board.is_connected("coin_transported", handler):
		return false
	board.connect("coin_transported", handler)
	return true


## The seam with the earrings feature. A coin of `currency_type` launches from
## `from_world_pos` (a transporter bucket on a colour board), arcs up to the
## apex peg, then falls the 10-row lattice normally.
func receive_coin(currency_type: Enums.CurrencyType, from_world_pos: Vector3) -> void:
	if not is_inside_tree() or not is_instance_valid(coins_container):
		return
	var coin := _make_coin(currency_type)
	if not coin:
		return
	var start: Vector3 = to_local(from_world_pos)
	var apex: Vector3 = _cell_local(0, 0)
	coin.transform = Transform3D(_coin_basis, start)
	coins_container.add_child(coin)
	_coins.append({
		"node": coin,
		"currency": currency_type,
		"phase": CoinPhase.ARC,
		"elapsed": 0.0,
		"duration": ThemeProvider.theme.space_arrival_arc_duration,
		"row": 0,
		"col": 0,
		"from": start,
		"to": apex,
	})
	_update_processing()


func _make_coin(currency_type: Enums.CurrencyType) -> MeshInstance3D:
	if not _coin_mesh:
		return null
	var coin := MeshInstance3D.new()
	coin.mesh = _coin_mesh
	coin.material_override = _coin_material_for(currency_type)
	return coin


func _coin_material_for(currency_type: Enums.CurrencyType) -> StandardMaterial3D:
	if _coin_material_cache.has(currency_type):
		return _coin_material_cache[currency_type]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ThemeProvider.theme.get_coin_color(currency_type)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_coin_material_cache[currency_type] = mat
	return mat


func _cell_local(row: int, col: int) -> Vector3:
	return Lattice.cell_to_world(row, col, space_between_pegs, vertical_spacing, COIN_ROW_Y_OFFSET)


## Board-local resting position of a coin sitting on top of bucket `index`.
func _bucket_top_local(index: int) -> Vector3:
	if index < 0 or index >= _buckets.size() or not is_instance_valid(buckets_container):
		return Vector3.ZERO
	var b: Bucket = _buckets[index]
	var t: VisualTheme = ThemeProvider.theme
	return buckets_container.position + Vector3(b.position.x,
		b.position.y + t.bucket_height / 2.0 + t.coin_radius, b.position.z)


## Board-local centre of the empty circle under bucket `index`.
func _underlay_local(index: int) -> Vector3:
	if index < 0 or index >= _buckets.size() or not is_instance_valid(buckets_container):
		return Vector3.ZERO
	var b: Bucket = _buckets[index]
	return buckets_container.position + b.position \
		- Vector3(0, ThemeProvider.theme.space_underlay_drop, 0)


# ── Per-frame ────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Engine.time_scale shrinks delta even under PROCESS_MODE_ALWAYS. Free-
	# flying coins keep the engine delta on purpose, so the cinematic's slow-mo
	# visibly slows the rest of the board; the cinematic clock and the camera
	# run on the recovered real delta so their tuned durations stay wall-clock.
	var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
	_advance_coins(delta)
	if _cinematic != Cinematic.OFF:
		_advance_cinematic(real_delta)
	_tick_shake(real_delta)
	_update_processing()


func _advance_coins(delta: float) -> void:
	var i := _coins.size() - 1
	while i >= 0:
		var c: Dictionary = _coins[i]
		var node: MeshInstance3D = c["node"]
		if not is_instance_valid(node):
			_coins.remove_at(i)
			i -= 1
			continue
		c["elapsed"] = float(c["elapsed"]) + delta
		var duration: float = maxf(float(c["duration"]), 0.0001)
		var t: float = clampf(float(c["elapsed"]) / duration, 0.0, 1.0)
		if c["phase"] == CoinPhase.ARC:
			node.position = arc_position_at(c["from"], c["to"], t)
		else:
			node.position = hop_position_at(c["from"], c["to"], t,
				vertical_spacing * ThemeProvider.theme.space_bounce_height_mult)
		if t >= 1.0:
			if _begin_next_step(c):
				_coins.remove_at(i)
		i -= 1


## A leg of the flight just finished, so the coin now sits on cell
## (c.row, c.col). Starts the next hop, or lands it. Returns true when the coin
## has left `_coins` (the landing queue owns it now, or it was freed).
##
## The arrival arc counts as the leg that delivers the coin to the apex peg
## (0, 0); from there it is an ordinary 10-row fall, one unbiased flip per row.
func _begin_next_step(c: Dictionary) -> bool:
	var row: int = int(c["row"])
	var col: int = int(c["col"])
	if row >= NUM_ROWS:
		_enqueue_landing(c["node"], c["currency"], col)
		return true
	c["phase"] = CoinPhase.FALL
	var direction: int = Enums.Direction.RIGHT if step_right(_rng) == 1 else Enums.Direction.LEFT
	var next: Vector2i = Lattice.next_cell(row, col, direction)
	c["from"] = _cell_local(row, col)
	c["to"] = _cell_local(next.x, next.y)
	c["row"] = next.x
	c["col"] = next.y
	c["elapsed"] = 0.0
	c["duration"] = ThemeProvider.theme.space_bounce_duration
	return false


func _update_processing() -> void:
	set_process(not _coins.is_empty() or _cinematic != Cinematic.OFF
		or not _landing_queue.is_empty() or _shake_active)


# ── Landing ──────────────────────────────────────────────────────────

## Coins land FIFO. Six boards can transport at once, and a dropped arrival is a
## lost activation, so landings queue behind the cinematic instead of racing it.
func _enqueue_landing(coin: MeshInstance3D, currency: Enums.CurrencyType, bucket_index: int) -> void:
	_landing_queue.append({"node": coin, "currency": currency, "bucket": bucket_index})
	_drain_landings()


func _drain_landings() -> void:
	while _cinematic == Cinematic.OFF and not _landing_queue.is_empty():
		var entry: Dictionary = _landing_queue.pop_front()
		var coin: MeshInstance3D = entry["node"]
		var index: int = int(entry["bucket"])
		var currency: Enums.CurrencyType = entry["currency"]
		if index >= 0 and index < _buckets.size() and is_instance_valid(coin):
			coin.position = _bucket_top_local(index)
		_draining = true
		var activated: bool = try_activate(index, currency)
		_draining = false
		if activated:
			if _should_play_cinematic():
				_begin_cinematic(coin, index)
				return
			# Off-camera arrival: commit the whole thing in one frame, with no
			# camera steal, no slow-mo and no input lock. The player finds the
			# bucket already lit and its coin already resting in the circle.
			_set_underlay_fill(index, 1.0)
			if is_instance_valid(coin):
				coin.position = _underlay_local(index)
			continue
		# Wrong colour, or a bucket a queued coin already lit: the coin has
		# nothing left to do.
		_pulse_bucket(index)
		if is_instance_valid(coin):
			coin.queue_free()
	_flush_win()
	_update_processing()


func _should_play_cinematic() -> bool:
	if should_play_cinematic_fn.is_valid():
		return bool(should_play_cinematic_fn.call())
	return true


func _pulse_bucket(index: int) -> void:
	if index >= 0 and index < _buckets.size() and is_instance_valid(_buckets[index]):
		_buckets[index].pulse()


# ── Activation cinematic ─────────────────────────────────────────────
#
# The money shot (locked decision 5): camera zooms up on the coin with a slight
# slow-motion, the coin sinks into the empty circle beneath its bucket, the
# circle fills, a coin-coloured shockwave fires as the camera pulls back out,
# and the coin stays in the circle for good with the bucket at full colour.
#
# Main holds ONE camera borrow for the whole space-viewing session
# (BoardManager.begin/end_cinematic_camera is a bool, not a counter), so this
# writes the camera directly rather than taking a nested borrow.

func _begin_cinematic(coin: MeshInstance3D, bucket_index: int) -> void:
	_cinematic = Cinematic.ZOOM_IN
	_cinematic_elapsed = 0.0
	_cinematic_coin = coin
	_cinematic_bucket_index = bucket_index
	_torn_down = false
	_cinematic_sink_from = _bucket_top_local(bucket_index)
	_cinematic_sink_to = _underlay_local(bucket_index)
	if is_instance_valid(coin):
		coin.position = _cinematic_sink_from
	if is_instance_valid(_camera):
		_cam_rest_pos = _camera.global_position
		_cam_rest_size = _camera.size
		_cam_start_pos = _cam_rest_pos
		_cam_start_size = _cam_rest_size
	_set_input_lock(true)
	Engine.time_scale = ThemeProvider.theme.space_activation_slow_mo_scale
	_update_processing()


func _advance_cinematic(real_delta: float) -> void:
	var t: VisualTheme = ThemeProvider.theme
	_cinematic_elapsed += real_delta
	match _cinematic:
		Cinematic.ZOOM_IN:
			var p: float = _phase_progress(t.space_activation_zoom_in_duration)
			_ease_camera_toward(_coin_world_pos(), t.space_activation_zoom_size, p)
			if p >= 1.0:
				_enter_phase(Cinematic.SINK)
		Cinematic.SINK:
			var p2: float = _phase_progress(t.space_activation_sink_duration)
			if is_instance_valid(_cinematic_coin):
				# Ease-in: the coin accelerates as it settles into the circle.
				_cinematic_coin.position = _cinematic_sink_from.lerp(
					_cinematic_sink_to, p2 * p2)
			_ease_camera_toward(_coin_world_pos(), t.space_activation_zoom_size, 1.0)
			if p2 >= 1.0:
				_enter_phase(Cinematic.FILL)
		Cinematic.FILL:
			var p3: float = _phase_progress(t.space_activation_fill_duration)
			_set_underlay_fill(_cinematic_bucket_index, p3)
			if p3 >= 1.0:
				# _enter_phase restores Engine.time_scale BEFORE the shockwave
				# is spawned — see the note there.
				_enter_phase(Cinematic.ZOOM_OUT)
				_fire_contact_vfx()
		Cinematic.ZOOM_OUT:
			var p4: float = _phase_progress(t.space_activation_zoom_out_duration)
			_ease_camera_back(p4)
			if p4 >= 1.0:
				_teardown_cinematic()
		Cinematic.OFF:
			pass


func _phase_progress(duration: float) -> float:
	return clampf(_cinematic_elapsed / maxf(duration, 0.0001), 0.0, 1.0)


func _enter_phase(next: Cinematic) -> void:
	_cinematic = next
	_cinematic_elapsed = 0.0
	if next == Cinematic.ZOOM_OUT:
		# Restore time_scale BEFORE the shockwave's own tween samples it —
		# VfxUtils._spawn_single_ring reads Engine.time_scale once at spawn, so
		# a ring fired during slow-mo would play back at the wrong rate.
		Engine.time_scale = 1.0
	if is_instance_valid(_camera):
		_cam_start_pos = _camera.global_position
		_cam_start_size = _camera.size


func _coin_world_pos() -> Vector3:
	if is_instance_valid(_cinematic_coin):
		return _cinematic_coin.global_position
	return global_position


func _ease_camera_toward(target: Vector3, target_size: float, progress: float) -> void:
	if not is_instance_valid(_camera):
		return
	var e: float = _smoothstep01(progress)
	_camera.global_position = _cam_start_pos.lerp(
		Vector3(target.x, target.y, _cam_start_pos.z), e)
	_camera.size = lerpf(_cam_start_size, target_size, e)


func _ease_camera_back(progress: float) -> void:
	if not is_instance_valid(_camera):
		return
	var e: float = _smoothstep01(progress)
	_camera.global_position = _cam_start_pos.lerp(_cam_rest_pos, e)
	_camera.size = lerpf(_cam_start_size, _cam_rest_size, e)


static func _smoothstep01(x: float) -> float:
	var c: float = clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## Contact: a shockwave tinted with the activated bucket's colour, plus the
## same decaying camera shake PrestigeVFX uses.
func _fire_contact_vfx() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var color: Color = ThemeProvider.theme.get_coin_color(
		BUCKET_COLORS[_cinematic_bucket_index]) if _cinematic_bucket_index >= 0 else Color.WHITE
	var opts := {
		"color": color,
		"color_strength": t.space_shockwave_color_strength,
		"duration": t.space_shockwave_duration,
	}
	if shockwave_fn.is_valid():
		shockwave_fn.call(_coin_world_pos(), opts)
	elif is_instance_valid(_camera) and is_inside_tree():
		var screen: Vector2 = _camera.unproject_position(_coin_world_pos())
		var vp: Vector2 = _camera.get_viewport().get_visible_rect().size
		VfxUtils.spawn_shockwave(self, screen / vp, opts)
	_shake_active = true
	_shake_intensity = t.prestige_shake_intensity
	_shake_duration = t.prestige_shake_duration
	_shake_elapsed = 0.0


func _tick_shake(real_delta: float) -> void:
	if not _shake_active:
		return
	if not is_instance_valid(_camera):
		_shake_active = false
		return
	_shake_elapsed += real_delta
	if _shake_elapsed >= _shake_duration:
		_shake_active = false
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		return
	# Exponential decay — the same exp(-4 * progress) curve PrestigeVFX uses.
	var decay: float = exp(-4.0 * (_shake_elapsed / maxf(_shake_duration, 0.0001)))
	var current: float = _shake_intensity * decay
	_camera.h_offset = randf_range(-current, current)
	_camera.v_offset = randf_range(-current, current)


## Idempotent full restore. Runs on normal finish, on _exit_tree, when Main
## leaves space or a prestige starts, and before a re-triggered cinematic.
## It always COMMITS the activation — never leaves a half-filled circle — so an
## interruption can't soft-lock a bucket into a half state.
func _teardown_cinematic() -> void:
	if _torn_down:
		return
	_torn_down = true
	var index: int = _cinematic_bucket_index
	_cinematic = Cinematic.OFF
	_cinematic_elapsed = 0.0
	# Only restore the scale if we still OWN it. PrestigeManager.enter_phase sets
	# Engine.time_scale and THEN emits prestige_phase_changed, which reaches us via
	# Main._on_prestige_phase_changed -> abort_cinematic(). An unconditional 1.0
	# here would overwrite prestige's slow-mo one line after it was set.
	if PrestigeManager.current_phase == PrestigeManager.PrestigePhase.NONE:
		Engine.time_scale = 1.0
	if index >= 0:
		_set_underlay_fill(index, 1.0)
		_mark_bucket_activated(index)
		if is_instance_valid(_cinematic_coin):
			# The coin stays in its circle permanently.
			_cinematic_coin.position = _underlay_local(index)
	_cinematic_coin = null
	_cinematic_bucket_index = -1
	_shake_active = false
	if is_instance_valid(_camera):
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		if _cam_rest_size > 0.0:
			_camera.global_position = _cam_rest_pos
			_camera.size = _cam_rest_size
	_set_input_lock(false)
	_flush_win()
	# Never drain while leaving the tree: _drain_landings can start a NEW cinematic
	# (setting Engine.time_scale to the slow-mo value and clearing _torn_down) on a
	# node that is about to be freed, and nothing would ever restore it — the next
	# scene would run at the slow-mo rate permanently.
	if not _exiting:
		_drain_landings()
	_update_processing()


## Public abort — called DOWN by Main when the player leaves space mid-shot or
## a prestige takes over the camera.
func abort_cinematic() -> void:
	_teardown_cinematic()


func _set_input_lock(locked: bool) -> void:
	if locked == _input_locked:
		return
	_input_locked = locked
	if apply_input_lock_fn.is_valid():
		apply_input_lock_fn.call(locked)


# ── Framing (read DOWN by Main to park the camera on this board) ──────

func _world_scale() -> float:
	if not is_inside_tree():
		return 1.0
	return maxf(global_basis.get_scale().y, 0.0001)


func get_camera_target(camera_z: float) -> Vector3:
	var s: float = _world_scale()
	var centre_y: float = global_position.y - (vertical_spacing * NUM_ROWS / 2.0) * s
	return Vector3(global_position.x, centre_y, camera_z)


func get_camera_size() -> float:
	var s: float = _world_scale()
	var padding: float = ThemeProvider.theme.space_camera_padding
	var height: float = (vertical_spacing * NUM_ROWS) * s + padding
	var width: float = (space_between_pegs * (BUCKET_COLORS.size() - 1)) * s + padding
	return maxf(height, width)


# ── Dev hotkeys (editor-only; Main gates them behind demo_mode) ───────

## Send one coin of `currency_type` on the full journey: arc in from below,
## then an honest 10-row fall. Exercises the arrival beat.
func dev_send_coin(currency_type: Enums.CurrencyType) -> void:
	if not is_inside_tree():
		return
	var launch: Vector3 = global_position - Vector3(0, get_camera_size(), 0)
	receive_coin(currency_type, launch)


## Light the next unactivated bucket with the full cinematic. Spawns the coin
## straight onto the bucket (the lattice odds are never biased — locked
## decision 8), so the activation beat is reachable on demand. Press it while
## viewing space: off-camera it commits silently, like any other arrival.
func dev_activate_next_bucket() -> void:
	if not is_inside_tree():
		return
	for i in _activated.size():
		if _activated[i]:
			continue
		var coin := _make_coin(BUCKET_COLORS[i])
		if not coin or not is_instance_valid(coins_container):
			return
		coin.transform = Transform3D(_coin_basis, _bucket_top_local(i))
		coins_container.add_child(coin)
		_enqueue_landing(coin, BUCKET_COLORS[i], i)
		return


## Light everything instantly (no cinematic) so the win overlay can be filmed.
func dev_activate_all() -> void:
	for i in _activated.size():
		if not _activated[i]:
			_activated[i] = true
			_mark_bucket_activated(i)
			_set_underlay_fill(i, 1.0)
			bucket_activated.emit(i)
	if is_won(_activated):
		_won = true
		_win_pending = true
	_flush_win()


# ── Scene construction ───────────────────────────────────────────────

func _build_pegs(t: VisualTheme) -> void:
	var total_pegs: int = NUM_ROWS * (NUM_ROWS + 1) / 2
	var positions := PackedVector3Array()
	positions.resize(total_pegs)
	var idx := 0
	for row in range(NUM_ROWS):
		var y: float = -vertical_spacing * row
		for col in range(row + 1):
			positions[idx] = Vector3(Lattice.x_for(row, col, space_between_pegs), y, 0)
			idx += 1

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = total_pegs
	mm.mesh = t.make_peg_mesh()

	var peg_basis := Basis.IDENTITY
	if t.peg_shape == VisualTheme.PegShape.CYLINDER:
		peg_basis = Basis.from_euler(Vector3(PI / 2, 0, 0))

	for i in total_pegs:
		mm.set_instance_transform(i, Transform3D(peg_basis, positions[i]))
		mm.set_instance_color(i, t.peg_color)

	var mm_instance := MultiMeshInstance3D.new()
	mm_instance.multimesh = mm
	mm_instance.material_override = t.make_peg_shader_material()
	pegs_container.add_child(mm_instance)


func _build_buckets(_t: VisualTheme) -> void:
	var num_buckets: int = BUCKET_COLORS.size()
	var bucket_x_offset: float = -space_between_pegs * (num_buckets - 1) / 2.0
	var bucket_y_offset: float = -vertical_spacing * NUM_ROWS + (vertical_spacing / 3.0)
	buckets_container.position = Vector3(bucket_x_offset, bucket_y_offset, 0)

	_buckets.clear()
	for i in range(num_buckets):
		var bucket: Bucket = BucketScene.instantiate()
		bucket.is_prestige_bucket = false
		buckets_container.add_child(bucket)
		bucket.setup(BUCKET_COLORS[i], Vector3(i * space_between_pegs, 0, 0), 1)
		# The space board pays nothing, so a value label would be a lie. Hiding
		# it also lets the rainbow read as a clean palette (prototype's choice).
		var label := bucket.get_node_or_null("BucketValue")
		if label:
			label.visible = false
		_buckets.append(bucket)


## The empty circles the activated coins come to rest in. They are SIBLINGS of
## the buckets, not children: Bucket.pulse() animates position:y, and a child
## would bob along with it. They also live here rather than in bucket.tscn so a
## space-only concept never reaches every plinko/challenge/menu bucket.
func _build_underlays(t: VisualTheme) -> void:
	_underlay_fills.clear()
	var radius: float = t.space_underlay_radius
	var thickness: float = t.space_underlay_ring_thickness
	var inner: float = maxf(radius - thickness, 0.01)

	for i in _buckets.size():
		var holder := Node3D.new()
		holder.name = "Underlay%d" % i
		buckets_container.add_child(holder)
		holder.position = _buckets[i].position - Vector3(0, t.space_underlay_drop, 0)

		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = inner
		torus.outer_radius = radius
		ring.mesh = torus
		# TorusMesh lies in the XZ plane; face it at the camera (+Z).
		ring.rotation = Vector3(PI / 2, 0, 0)
		ring.material_override = _unshaded_material(t.space_underlay_empty_color)
		holder.add_child(ring)

		var fill := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = inner
		disc.bottom_radius = inner
		disc.height = 0.02
		fill.mesh = disc
		fill.rotation = Vector3(PI / 2, 0, 0)
		# Slightly behind the coin's plane so the resting coin reads on top.
		fill.position = Vector3(0, 0, -0.02)
		var fill_color: Color = t.get_bucket_color(BUCKET_COLORS[i])
		fill_color.a = 0.0
		var fill_mat := _unshaded_material(fill_color)
		fill_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		fill.material_override = fill_mat
		holder.add_child(fill)
		_underlay_fills.append(fill)


func _unshaded_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## `progress` 0 = empty circle, 1 = filled. Null-guarded so the bookkeeping in
## try_activate stays callable on a bare instance.
func _set_underlay_fill(index: int, progress: float) -> void:
	if index < 0 or index >= _underlay_fills.size():
		return
	var fill: MeshInstance3D = _underlay_fills[index]
	if not is_instance_valid(fill):
		return
	var p: float = clampf(progress, 0.0, 1.0)
	# Never a literal zero scale — Godot clamps that to 0.001 and logs about it.
	# Visibility is what actually hides an empty circle's fill.
	fill.scale = Vector3.ONE * maxf(p, 0.001)
	fill.visible = p > 0.0
	var mat := fill.material_override as StandardMaterial3D
	if mat:
		var c: Color = mat.albedo_color
		c.a = p
		mat.albedo_color = c


func _mark_bucket_activated(index: int) -> void:
	if index < 0 or index >= _buckets.size():
		return
	if is_instance_valid(_buckets[index]):
		_buckets[index].mark_activated(true)


## Repaint every bucket + circle from `_activated`. Called after _ready and
## after deserialize; no-ops on a bare instance.
func _refresh_bucket_visuals() -> void:
	for i in _activated.size():
		if i < _buckets.size() and is_instance_valid(_buckets[i]):
			_buckets[i].mark_activated(_activated[i])
		_set_underlay_fill(i, 1.0 if _activated[i] else 0.0)
