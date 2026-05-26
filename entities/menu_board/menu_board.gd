class_name MenuBoard
extends Node3D

## Decorative, visual-only Plinko board for the main-menu background.
##
## Why a triangular lattice: it is the SAME 30/60/90 peg packing the real game
## uses (shared `Lattice` module, also behind `PlinkoBoard`), so the menu
## previews the actual game feel instead of an unrelated graphic.
##
## Why a perspective camera when the gameplay board is orthographic: purely an
## aesthetic choice for the menu. A `Camera3D` tilted down from near the board's
## top makes pegs read as physical 3D pins and the tall row field recede and
## shrink toward the bottom of the screen. The camera is authored directly in
## menu_board.tscn (transform + fov on the `$Camera3D` node) so it can be moved
## live with the editor gizmo; nothing in code touches it. The key light's
## rotation is still set in code (only a direction, no transpose risk).
##
## Why decorative-only: these coins are visual sugar. No currency, no save, no
## upgrades, no `Coin` entity, no buckets, no rewards, no landing signal. A coin
## bounces row-by-row (random left/right) then despawns at the bottom row. This
## node emits nothing (calls down only). Reads `ThemeProvider.theme` for visual
## config and calls `AudioManager.play_pitched_chime` for two independent
## audio layers — peg-contact ticks + a background chord progression bed. See
## the CLAUDE.md `MenuBoard` entry for the audio-layer system map.

## Peg rows in the decorative lattice — taller than any early-game board so the
## field reads as receding into the distance under the perspective camera.
const MENU_BOARD_ROWS := 25

## Hard cap on simultaneously-falling coins (anti-leak backstop). Kept well
## ABOVE steady-state so the cap is never actually hit — coins must never stop
## dropping. Steady-state ≈ full-board fall time ÷ spawn interval ≈
## (MENU_BOARD_ROWS × ~0.4s) ÷ COIN_SPAWN_INTERVAL_SEC; at 25 rows that's ≈ 22,
## so 180 is a large safety margin. Bump this if MENU_BOARD_ROWS or the fall
## time grows a lot.
const MAX_DECORATIVE_COINS := 180

const COIN_SPAWN_INTERVAL_SEC := 0.45

## Fraction of one bounce spent rising; the rest is the fall to the next row
## (matches the real Coin's 1/3-up, 2/3-down arc).
const BOUNCE_RISE_FRACTION := 1.0 / 3.0

const COIN_SPAWN_DROP_HEIGHT := 1.6

const COIN_INITIAL_DROP_SEC := 0.3

## Menu pegs are near-flat discs (a cylinder collapsed along its axis) facing
## the camera — effectively a round plane, no 3D depth.
const MENU_PEG_THICKNESS := 0.001

## Scales peg radius + thickness (menu-only; not the theme's peg_radius). 1.5x
## compensates for the gameplay theme default being shrunk to 0.053 (was 0.08)
## so the menu's pegs stay visually their original 0.08 size — pair with
## MENU_PEG_SPACING_MULT = 1.5 to keep the menu's peg-to-spacing ratio.
const MENU_PEG_SIZE_MULT := 1.5

## Peg opacity fades down the board: alpha(row) = PEG_ALPHA_TOP −
## PEG_ALPHA_FALLOFF_PER_ROW * row, floored at 0 (far rows fade out entirely →
## depth). With the values below, pegs reach full transparency near the last row.
const PEG_ALPHA_TOP := 0.99
const PEG_ALPHA_FALLOFF_PER_ROW := 0.04

## The menu spreads its lattice wider than gameplay — multiplies the theme's
## space_between_pegs locally (does NOT touch the shared VisualTheme). Scales
## both horizontal and vertical peg spacing (vertical = space*sqrt3/2).
const MENU_PEG_SPACING_MULT := 1.5

## Coins ride in the SAME plane as the pegs (z = 0) — no parallax, they track
## the peg columns exactly. They no longer clip into pegs because the bounce
## arc is tall enough (MENU_BOUNCE_HEIGHT_MULT) to lift them clear between hits.
const COIN_Z_OFFSET := 0.0

## Decorative coins bounce a bit higher than the gameplay coin so that, sharing
## the peg plane, the arc lifts them clear of the peg geometry between contacts.
## (Halved from 3.0 — lower, calmer arcs; may graze pegs slightly, acceptable.)
const MENU_BOUNCE_HEIGHT_MULT := 1.5

## When a coin strikes a peg the pin does a slow "jello" pop: a big scale
## expansion that rings down with decreasing overshoots back to rest (elastic).
## Scale only — no rotation.
const PEG_WOBBLE_SCALE_PEAK := 1.5
const PEG_WOBBLE_DURATION := 2.7

## Authored chord progression. Each chord is FOUR notes authored in ascending
## order (root → up). The index parity selects the playback DIRECTION: even
## chords arpeggiate ascending (low→high), odd arpeggiate descending (high→low).
## `intro` plays on beat 0 alongside the regular note — an octave above one of
## the chord tones, picked per-chord to "announce" the new harmony. Held back
## until the second loop of the progression so the first time through is bare
## arpeggios (gradual reveal). `mid` is a higher-octave grace note that plays
## on the middle beat starting at loop 2 (third play-through), giving an
## x-x- pattern across the chord (intro on 0, grace on 2).
## Drop either key (or set "") to skip that note on a chord.
## To swap chords, edit the `notes` arrays. To flip a chord's direction, just
## reorder its position in the array.
const PEG_CHIME_PROGRESSION: Array[Dictionary] = [
	{"name": "Cmaj7", "notes": ["C3", "E3", "G3", "B3"],   "intro": "C5",  "mid": "E5"},
	{"name": "C7",    "notes": ["Db3", "E3", "G3", "Bb3"], "intro": "Bb4", "mid": "D5"},
	{"name": "Fmaj7", "notes": ["F3", "A3", "C4", "E4"],   "intro": "A4",  "mid": "C5"},
	{"name": "Fm6",   "notes": ["F3", "Ab3", "C4", "D4"],  "intro": "Ab4", "mid": "C5"},
]

## Beat grid for the background chord progression — fully decoupled from coin
## bounces (a `Timer` ticks the beat; bounces are visual-only now).
const PEG_CHIME_BEAT_SECONDS := 0.5
## Each chord plays one note per beat over this many beats. Steady 2-second
## phrase per chord; 8-second loop across the 4-chord progression.
const PEG_CHIME_BEATS_PER_CHORD := 4

## Mid-beat slot for `mid` grace notes — pre-computed const so the timeout
## handler doesn't divide on every tick. Integer division → middle of an
## even beats-per-chord (4 → 2), or first-past-middle for odd.
@warning_ignore("integer_division")
const PEG_CHIME_MID_BEAT: int = PEG_CHIME_BEATS_PER_CHORD / 2

## Loop-counter gates for layered ornaments. Intro accents enter on the
## SECOND play-through (loop_index == 1), mid grace notes on the THIRD.
## The first loop is intentionally bare so the chime arrives in stages.
const PEG_CHIME_INTRO_START_LOOP := 1
const PEG_CHIME_MID_START_LOOP := 2

## dB swing between the lowest and highest note of any chord. Higher pitch =
## louder, applied symmetrically to both directions: ascending arpeggios
## crescendo (quiet→loud), descending arpeggios decrescendo (loud→quiet).
const PEG_CHIME_DYNAMIC_RANGE_DB := 9.0

## Base chime loudness above bucket volume — `BUCKET_VOLUME_DB + this` is the
## peak of each arpeggio. ~+6 dB ≈ doubled amplitude; menu chime IS the
## soundscape (no busy gameplay layers underneath).
const PEG_CHIME_VOLUME_OFFSET_DB := 6.0

## Master toggle for the background chord progression. False = the beat timer
## ticks but plays nothing, so all chord state (loop index, indices, ornament
## gates) is preserved for an easy re-enable.
const PEG_CHIME_ENABLED := true

## Tone-less percussion blip on coin/peg contact (glass-marble clink). Rate-
## limited with a per-hit RANDOM interval so dense bounces don't strobe and
## the texture feels organic rather than metronomic. Pitch and volume are
## also randomised per hit so it sounds like varied physical material (size /
## striking force) rather than a sampled note.
const PEG_TICK_INTERVAL_MIN_S := 0.1
const PEG_TICK_INTERVAL_MAX_S := 0.4
const PEG_TICK_PITCH_MIN := 0.7
const PEG_TICK_PITCH_MAX := 1.6
## dB offset from BUCKET_VOLUME_DB — peg tick is a soft texture, well below
## the chime/buckets.
const PEG_TICK_VOLUME_OFFSET_DB := -10.0
## Per-hit amplitude randomisation: ±6 dB ≈ 0.5x to 2x amplitude.
## Wider swing makes some hits feel close-by and others distant.
const PEG_TICK_VOLUME_VARIATION_DB := 6.0

## Every Nth coin sparkles — visual peg-ring effect only, NO audio coupling.
## Audio plays in the background on its own beat timer.
const SPARKLE_EVERY_NTH_COIN := 4

## Per-bounce chance a coin bursts into particles instead of continuing.
const COIN_EXPLODE_CHANCE := 0.02

## `_track_tween` only sweeps dead tweens once the list exceeds this (kept well
## above steady-state live count so the sweep is rare/amortized, not per-call).
const TWEEN_PRUNE_THRESHOLD := 600

const PEG_RING_SHADER := preload("res://entities/plinko_board/peg_ring.gdshader")

## Every coin colour cycles through the menu (no economy — purely visual).
## One material per type is built once and reused.
const MENU_COIN_CURRENCIES: Array[Enums.CurrencyType] = [
	Enums.CurrencyType.GOLD_COIN,
	Enums.CurrencyType.ORANGE_COIN,
	Enums.CurrencyType.RED_COIN,
	Enums.CurrencyType.VIOLET_COIN,
	Enums.CurrencyType.BLUE_COIN,
	Enums.CurrencyType.GREEN_COIN,
]

## Camera is authored on the `$Camera3D` node in menu_board.tscn (transform +
## fov), NOT here — open that scene in the editor, select Camera3D, move/rotate
## it with the gizmo (or set Transform/FOV in the Inspector), save, run. Code
## must not write the camera transform or the editor edits would be ignored.

## Menu-only key light. The gameplay theme is unshaded, so ThemeProvider adds no
## DirectionalLight; the menu deliberately adds one (rotation set in code for the
## same reason as the camera — a .tscn Transform3D literal is row-major and easy
## to transpose). Angled to RAKE across the pegs (more side than top-down) and
## bright enough that each pin's camera-facing cap reads distinctly from its
## barrel. Tuned by eye.
const MENU_LIGHT_ROTATION_DEG := Vector3(-30.0, -55.0, 0.0)
const MENU_LIGHT_ENERGY := 0.95

## How far ABOVE each peg row a coin rests (same idea as
## PlinkoBoard.COIN_ROW_Y_OFFSET). Pegs sit at y = -vspace*row; lifting every
## coin waypoint by this much makes coins bounce ON TOP of the pegs instead of
## clipping through their centres, while staying in the SAME Z plane (so they
## still track the peg columns — no parallax). Roughly peg_radius + coin_radius.
## Local (not PlinkoBoard's) so the lattice parity test stays a pure
## PlinkoBoard-vs-Lattice comparison.
const COIN_ROW_Y_OFFSET := 0.22

## Lattice geometry. Plain fields (defaulted from the theme in `_ready`) so the
## pure lattice methods below are callable on a bare `MenuBoard.new()` in tests,
## exactly like `PlinkoBoard`. `num_rows` / `position_x_for` /
## `next_lattice_cell` / `is_terminal_cell` deliberately mirror PlinkoBoard's
## names so a parity test can assert the menu can't drift from the real board.
var space_between_pegs := 1.0
var num_rows := MENU_BOARD_ROWS

@onready var _pegs: Node3D = $Pegs
@onready var _coins: Node3D = $Coins
@onready var _spawn_timer: Timer = $SpawnTimer
@onready var _chime_beat_timer: Timer = $ChimeBeatTimer
@onready var _light: DirectionalLight3D = $DirectionalLight3D

var _vertical_spacing := 0.0
var _coin_mesh: Mesh
# Shared sphere reused by every explosion particle — built once in _ready.
var _particle_mesh: SphereMesh
# currency (int) -> shaded StandardMaterial3D / palette Color, built in _ready.
var _coin_materials: Dictionary = {}
var _coin_colors: Dictionary = {}
var _coin_basis := Basis.IDENTITY
# Peg MultiMesh + per-peg base orientation, kept so individual pegs can wobble.
var _peg_mm: MultiMesh
var _peg_basis := Basis.IDENTITY
# peg index -> its active wobble Tween, so repeated hits don't fight.
var _peg_wobbles: Dictionary = {}
var _live_coin_count := 0
var _coin_tweens: Array[Tween] = []
# Running spawn tally; every SPARKLE_EVERY_NTH_COIN-th coin sparkles (visual only).
var _spawn_count: int = 0
# Beat-grid state. `_chord_index` walks PEG_CHIME_PROGRESSION; `_beat_index`
# walks 0..PEG_CHIME_BEATS_PER_CHORD-1 within the current chord. Driven by
# the ChimeBeatTimer (timeout → _on_chime_beat_timeout); coin bounces never
# touch these.
var _chord_index: int = 0
var _beat_index: int = 0
# Completed full progressions. Gates layered ornaments — intro accents start
# at loop 1 (second play-through), mid-beat grace notes start at loop 2 (third).
# First loop is bare arpeggios so the chime arrives in stages.
var _loop_index: int = 0
# Cached pitch multipliers per chord (parsed once in _ready from
# PEG_CHIME_PROGRESSION) — parallel structure: _chime_pitches[chord][note].
var _chime_pitches: Array[PackedFloat32Array] = []
# Parallel to _chime_pitches: per-chord intro-accent pitch played on beat 0.
# 0.0 = no intro for that chord (data didn't include / set blank `intro`).
var _chime_intro_pitches: PackedFloat32Array = PackedFloat32Array()
# Parallel: per-chord mid-beat grace pitch played on the middle beat of each
# chord starting at loop 2. 0.0 = no mid note for that chord.
var _chime_mid_pitches: PackedFloat32Array = PackedFloat32Array()
# Earliest time (seconds, monotonic) at which the next peg-tick may fire.
# 0.0 so the first hit always plays. A fresh random interval is rolled each
# time a tick fires (see _try_play_peg_tick) — keeps the texture organic.
var _peg_tick_next_time: float = 0.0
# Timbre for the chord bed. Hardcoded (NOT theme-driven) — the menu chime is
# its own audio role, not a copy of the gameplay bucket sound. Swap in
# `Instrument.Type.{SOFT_CHIME,BELL,HARP,...}` here to A/B variants.
const CHIME_INSTRUMENT_TYPE: Instrument.Type = Instrument.Type.MUSIC_BOX
# Impact squash, copied from the gameplay Coin so bounces read naturally.
var _squash_enabled := false
var _squash_scale := Vector3.ONE
var _squash_duration := 0.0


func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	space_between_pegs = t.space_between_pegs * MENU_PEG_SPACING_MULT
	num_rows = MENU_BOARD_ROWS
	_vertical_spacing = Lattice.vertical_spacing(space_between_pegs)

	_build_pegs(t)

	_coin_mesh = t.make_coin_mesh()
	for currency in MENU_COIN_CURRENCIES:
		var c: Color = t.get_coin_color(currency)
		_coin_colors[currency] = c
		# Low metallic + mid roughness → soft, no harsh specular hotspot.
		_coin_materials[currency] = _make_shaded_material(c, 0.1, 0.55)
	# Built ONCE and shared by every explosion particle (no per-burst alloc).
	_particle_mesh = SphereMesh.new()
	_particle_mesh.radius = t.coin_radius * 0.35
	_particle_mesh.height = _particle_mesh.radius * 2.0

	if t.coin_shape == VisualTheme.CoinShape.CYLINDER:
		# Lay the cylinder flat so it reads as a coin face-on to the camera.
		_coin_basis = Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0))

	_squash_enabled = t.coin_impact_squash_enabled
	_squash_scale = t.coin_impact_squash_scale
	_squash_duration = t.coin_impact_squash_duration

	_chime_pitches = []
	_chime_intro_pitches = PackedFloat32Array()
	_chime_mid_pitches = PackedFloat32Array()
	for chord_entry in PEG_CHIME_PROGRESSION:
		var notes: Array = chord_entry["notes"]
		var arr := PackedFloat32Array()
		for note in notes:
			arr.append(SoftChime.note_name_to_pitch_mult(note))
		_chime_pitches.append(arr)
		# 0.0 sentinel = no extra note for this chord at this slot.
		var intro_pitch: float = 0.0
		if chord_entry.has("intro") and String(chord_entry["intro"]) != "":
			intro_pitch = SoftChime.note_name_to_pitch_mult(chord_entry["intro"])
		_chime_intro_pitches.append(intro_pitch)
		var mid_pitch: float = 0.0
		if chord_entry.has("mid") and String(chord_entry["mid"]) != "":
			mid_pitch = SoftChime.note_name_to_pitch_mult(chord_entry["mid"])
		_chime_mid_pitches.append(mid_pitch)

	_spawn_timer.wait_time = COIN_SPAWN_INTERVAL_SEC
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	_spawn_timer.start()

	# Background chord beat — independent of coin bounces. Fires on a fixed
	# 0.5s grid regardless of how many coins are alive.
	_chime_beat_timer.wait_time = PEG_CHIME_BEAT_SECONDS
	_chime_beat_timer.timeout.connect(_on_chime_beat_timeout)
	_chime_beat_timer.start()

	# Camera transform/fov are authored on $Camera3D in the .tscn (editor-tunable).
	_light.rotation_degrees = MENU_LIGHT_ROTATION_DEG
	_light.light_energy = MENU_LIGHT_ENERGY


func _exit_tree() -> void:
	# SceneManager.set_new_scene() frees the whole MainMenu mid-fade while coins
	# may still be tweening — kill every live tween so no callback fires against
	# a freeing coin. Same rationale for the ChimeBeatTimer: stop it explicitly
	# so a final timeout can't fire `_on_chime_beat_timeout` mid-free.
	if _chime_beat_timer != null:
		_chime_beat_timer.stop()
	for tween in _coin_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_coin_tweens.clear()


# ── Pure lattice helpers (mirror PlinkoBoard names; no tree/theme needed) ──

## Local x of lattice cell (row, col). Same formula as
## PlinkoBoard.position_x_for (both forward to `Lattice`) so the menu board
## can't drift from the real game.
func position_x_for(row: int, col: int) -> float:
	return Lattice.x_for(row, col, space_between_pegs)


## Pure integer lattice transition. `direction` is an Enums.Direction (+1 right).
func next_lattice_cell(row: int, col: int, direction: int) -> Vector2i:
	return Lattice.next_cell(row, col, direction)


## True once a coin has bounced past the last peg row.
func is_terminal_cell(row: int, _col: int) -> bool:
	return row >= num_rows


## Flat peg index for (row, col) — matches the row-major fill in _build_pegs
## (same triangular formula as PlinkoBoard.peg_index).
func _peg_index(row: int, col: int) -> int:
	@warning_ignore("integer_division")
	return row * (row + 1) / 2 + col


# ── Shaded materials ──

## The active theme is flat/unshaded by design for gameplay; the menu board
## deliberately overrides that with lit StandardMaterial3D + a DirectionalLight
## (in menu_board.tscn) so the 3D pegs/coins read with form. Colour still comes
## from the theme palette (never a raw Color).
func _make_shaded_material(albedo: Color, metallic: float,
		roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


# ── Peg field ──

func _build_pegs(t: VisualTheme) -> void:
	@warning_ignore("integer_division")
	var total_pegs: int = num_rows * (num_rows + 1) / 2

	# Order matters (matches plinko_board.gd): transform_format / use_colors
	# before instance_count allocates the buffer; mesh after.
	# Menu pegs are always cylinders standing toward the camera, regardless of
	# the theme's peg_shape.
	var peg_mesh := CylinderMesh.new()
	peg_mesh.top_radius = t.peg_radius * MENU_PEG_SIZE_MULT
	peg_mesh.bottom_radius = t.peg_radius * MENU_PEG_SIZE_MULT
	# Collapsed along its axis → reads as a flat round plane, not a 3D pin.
	peg_mesh.height = MENU_PEG_THICKNESS * MENU_PEG_SIZE_MULT

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = total_pegs
	mm.mesh = peg_mesh

	# Rotate the cylinder's length axis (local Y) to world +Z so each peg pokes
	# out toward the viewer.
	_peg_basis = Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0))

	# Rich warm brown from the palette (theme's orange, darkened to a deeper
	# coffee) — the bg shades read too grey. Per-row alpha lives in the
	# per-instance colour (material reads it as albedo), fading down the board.
	var peg_color: Color = t.get_coin_color(Enums.CurrencyType.ORANGE_COIN).darkened(0.35)
	var idx := 0
	for row in range(num_rows):
		var y: float = -_vertical_spacing * row
		var row_alpha := maxf(0.0, PEG_ALPHA_TOP - PEG_ALPHA_FALLOFF_PER_ROW * row)
		var col_with_alpha := Color(peg_color.r, peg_color.g, peg_color.b, row_alpha)
		for col in range(row + 1):
			var pos := Vector3(position_x_for(row, col), y, 0.0)
			mm.set_instance_transform(idx, Transform3D(_peg_basis, pos))
			mm.set_instance_color(idx, col_with_alpha)
			idx += 1

	_peg_mm = mm
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mm
	# Per-instance colour (incl. alpha) drives albedo; transparent so the
	# fade-down reads. Soft sheen (specular on, mid roughness, metallic 0) so
	# the light still gives each pin readable 3D form without a harsh hotspot.
	var peg_mat := StandardMaterial3D.new()
	peg_mat.albedo_color = Color.WHITE
	peg_mat.vertex_color_use_as_albedo = true
	peg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	peg_mat.metallic = 0.0
	peg_mat.roughness = 0.5
	instance.material_override = peg_mat
	_pegs.add_child(instance)


# ── Decorative coins ──

func _on_spawn_timer_timeout() -> void:
	if _live_coin_count >= MAX_DECORATIVE_COINS:
		return
	_spawn_coin()


func _spawn_coin() -> void:
	var coin := MeshInstance3D.new()
	coin.mesh = _coin_mesh
	var currency: Enums.CurrencyType = MENU_COIN_CURRENCIES.pick_random()
	coin.material_override = _coin_materials[currency]
	coin.basis = _coin_basis

	_spawn_count += 1
	var sparkle: bool = _spawn_count % SPARKLE_EVERY_NTH_COIN == 0
	var coin_color: Color = _coin_colors[currency]

	var entry := _cell_position(0, 0) + Vector3(0.0, 0.0, COIN_Z_OFFSET)
	coin.position = entry + Vector3(0.0, COIN_SPAWN_DROP_HEIGHT, 0.0)
	_coins.add_child(coin)
	_live_coin_count += 1

	# Drop in from above, then bounce row by row (bounces tween only x/y).
	var drop := _track_tween(create_tween())
	drop.tween_property(coin, "position", entry, COIN_INITIAL_DROP_SEC) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	drop.tween_callback(_advance_coin_bounce.bind(coin, 0, 0, coin_color, sparkle))


## Recursive row-by-row bounce, like the gameplay Coin (CLAUDE.md "row by row").
## `row`/`col` are explicit (not a hidden default counter) and the base case is
## checked first so a cold reader sees termination immediately. Sparkle coins
## emit a peg ring at every peg they strike — purely visual, no audio coupling
## (audio runs on the ChimeBeatTimer in the background).
func _advance_coin_bounce(coin: MeshInstance3D, row: int, col: int,
		coin_color: Color, sparkle: bool) -> void:
	if not is_instance_valid(coin):
		return
	if is_terminal_cell(row, col):
		_despawn_coin(coin)
		return

	var t: VisualTheme = ThemeProvider.theme

	var direction: int = Enums.Direction.RIGHT if randf() < 0.5 else Enums.Direction.LEFT

	_wobble_peg(row, col)
	if sparkle:
		_spawn_peg_ring(_peg_position(row, col), coin_color, t)
	_try_play_peg_tick()

	if randf() < COIN_EXPLODE_CHANCE:
		_explode_coin(coin, t)
		return

	# Squash on peg contact, then spring back — copied from the gameplay Coin.
	if _squash_enabled:
		coin.scale = _squash_scale
		var squash := _track_tween(create_tween())
		squash.tween_property(coin, "scale", Vector3.ONE, _squash_duration) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	var next: Vector2i = next_lattice_cell(row, col, direction)
	var target := _cell_position(next.x, next.y)
	# Per-bounce randomness so the field doesn't look uniform (as in Coin),
	# scaled up so the coplanar coin arcs clear of the pegs.
	var bounce_height: float = (t.coin_bounce_height * MENU_BOUNCE_HEIGHT_MULT
		* randf_range(0.3, 1.7))
	var fall_time: float = t.coin_fall_time * randf_range(0.9, 1.1)

	# Two CONCURRENT tweens, exactly like Coin._bounce_or_despawn: x glides the
	# whole way while y arcs up then down over the same span, so the path is a
	# natural parabola (not horizontal-then-vertical).
	var x_tween := _track_tween(create_tween())
	x_tween.tween_property(coin, "position:x", target.x, fall_time) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_LINEAR)

	var y_tween := _track_tween(create_tween())
	y_tween.tween_property(coin, "position:y",
			coin.position.y + bounce_height, fall_time * BOUNCE_RISE_FRACTION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	y_tween.tween_property(coin, "position:y", target.y,
			fall_time * (1.0 - BOUNCE_RISE_FRACTION)) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# Re-enter for the next row once this bounce finishes.
	y_tween.tween_callback(
		_advance_coin_bounce.bind(coin, next.x, next.y, coin_color, sparkle))


func _despawn_coin(coin: MeshInstance3D) -> void:
	if not is_instance_valid(coin):
		return
	_live_coin_count = maxi(0, _live_coin_count - 1)
	coin.queue_free()


## Burst the coin into a short-lived scatter of small spheres in its colour
## (reuses the theme's coin-land particle params), then despawn the coin.
## Tweens are tracked so a mid-fade scene exit can't fire a stale callback.
func _explode_coin(coin: MeshInstance3D, t: VisualTheme) -> void:
	if not is_instance_valid(coin):
		return
	var origin: Vector3 = coin.position
	var count: int = t.coin_land_particle_count
	var dist: float = t.coin_land_particle_speed * t.coin_land_particle_duration
	var life: float = t.coin_land_particle_duration

	# Reuse the prebuilt shared sphere + the coin's already-shared per-currency
	# material — no per-explosion Mesh/Material allocation (that churn, esp.
	# StandardMaterial3D shader setup, was the lag).
	var mat: Material = coin.material_override

	for i in count:
		var p := MeshInstance3D.new()
		p.mesh = _particle_mesh
		p.material_override = mat
		p.position = origin
		_coins.add_child(p)
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)).normalized()
		var tw := _track_tween(create_tween())
		tw.tween_property(p, "position", origin + dir * dist, life) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(p, "scale", Vector3.ZERO, life) \
			.set_ease(Tween.EASE_IN)
		tw.tween_callback(p.queue_free)

	_despawn_coin(coin)


## The struck peg does a slow "jello" pop: scale rings from PEAK down to 1.0
## with decaying overshoots (elastic) — enlarge/shrink only, NO rotation. A
## repeated hit on the same peg replaces the prior wobble so concurrent tweens
## don't fight over one MultiMesh instance transform.
func _wobble_peg(row: int, col: int) -> void:
	if _peg_mm == null:
		return
	var idx := _peg_index(row, col)
	var base_pos := _peg_position(row, col)
	# The literal resting transform; restored verbatim on settle so repeated
	# round-trips can't accumulate orthonormality drift on a long-idling menu.
	var base_xform := Transform3D(_peg_basis, base_pos)

	var prior: Variant = _peg_wobbles.get(idx, null)
	if prior is Tween and prior.is_valid():
		prior.kill()

	# Uniform scale only; keep the peg's resting orientation (_peg_basis).
	var tw := _track_tween(create_tween())
	tw.tween_method(
		func(s: float) -> void:
			_peg_mm.set_instance_transform(idx, Transform3D(
				_peg_basis.scaled(Vector3(s, s, s)), base_pos)),
		PEG_WOBBLE_SCALE_PEAK, 1.0, PEG_WOBBLE_DURATION) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if _peg_mm != null:
			_peg_mm.set_instance_transform(idx, base_xform)
		# Only clear our own entry — a newer wobble may already own this idx.
		if _peg_wobbles.get(idx) == tw:
			_peg_wobbles.erase(idx))
	_peg_wobbles[idx] = tw


## Rate-limited tone-less peg-contact blip — glass-marble clink. Called on
## every peg strike of every coin (not just the sparkle coin). A random
## interval is rolled after each fire so the texture isn't metronomic, and
## pitch + volume are also randomised per hit so successive clinks read as
## different physical objects (size + striking force) rather than a
## repeating sample.
func _try_play_peg_tick() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _peg_tick_next_time:
		return
	_peg_tick_next_time = now + randf_range(PEG_TICK_INTERVAL_MIN_S,
		PEG_TICK_INTERVAL_MAX_S)
	var pitch: float = randf_range(PEG_TICK_PITCH_MIN, PEG_TICK_PITCH_MAX)
	var volume_jitter: float = randf_range(-PEG_TICK_VOLUME_VARIATION_DB,
		PEG_TICK_VOLUME_VARIATION_DB)
	var volume_db: float = AudioManager.BUCKET_VOLUME_DB \
		+ PEG_TICK_VOLUME_OFFSET_DB + volume_jitter
	AudioManager.play_pitched_chime(pitch, volume_db, NAN, Instrument.Type.PEG_TICK)


## Beat-grid driver — fires every PEG_CHIME_BEAT_SECONDS (0.5s) regardless of
## coin activity. One note per beat across PEG_CHIME_BEATS_PER_CHORD beats per
## chord. Even-indexed chords play their notes in authored (ascending) order;
## odd-indexed chords play them in reverse (descending arpeggio). After all
## beats fire, advance to the next chord (wrapping at end of progression).
func _on_chime_beat_timeout() -> void:
	if not PEG_CHIME_ENABLED:
		return
	if _chime_pitches.is_empty():
		return
	var pitches: PackedFloat32Array = _chime_pitches[_chord_index]
	if pitches.size() > 0 and _beat_index < pitches.size():
		# Notes in each chord are ALWAYS authored ascending. Direction is
		# implicit from chord-index parity — even chords iterate the array
		# forward, odd chords iterate it backward. This single rule produces
		# the ascend/descend pattern in PEG_CHIME_PROGRESSION's docstring.
		var ascending: bool = _chord_index % 2 == 0
		var note_idx: int = _beat_index if ascending else pitches.size() - 1 - _beat_index
		# Per-note offset scales with pitch (`note_idx` in the ascending
		# array): lowest note sits at base - PEG_CHIME_DYNAMIC_RANGE_DB,
		# highest at base. The same rule for ascending AND descending —
		# direction emerges from how note_idx is iterated above.
		var base_db: float = AudioManager.BUCKET_VOLUME_DB + PEG_CHIME_VOLUME_OFFSET_DB
		var t_pitch: float = 0.0 if pitches.size() <= 1 \
			else float(note_idx) / float(pitches.size() - 1)
		var volume_db: float = base_db - PEG_CHIME_DYNAMIC_RANGE_DB * (1.0 - t_pitch)
		AudioManager.play_pitched_chime(pitches[note_idx], volume_db,
			NAN, CHIME_INSTRUMENT_TYPE)
		# Beat 0 fires the chord's intro accent (an octave above one of its
		# chord tones) — "announces" the new harmony. Held back until the
		# second play-through (loop 1) so loop 0 stays bare. Plays at base
		# volume so it sits clearly above the arpeggio dynamic.
		if _beat_index == 0 and _loop_index >= PEG_CHIME_INTRO_START_LOOP \
				and _chord_index < _chime_intro_pitches.size():
			var intro_pitch: float = _chime_intro_pitches[_chord_index]
			if intro_pitch > 0.0:
				AudioManager.play_pitched_chime(intro_pitch, base_db,
					NAN, CHIME_INSTRUMENT_TYPE)
		# Mid-beat slot adds a higher-octave grace note starting at the third
		# play-through (loop 2) — produces the x-x- pattern across the chord
		# (intro on beat 0, grace on PEG_CHIME_MID_BEAT).
		if _beat_index == PEG_CHIME_MID_BEAT \
				and _loop_index >= PEG_CHIME_MID_START_LOOP \
				and _chord_index < _chime_mid_pitches.size():
			var mid_pitch: float = _chime_mid_pitches[_chord_index]
			if mid_pitch > 0.0:
				AudioManager.play_pitched_chime(mid_pitch, base_db,
					NAN, CHIME_INSTRUMENT_TYPE)

	_beat_index += 1
	if _beat_index >= PEG_CHIME_BEATS_PER_CHORD:
		_beat_index = 0
		_chord_index += 1
		if _chord_index >= _chime_pitches.size():
			_chord_index = 0
			_loop_index += 1


## Expanding sparkle ring at a struck peg — same shader/animation as the
## gameplay board's _spawn_peg_ring, in the coin's colour.
func _spawn_peg_ring(peg_pos: Vector3, ring_color: Color, t: VisualTheme) -> void:
	var ring := MeshInstance3D.new()
	var ring_mesh := QuadMesh.new()
	var quad_size: float = t.peg_ring_max_radius * 2.0
	ring_mesh.size = Vector2(quad_size, quad_size)
	ring.mesh = ring_mesh

	var mat := ShaderMaterial.new()
	mat.shader = PEG_RING_SHADER
	mat.set_shader_parameter("ring_color", ring_color)
	mat.set_shader_parameter("ring_thickness", t.peg_ring_thickness)
	mat.set_shader_parameter("ring_radius", 0.0)
	mat.set_shader_parameter("opacity_mult", 0.0)
	ring.material_override = mat
	# Just behind the peg/coin plane (like the gameplay ring) so it haloes the
	# peg without occluding the now-coplanar coins.
	ring.position = peg_pos + Vector3(0.0, 0.0, -0.03)
	_pegs.add_child(ring)

	var max_opacity: float = t.peg_ring_max_opacity
	var tween := _track_tween(create_tween())
	tween.tween_method(
		func(p: float) -> void:
			mat.set_shader_parameter("ring_radius", p)
			mat.set_shader_parameter("opacity_mult", sin(p * PI) * max_opacity),
		0.0, 1.0, t.peg_ring_duration)
	tween.tween_callback(ring.queue_free)


## World position of the PEG at lattice cell (row, col) — NO coin Y offset.
## Coins ride COIN_ROW_Y_OFFSET above this; the wobble and the sparkle ring
## act on the peg itself, so they use this.
func _peg_position(row: int, col: int) -> Vector3:
	return Vector3(position_x_for(row, col), -_vertical_spacing * row, 0.0)


## World position of lattice cell (row, col) for the decorative board.
func _cell_position(row: int, col: int) -> Vector3:
	return Lattice.cell_to_world(row, col, space_between_pegs,
		_vertical_spacing, COIN_ROW_Y_OFFSET)


## Tracks a tween so `_exit_tree` can kill it, and drops finished tweens so the
## list can't grow without bound while the menu idles.
func _track_tween(tween: Tween) -> Tween:
	_coin_tweens.append(tween)
	# Amortized prune: rebuilding the whole array every call was O(n) per
	# tracked tween (hundreds live), so an 8-particle explosion did 8 full
	# rebuilds. Only sweep past the threshold → the common path is O(1).
	if _coin_tweens.size() > TWEEN_PRUNE_THRESHOLD:
		_coin_tweens = _coin_tweens.filter(func(tw: Tween) -> bool:
			return tw != null and tw.is_valid())
	return tween
