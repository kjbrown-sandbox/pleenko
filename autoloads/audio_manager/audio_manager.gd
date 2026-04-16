extends Node

# Fires when the chord progression advances. PlinkoBoard listens and fades
# chord-activated buckets back to faded.
signal chord_changed(chord_index: int)

# Fired when a drum-layer tier plays a beat. PlinkoBoard listens to pulse
# every bucket at the given distance-from-center.
signal drum_tier_fired(tier: int)

# Fired when a drum-layer tier's active lifetime runs out. PlinkoBoard fades
# every bucket at that distance back to faded.
signal drum_tier_expired(tier: int)

# Floor for chord-gated tail length so a late-chord hit still rings audibly
# before the chord_changed fade starts.
const MIN_BUCKET_RING_SECONDS := 1.0

const POOL_SIZE := 10
const MAX_BUCKET_SOUNDS := 30

var _pools: Dictionary = {}  # StringName -> Array[AudioStreamPlayer]
var _indices: Dictionary = {}  # StringName -> int (round-robin index)

var _sounds: Dictionary = {
	&"bucket_land": preload("res://assets/sounds/zapsplat_enter_bucket.mp3"),
	&"menu_item": preload("res://assets/sounds/zapsplat_menu_item.mp3"),
	&"coin": preload("res://assets/sounds/itchambroggiomusic/Coin.mp3"),
	&"old_coin": preload("res://assets/sounds/itchambroggiomusic/Old Coin.mp3"),
	&"coin_flip": preload("res://assets/sounds/itchambroggiomusic/Coin Flip.mp3"),
	&"retro_coin_1": preload("res://assets/sounds/itchambroggiomusic/Retro Coin 1.mp3"),
	&"retro_coin_2": preload("res://assets/sounds/itchambroggiomusic/Retro Coin 2.mp3"),
	&"coin_pouch_1": preload("res://assets/sounds/itchambroggiomusic/Coin Pouch 1.mp3"),
	&"coin_pouch_2": preload("res://assets/sounds/itchambroggiomusic/Coin Pouch 2.mp3"),
	&"coin_rattle": preload("res://assets/sounds/itchambroggiomusic/Coin Rattle.mp3"),
	&"prestige": preload("res://assets/sounds/lucadialessandro-prestige.wav"),
}

# ── Musical system ───────────────────────────────────────────────────

# Chord voicings (semitone offsets above root) — reference for .tres authors.
# Bucket distance from center indexes into the array (center = root, ±1 = 3rd).
#   maj7: [0, 4, 7, 11, 12, 16, 19, 23]
#   dom7: [0, 4, 7, 10, 12, 16, 19, 22]
#   min7: [0, 3, 7, 10, 12, 15, 19, 22]
#   maj:  [0, 4, 7, 12, 16, 19, 24, 28]
#   min:  [0, 3, 7, 12, 15, 19, 24, 27]

var _chord_index: int = 0
const CHORD_IDLE_RESET := 2.0

# Beat grid: 4/4 derived from the autodropper tick. Beat clock free-runs at
# DEFAULT_AUTODROP_INTERVAL until the first real tick snaps the phase.
const DEFAULT_AUTODROP_INTERVAL := 1.5
const BEATS_PER_BAR := 4

const MELODY_POOL_SIZE := 12
const CLICK_POOL_SIZE := 8
# DEPRECATED — ambient pad constants. The pad layer is dormant; `_fade_in_ambient`
# early-returns. See the `DEPRECATED: Ambient pad` section below for the full
# dormant code path and removal candidates.
const AMBIENT_FADE_DURATION := 2.0
const AMBIENT_IDLE_TIMEOUT := 2.0
const AMBIENT_VOLUME_DB := -6.0
const PEG_CLICK_VOLUME_DB := -18.0
const PEG_SPARKLE_VOLUME_DB := -8.0
const BUCKET_VOLUME_DB := -17.5

var _cello_pool: Array[AudioStreamPlayer] = []
var _chime_pool: Array[AudioStreamPlayer] = []
var _click_pool: Array[AudioStreamPlayer] = []
var _cello_idx: int = 0
var _chime_idx: int = 0
var _click_idx: int = 0

var _active_board: Enums.BoardType = Enums.BoardType.GOLD

var _chord_timer: float = 6.0  # overwritten from theme.chord_duration on _ready
var _chord_idle_timer: float = 0.0
var _chord_had_sparkle: bool = false

var _autodrop_interval: float = DEFAULT_AUTODROP_INTERVAL
var _beat_period: float = DEFAULT_AUTODROP_INTERVAL / BEATS_PER_BAR
var _beat_phase: float = 0.0
var _beat_armed: bool = false
var _motif_position: int = 0

# DEPRECATED — ambient pad double-buffer state. Pad layer is dormant.
var _ambient_a: AudioStreamPlayer
var _ambient_b: AudioStreamPlayer
var _ambient_active: AudioStreamPlayer
var _ambient_pad_streams: Dictionary = {}  # BoardType -> AudioStreamWAV
var _ambient_fading_in: bool = false
var _idle_timer: float = 0.0
var _activity_detected: bool = false
# Ambient pad stays alive while > 0 and for AMBIENT_IDLE_TIMEOUT after it hits 0.
var _active_coin_count: int = 0

# Drone lifecycle:
#   SPARKLE   — peg sparkle; timer-decayed by _update_bucket_drones.
#   ACTIVE    — bucket note in current chord; chord-managed (chord advance
#               flips it to LINGERING), never timer-decayed.
#   LINGERING — previous chord's note carrying across silence; timer = synth
#               sample length so the slot releases after audible decay ends.
# Fade-duration knobs live on VisualTheme: bucket_fade_duration (visual color
# tween), linger_fade_duration (audio handoff), eviction_fade_duration.
enum DroneState { SPARKLE, ACTIVE, LINGERING }

# Per-coin-type voice caps. Normal = melodic top layer, advanced = deeper bass
# punctuation. Independent pools so they don't dim or evict each other.
const MAX_NORMAL_DRONES := 5
const MAX_ADVANCED_DRONES := 3

# Per-voice attenuation: voice N plays at VOICE_ATTENUATION_RATIO^(N-1) of
# base amplitude (~2.5 dB drop per added voice at 0.75). The Drones-bus
# compressor is tuned against this curve — retune both together.
const VOICE_ATTENUATION_RATIO := 0.75

const BUCKET_DRONE_FADE_RATE := 24.0  # dB/sec — 3s fade over ~72 dB
const SPARKLE_DRONE_SUSTAIN := 3.5
const BUCKET_DRONE_POOL_SIZE := 24
var _drone_pool: Array[AudioStreamPlayer] = []
var _drone_free: Array[int] = []
var _active_drones: Dictionary = {}  # String key -> { "idx", "timer", "degree", "octave_mult", "state" }
# Keyed by drone pool idx. Killed before a slot is reused so an in-flight fade
# can't keep writing to the new drone's volume_db.
var _drone_fade_tweens: Dictionary = {}

# Bucket audio — three modes, selected by theme data:
#   Drum-layer mode (drum_instruments non-empty): coin landings activate
#     percussion tiers; a global sequencer plays their beat patterns.
#   Arpeggio mode (arpeggio_pattern non-empty): pattern picks from activated
#     bucket pool (FIFO-then-random). First hit of a chord is immediate.
#   Queue mode (default): hits dispatch BUCKET_WAIT apart, coin-driven.
const BUCKET_WAIT := 0.5
var _bucket_queue: Array[Dictionary] = []
var _chord_activated_buckets: Dictionary = {}
var _last_bucket_play_time: float = -999.0

# Arpeggio-mode only. Cleared on chord advance.
var _activated_buckets_order: Array[Dictionary] = []
var _unplayed_buckets: Array[Dictionary] = []
var _pattern_slot_idx: int = -1
var _pattern_slot_timer: float = 0.0

# Sequencer (drum-layer mode): drives both melody and drum-layer playback.
# Starts on first challenge tick, ticks at SLOT_DURATION (0.25s = 4/sec).
const SLOT_DURATION := 0.25
var _sequencer_running: bool = false
var _global_slot_idx: int = 0
var _slot_timer: float = 0.0
var _melody_player: AudioStreamPlayer
var _melody_idx: int = 0
var _active_drum_tiers: Dictionary = {}  # tier_index -> expiration time (sec)
const DRUM_POOL_SIZE := 6
var _drum_seq_pool: Array[AudioStreamPlayer] = []
var _drum_seq_idx: int = 0

var _sparkle_counter: int = 0
# Default streams assigned to drone pool slots at startup. Individual plays
# may override via instrument.resolve().
var _sine_drone_stream: AudioStreamWAV
var _piano_drone_stream: AudioStream = preload("res://assets/sounds/instrument_samples/Ensoniq-ESQ-1-FM-Piano-C4.wav")

# Instruments — each owns its synthesis (sample or procedural) and exposes
# resolve(pitch_mult) -> { stream, pitch_scale }. AudioManager keeps voice
# pooling, fades, chord-gated lifecycle, and bus routing.
var _harp: Harp
var _triangle: Triangle
var _arcade_kick: ArcadeKick
var _click: Click
var _drum_kick_deep: DrumKick
var _drum_kick_thin: DrumKick
var _drum_kick_bass: DrumKick
var _drum_snare: DrumSnare
var _drum_clap: DrumClap
var _drum_rim: DrumRim
var _drum_hat: DrumHat
var _kick_player: AudioStreamPlayer

# Last N seconds of a challenge: kick doubles to 2/sec for intensity ramp.
const FINAL_COUNTDOWN_SECONDS := 10

# Arcade backing stays silent until the first challenge tick.
var _challenge_tick_received: bool = false

# Melody-bus low-pass filter. Toggled on/off with lofi theme.
const MELODY_LOWPASS_CUTOFF := 3000.0
var _melody_lowpass_effect_idx: int = -1

# ── Lofi drum system ─────────────────────────────────────────────────
# Player drops: random pick from snare/clap/rim. Autodropper kicks cycle;
# advanced autodropper hats cycle and fire offbeat (ADVANCED_DRUM_OFFSET after
# the tick).
const DRUM_POOL_PLAYER_VOLUME_DB := -2.0
const DRUM_POOL_KICK_VOLUME_DB := 0.0
const DRUM_POOL_HAT_VOLUME_DB := -6.0
const DRUM_RAPID_FIRE_WINDOW := 0.25
const DRUM_RAPID_FIRE_ATTENUATION_DB := -6.0
const ADVANCED_DRUM_OFFSET := 0.75  # half of default 1.5s tick

var _player_drum_players: Array[AudioStreamPlayer] = []
var _kick_drum_players: Array[AudioStreamPlayer] = []
var _hat_drum_players: Array[AudioStreamPlayer] = []
var _kick_rotation_idx: int = 0
var _hat_rotation_idx: int = 0
var _last_player_drum_time: float = -999.0

var _melody_bus_idx: int = -1
var _drones_bus_idx: int = -1
var _click_bus_idx: int = -1
var _ambient_bus_idx: int = -1


func _ready() -> void:
	# ── Legacy sound pools ───────────────────────────────────────────
	var pool_overrides := {&"coin_flip": MAX_BUCKET_SOUNDS}
	for sound_name in _sounds:
		_pools[sound_name] = []
		_indices[sound_name] = 0
		var size: int = pool_overrides.get(sound_name, POOL_SIZE)
		for i in size:
			var player := AudioStreamPlayer.new()
			player.stream = _sounds[sound_name]
			player.bus = &"Master"
			add_child(player)
			_pools[sound_name].append(player)

	# ── Audio buses ──────────────────────────────────────────────────
	_setup_buses()

	# ── Instruments ─────────────────────────────────────────────────
	_harp = Harp.new()
	_triangle = Triangle.new()
	_arcade_kick = ArcadeKick.new()
	_click = Click.new()
	_drum_kick_deep = DrumKick.new(60.0, 0.22)
	_drum_kick_thin = DrumKick.new(100.0, 0.09)
	_drum_kick_bass = DrumKick.new(40.0, 0.3)
	_drum_snare = DrumSnare.new(180.0, 0.18)
	_drum_clap = DrumClap.new(0.2)
	_drum_rim = DrumRim.new(400.0, 0.08)
	_drum_hat = DrumHat.new(6000.0, 0.05)

	# Placeholder cello/chime streams — legacy pools, unused by active paths.
	var cello_stream := _generate_tone(196.0, 0.8)      # G3
	var chime_stream := _generate_chime(784.0, 0.6)      # G5 + shimmer
	var click_stream: AudioStream = _click.resolve(0.0).stream

	# DEPRECATED — ambient pad streams per board (4-note stacks of each chord).
	_ambient_pad_streams[Enums.BoardType.GOLD] = _generate_ambient_pad(4.0, 44100,
		[130.81, 164.81, 196.00, 246.94])  # Cmaj7
	_ambient_pad_streams[Enums.BoardType.ORANGE] = _generate_ambient_pad(4.0, 44100,
		[98.00, 123.47, 146.83, 174.61])   # G7
	_ambient_pad_streams[Enums.BoardType.RED] = _generate_ambient_pad(4.0, 44100,
		[110.00, 130.81, 164.81, 196.00])  # Am7

	# Zen default drone stream. Lofi swaps to _piano_drone_stream per-play.
	_sine_drone_stream = _generate_ambient_pad(2.0, 44100, [262.0, 392.0])

	_kick_player = AudioStreamPlayer.new()
	_kick_player.stream = _arcade_kick.resolve(0.0).stream
	_kick_player.bus = &"Melody"
	_kick_player.volume_db = -4.0
	add_child(_kick_player)

	# ── Musical pools ───────────────────────────────────────────────
	for i in MELODY_POOL_SIZE:
		var cello := AudioStreamPlayer.new()
		cello.stream = cello_stream
		cello.bus = &"Melody"
		cello.volume_db = BUCKET_VOLUME_DB
		add_child(cello)
		_cello_pool.append(cello)

		var chime := AudioStreamPlayer.new()
		chime.stream = chime_stream
		chime.bus = &"Melody"
		chime.volume_db = PEG_SPARKLE_VOLUME_DB
		add_child(chime)
		_chime_pool.append(chime)

	for i in CLICK_POOL_SIZE:
		var click := AudioStreamPlayer.new()
		click.stream = click_stream
		click.bus = &"Click"
		click.volume_db = PEG_CLICK_VOLUME_DB
		add_child(click)
		_click_pool.append(click)

	# ── Ambient pad players ──────────────────────────────────────────
	var initial_pad: AudioStreamWAV = _ambient_pad_streams[Enums.BoardType.GOLD]
	_ambient_a = AudioStreamPlayer.new()
	_ambient_a.stream = initial_pad
	_ambient_a.bus = &"Ambient"
	_ambient_a.volume_db = -80.0
	add_child(_ambient_a)

	_ambient_b = AudioStreamPlayer.new()
	_ambient_b.stream = initial_pad
	_ambient_b.bus = &"Ambient"
	_ambient_b.volume_db = -80.0
	add_child(_ambient_b)

	_ambient_active = _ambient_a

	# ── Bucket drone pool ───────────────────────────────────────────
	# Stream is (re)assigned per-play via instrument.resolve() in play_bucket.
	for i in BUCKET_DRONE_POOL_SIZE:
		var drone := AudioStreamPlayer.new()
		drone.stream = _sine_drone_stream
		drone.bus = &"Drones"
		drone.volume_db = -80.0
		add_child(drone)
		_drone_pool.append(drone)
		_drone_free.append(i)

	# ── Lofi drum pools ─────────────────────────────────────────────
	for inst: Instrument in [_drum_snare, _drum_clap, _drum_rim]:
		var p := AudioStreamPlayer.new()
		p.stream = inst.resolve(0.0).stream
		p.bus = &"Click"
		p.volume_db = DRUM_POOL_PLAYER_VOLUME_DB
		add_child(p)
		_player_drum_players.append(p)

	for inst: Instrument in [_drum_kick_deep, _drum_kick_thin]:
		var p := AudioStreamPlayer.new()
		p.stream = inst.resolve(0.0).stream
		p.bus = &"Click"
		p.volume_db = DRUM_POOL_KICK_VOLUME_DB
		add_child(p)
		_kick_drum_players.append(p)

	for inst: Instrument in [_drum_hat]:
		var p := AudioStreamPlayer.new()
		p.stream = inst.resolve(0.0).stream
		p.bus = &"Click"
		p.volume_db = DRUM_POOL_HAT_VOLUME_DB
		add_child(p)
		_hat_drum_players.append(p)

	# ── Sequencer players (melody + drum-layer dispatch) ────────────
	_melody_player = AudioStreamPlayer.new()
	_melody_player.bus = &"Melody"
	_melody_player.volume_db = BUCKET_VOLUME_DB
	add_child(_melody_player)

	for i in DRUM_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"Click"
		p.volume_db = 0.0
		add_child(p)
		_drum_seq_pool.append(p)

	# call_deferred so ThemeProvider autoload is fully ready.
	ThemeProvider.theme_changed.connect(_on_theme_changed)
	_on_theme_changed.call_deferred()

	ChallengeManager.tick.connect(_on_challenge_tick)
	_on_theme_swap.call_deferred()

	set_process(true)


func _process(delta: float) -> void:
	var has_activity: bool = _activity_detected or _active_coin_count > 0
	if has_activity:
		_idle_timer = 0.0
		_activity_detected = false
		if not _ambient_fading_in:
			_fade_in_ambient()
	else:
		_idle_timer += delta
		if _idle_timer >= AMBIENT_IDLE_TIMEOUT and _ambient_fading_in:
			_fade_out_ambient()

	_tick_harmonic_rhythm(delta, has_activity)
	_tick_beat_grid(delta)
	_pump_bucket_queue()
	_tick_pattern(delta)
	_tick_sequencer(delta)
	_update_bucket_drones(delta)


## Advances the chord index through theme.progression while there's activity.
## Idle > CHORD_IDLE_RESET resets to the root chord; a whole chord without
## sparkles also resets (board too quiet to sustain the progression).
func _tick_harmonic_rhythm(delta: float, has_activity: bool) -> void:
	var prog: Array = _theme_progression()
	if prog.is_empty():
		return

	if has_activity:
		_chord_idle_timer = 0.0
		_chord_timer -= delta
		if _chord_timer <= 0.0:
			# Themes with a melody self-sustain the progression; harp-mode
			# themes depend on peg sparkles to keep the chord cycling.
			var has_melody: bool = ThemeProvider.theme \
					and ThemeProvider.theme.melody_sequence.size() > 0
			if not has_melody and not _chord_had_sparkle:
				_reset_harmonic_state()
			elif prog.size() > 1:
				_chord_index = (_chord_index + 1) % prog.size()
				_motif_position = 0
			_chord_timer = _theme_chord_duration()
			_chord_had_sparkle = false
			_handle_chord_advance()
	else:
		_chord_idle_timer += delta
		if _chord_idle_timer >= CHORD_IDLE_RESET:
			_chord_idle_timer = 0.0
			_reset_harmonic_state()


func _reset_harmonic_state() -> void:
	_chord_index = 0
	_chord_timer = _theme_chord_duration()
	_motif_position = 0
	_beat_phase = 0.0
	_beat_armed = true
	_chord_had_sparkle = false
	# Idle reset counts as a chord change for visuals (buckets need to fade).
	_handle_chord_advance()


## Theme swap: fade lingering drones, reset chord state, rebind kick stream.
func _on_theme_swap() -> void:
	_chord_index = 0
	_motif_position = 0
	_beat_phase = 0.0
	_beat_armed = true
	_challenge_tick_received = false
	_chord_timer = _theme_chord_duration()
	_beat_period = _autodrop_interval / float(BEATS_PER_BAR)
	_fade_all_drones(1.0)
	_stop_sequencer()
	var kick: Instrument = _instrument_for(_theme_kick_type())
	if kick:
		_kick_player.stream = kick.resolve(0.0).stream


## Maps the Instrument.Type enum to the singleton instance. null = SILENT.
func _instrument_for(type: int) -> Instrument:
	match type:
		Instrument.Type.HARP: return _harp
		Instrument.Type.TRIANGLE: return _triangle
		Instrument.Type.ARCADE_KICK: return _arcade_kick
		Instrument.Type.DRUM_KICK_DEEP: return _drum_kick_deep
		Instrument.Type.DRUM_KICK_THIN: return _drum_kick_thin
		Instrument.Type.DRUM_SNARE: return _drum_snare
		Instrument.Type.DRUM_CLAP: return _drum_clap
		Instrument.Type.DRUM_RIM: return _drum_rim
		Instrument.Type.DRUM_HAT: return _drum_hat
		Instrument.Type.DRUM_KICK_BASS: return _drum_kick_bass
	return null


func _theme_progression() -> Array:
	if ThemeProvider and ThemeProvider.theme:
		return ThemeProvider.theme.progression
	return []


func _theme_chord_duration() -> float:
	if ThemeProvider and ThemeProvider.theme:
		return ThemeProvider.theme.chord_duration
	return 6.0


func _theme_bucket_type() -> int:
	if ThemeProvider and ThemeProvider.theme:
		return ThemeProvider.theme.bucket_instrument
	return Instrument.Type.SILENT


func _theme_kick_type() -> int:
	if ThemeProvider and ThemeProvider.theme:
		return ThemeProvider.theme.kick_instrument
	return Instrument.Type.SILENT


func _theme_pattern() -> String:
	if not ThemeProvider or not ThemeProvider.theme:
		return ""
	return ThemeProvider.theme.arpeggio_pattern


func _fade_all_drones(duration: float) -> void:
	for drone_key in _active_drones.keys():
		var drone: Dictionary = _active_drones[drone_key]
		_fade_drone(int(drone["idx"]), duration)
	_active_drones.clear()


func _fade_drone(idx: int, duration: float) -> void:
	_kill_fade_tween(idx)
	var player: AudioStreamPlayer = _drone_pool[idx]
	var tween := create_tween()
	# EASE_OUT matches loudness perception (drop fast, trail off slowly).
	# Bucket visual fades use EASE_IN — the asymmetry is intentional.
	tween.tween_property(player, "volume_db", -80.0, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_finish_drone_fade.bind(idx))
	_drone_fade_tweens[idx] = tween


## Kill before reassigning a pool slot so an in-flight fade can't keep driving
## the new drone's volume_db.
func _kill_fade_tween(idx: int) -> void:
	var tween: Tween = _drone_fade_tweens.get(idx)
	if tween and tween.is_valid():
		tween.kill()
	_drone_fade_tweens.erase(idx)


## dB equivalent of VOICE_ATTENUATION_RATIO^N.
func _voice_attenuation_db(voice_count: int) -> float:
	return 20.0 * log(pow(VOICE_ATTENUATION_RATIO, voice_count)) / log(10.0)


func _count_drones_of_type(is_advanced: bool) -> int:
	var count: int = 0
	for drone_key in _active_drones:
		var drone: Dictionary = _active_drones[drone_key]
		if drone["state"] == DroneState.SPARKLE:
			continue
		if drone.get("is_advanced", false) == is_advanced:
			count += 1
	return count


## Factory for `_active_drones` entries — centralized so field shape can't
## drift per-site. Sparkle allocations get is_advanced=false by default.
func _make_drone_entry(idx: int, timer: float, degree: int, octave_mult: float, state: int, is_advanced: bool = false) -> Dictionary:
	return {
		"idx": idx,
		"timer": timer,
		"degree": degree,
		"octave_mult": octave_mult,
		"state": state,
		"is_advanced": is_advanced,
		"created_at": Time.get_ticks_msec(),
	}


## Eviction priority: LINGERING (trailing) > SPARKLE (decorative) > ACTIVE
## (melody in current chord). Higher = evict first.
func _eviction_priority(state: int) -> int:
	match state:
		DroneState.LINGERING: return 2
		DroneState.SPARKLE: return 1
		DroneState.ACTIVE: return 0
		_: return 0


## Per-coin-type voice cap. NOTE: chord advances can flip many ACTIVE→LINGERING
## at once and transiently exceed the cap — the Drones-bus compressor handles
## that burst; the cap bites on the next allocation.
func _evict_oldest_drone_if_full(is_advanced: bool) -> void:
	var cap: int = MAX_ADVANCED_DRONES if is_advanced else MAX_NORMAL_DRONES
	if _count_drones_of_type(is_advanced) < cap:
		return
	var victim_key: String = ""
	var victim_priority: int = -1
	var victim_age: int = -1  # higher = older
	var now: int = Time.get_ticks_msec()
	for drone_key in _active_drones:
		var drone: Dictionary = _active_drones[drone_key]
		if drone["state"] == DroneState.SPARKLE:
			continue
		if drone.get("is_advanced", false) != is_advanced:
			continue
		var priority: int = _eviction_priority(drone["state"])
		var age: int = now - int(drone.get("created_at", now))
		if priority > victim_priority or (priority == victim_priority and age > victim_age):
			victim_priority = priority
			victim_age = age
			victim_key = drone_key
	if victim_key == "":
		return
	var victim: Dictionary = _active_drones[victim_key]
	var fade_duration: float = 0.4
	if ThemeProvider and ThemeProvider.theme:
		fade_duration = ThemeProvider.theme.eviction_fade_duration
	# Erase first so fade-tween callbacks can't see a half-dead entry.
	_active_drones.erase(victim_key)
	_fade_drone(int(victim["idx"]), fade_duration)


func _finish_drone_fade(idx: int) -> void:
	var player: AudioStreamPlayer = _drone_pool[idx]
	player.stop()
	_drone_fade_tweens.erase(idx)
	if not _drone_free.has(idx):
		_drone_free.append(idx)


func get_time_until_next_chord() -> float:
	return _chord_timer


## Total chord length from the active theme.
func get_chord_duration() -> float:
	return _theme_chord_duration()


## 0..1 position within the current chord. Global — all readers see the same
## value at the same moment, so visual pulses stay in sync across buckets.
func get_chord_phase() -> float:
	var duration: float = get_chord_duration()
	if duration <= 0.0:
		return 0.0
	return clampf(1.0 - (_chord_timer / duration), 0.0, 1.0)


## Chord advance is a VISUAL event: emits chord_changed so buckets revert to
## faded, and flips ACTIVE→LINGERING so the activation gate no longer
## suppresses re-hits. Does NOT fade audio — lingering drones ring via their
## natural decay until a new coin hands off (_fade_lingering_drones) or the
## synth sample ends (_update_bucket_drones releases the slot).
func _handle_chord_advance() -> void:
	for drone_key in _active_drones.keys():
		var drone: Dictionary = _active_drones[drone_key]
		if drone["state"] == DroneState.ACTIVE:
			drone["state"] = DroneState.LINGERING
			drone["timer"] = Harp.DECAY_SECONDS
	_bucket_queue.clear()
	_chord_activated_buckets.clear()
	_last_bucket_play_time = -999.0
	_activated_buckets_order.clear()
	_unplayed_buckets.clear()
	_pattern_slot_idx = -1
	_pattern_slot_timer = 0.0
	# Drum tiers are time-based (one chord_duration from activation) and
	# NOT cleared here — they persist past chord boundaries until expiration.
	chord_changed.emit(_chord_index)


## New coin landing after chord advance — hands off from the old chord's tail.
## Audio fade (theme.linger_fade_duration) is longer than the visual fade.
func _fade_lingering_drones() -> void:
	if _active_drones.is_empty():
		return
	var fade_duration: float = 2.5
	if ThemeProvider and ThemeProvider.theme:
		fade_duration = ThemeProvider.theme.linger_fade_duration
	var keys: Array = []
	for drone_key in _active_drones.keys():
		if _active_drones[drone_key]["state"] == DroneState.LINGERING:
			keys.append(drone_key)
	for drone_key in keys:
		var drone: Dictionary = _active_drones[drone_key]
		_fade_drone(int(drone["idx"]), fade_duration)
		_active_drones.erase(drone_key)


## Called every second by ChallengeManager.tick. Starts the sequencer on
## the first tick. Phase-locks the beat grid. Fires the kick if the theme
## has one; final 10s doubles to 2/sec.
func _on_challenge_tick(seconds_remaining: int) -> void:
	# Start sequencer on first tick (which fires on first coin drop).
	if not _sequencer_running and _theme_drum_instruments().size() > 0:
		_sequencer_running = true
		_global_slot_idx = 0
		_melody_idx = 0
		_slot_timer = SLOT_DURATION
		_play_slot()

	_challenge_tick_received = true
	_beat_phase = 0.0
	_beat_armed = true

	if _theme_kick_type() != Instrument.Type.SILENT:
		_kick_player.play()
		if seconds_remaining <= FINAL_COUNTDOWN_SECONDS:
			get_tree().create_timer(0.5).timeout.connect(_kick_player.play, CONNECT_ONE_SHOT)


func _tick_beat_grid(delta: float) -> void:
	_beat_phase += delta
	while _beat_phase >= _beat_period:
		_beat_phase -= _beat_period
		_motif_position += 1
		_beat_armed = true


# ── Public API: musical sounds ───────────────────────────────────────

## Register a bucket hit. Returns true if the caller should light up the
## bucket visually. Three modes, selected by theme data:
##   1. Drum-layer (drum_instruments non-empty): activate the tier's drum
##      pattern; audio waits for the tier's next beat slot.
##   2. Arpeggio (arpeggio_pattern non-empty): register + first-hit-immediate.
##   3. Queue (default): BUCKET_WAIT-spaced dispatch.
func request_bucket_play(board_type: Enums.BoardType, bucket_idx: int, degree: int, is_advanced: bool) -> bool:
	if board_type != _active_board:
		return false
	_activity_detected = true

	# Drum-layer mode: activate the tier. Tier stays active for one chord
	# duration from this activation.
	if _theme_drum_instruments().size() > 0:
		var tier: int = degree
		if tier < _theme_drum_instruments().size():
			var now: float = Time.get_ticks_msec() / 1000.0
			_active_drum_tiers[tier] = now + _theme_chord_duration()
		return true

	# Arpeggio / queue modes: per-bucket-per-chord dedup.
	var dedup_key: String = str(bucket_idx) + "_" + ("A" if is_advanced else "N")
	if dedup_key in _chord_activated_buckets:
		return false
	_chord_activated_buckets[dedup_key] = true

	var entry: Dictionary = {
		"bucket_idx": bucket_idx,
		"degree": degree,
		"is_advanced": is_advanced,
	}

	if _theme_pattern().length() > 0:
		_activated_buckets_order.push_back(entry)
		if _activated_buckets_order.size() == 1:
			_play_bucket_now(bucket_idx, degree, is_advanced)
		else:
			_unplayed_buckets.push_back(entry)
		return true

	# Queue mode.
	var now: float = Time.get_ticks_msec() / 1000.0
	if _bucket_queue.is_empty() and now - _last_bucket_play_time >= BUCKET_WAIT:
		_play_bucket_now(bucket_idx, degree, is_advanced)
		_last_bucket_play_time = now
	else:
		_bucket_queue.push_back(entry)
	return true


## Dequeues pending bucket plays spaced by BUCKET_WAIT. Called from _process.
func _pump_bucket_queue() -> void:
	if _bucket_queue.is_empty():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	while not _bucket_queue.is_empty() and now - _last_bucket_play_time >= BUCKET_WAIT:
		var entry: Dictionary = _bucket_queue.pop_front()
		_play_bucket_now(int(entry["bucket_idx"]), int(entry["degree"]), bool(entry["is_advanced"]))
		_last_bucket_play_time = now


## Pattern mode: advance the slot timer, pick and play on "x" slots, rest on
## "-" slots. No-op if the active theme has no pattern (queue mode).
func _tick_pattern(delta: float) -> void:
	var pattern: String = _theme_pattern()
	if pattern.length() == 0:
		return
	var slot_duration: float = _theme_chord_duration() / float(pattern.length())
	if slot_duration <= 0.0:
		return
	_pattern_slot_timer -= delta
	while _pattern_slot_timer <= 0.0:
		_pattern_slot_idx = (_pattern_slot_idx + 1) % pattern.length()
		_pattern_slot_timer += slot_duration
		if pattern[_pattern_slot_idx] == "x":
			_play_pattern_slot()


## Picks one entry from the activation pool. FIFO through _unplayed_buckets
## first (every newly activated bucket gets a guaranteed play), then falls
## back to random across the whole pool.
func _play_pattern_slot() -> void:
	var entry: Dictionary
	if not _unplayed_buckets.is_empty():
		entry = _unplayed_buckets.pop_front()
	elif not _activated_buckets_order.is_empty():
		entry = _activated_buckets_order.pick_random()
	else:
		return
	_play_bucket_now(int(entry["bucket_idx"]), int(entry["degree"]), bool(entry["is_advanced"]))


## Sequencer: drives background melody + drum-layer dispatch. Ticks at
## SLOT_DURATION (0.25s). Starts on first challenge tick, stops on theme swap.
func _tick_sequencer(delta: float) -> void:
	if not _sequencer_running:
		return
	_slot_timer -= delta
	while _slot_timer <= 0.0:
		_global_slot_idx += 1
		_slot_timer += SLOT_DURATION
		_play_slot()


func _play_slot() -> void:
	if not ThemeProvider or not ThemeProvider.theme:
		return
	var theme: VisualTheme = ThemeProvider.theme

	# Melody
	var seq: PackedInt32Array = theme.melody_sequence
	if seq.size() > 0:
		var midi: int = seq[_melody_idx % seq.size()]
		_melody_idx += 1
		if midi >= 0:
			var pitch_mult: float = pow(2.0, float(midi - 60) / 12.0)
			var sp: Dictionary = _triangle.resolve(pitch_mult)
			_melody_player.stream = sp["stream"]
			_melody_player.pitch_scale = sp["pitch_scale"]
			_melody_player.volume_db = BUCKET_VOLUME_DB + theme.melody_volume_offset
			_melody_player.play()

	# Drum layers — prune expired tiers, play active ones on "x" slots.
	var now: float = Time.get_ticks_msec() / 1000.0
	var expired: Array[int] = []
	for tier: int in _active_drum_tiers:
		if _active_drum_tiers[tier] <= now:
			expired.append(tier)
			continue
		if tier >= theme.drum_patterns.size():
			continue
		var pattern: String = theme.drum_patterns[tier]
		if pattern.length() == 0:
			continue
		var slot_in_pattern: int = _global_slot_idx % pattern.length()
		if pattern[slot_in_pattern] == "x":
			var inst_type: int = theme.drum_instruments[tier] if tier < theme.drum_instruments.size() else 0
			var inst: Instrument = _instrument_for(inst_type)
			if inst:
				var vol_offset: float = theme.drum_volumes[tier] if tier < theme.drum_volumes.size() else 0.0
				_play_drum_hit(inst, vol_offset)
			drum_tier_fired.emit(tier)
	for tier: int in expired:
		_active_drum_tiers.erase(tier)
		drum_tier_expired.emit(tier)



func _play_drum_hit(inst: Instrument, volume_offset: float) -> void:
	var sp: Dictionary = inst.resolve(0.0)
	var player: AudioStreamPlayer = _drum_seq_pool[_drum_seq_idx]
	_drum_seq_idx = (_drum_seq_idx + 1) % _drum_seq_pool.size()
	player.stream = sp["stream"]
	player.pitch_scale = sp["pitch_scale"]
	player.volume_db = DRUM_POOL_PLAYER_VOLUME_DB + volume_offset
	player.play()


func _stop_sequencer() -> void:
	_sequencer_running = false
	_global_slot_idx = 0
	_slot_timer = 0.0
	_melody_idx = 0
	_active_drum_tiers.clear()
	_melody_player.stop()


func _theme_drum_instruments() -> PackedInt32Array:
	if not ThemeProvider or not ThemeProvider.theme:
		return PackedInt32Array()
	return ThemeProvider.theme.drum_instruments


## Allocates a drone slot for a bucket hit and starts playing. Drone key is
## per-bucket so mirror buckets sharing a pitch get independent entries.
## Re-picks of the same bucket (pattern repeats) free the old slot first so
## each attack is distinct.
func _play_bucket_now(bucket_idx: int, degree: int, is_advanced: bool) -> void:
	var instrument: Instrument = _instrument_for(_theme_bucket_type())
	if not instrument or _theme_progression().is_empty():
		return

	var key: String = ("A_" if is_advanced else "N_") + str(bucket_idx)

	# Re-attack: free any existing drone for this key before reallocating.
	if key in _active_drones:
		var old_idx: int = int(_active_drones[key]["idx"])
		_kill_fade_tween(old_idx)
		_drone_pool[old_idx].stop()
		if not _drone_free.has(old_idx):
			_drone_free.append(old_idx)
		_active_drones.erase(key)

	var octave_mult: float = 0.25 if is_advanced else 0.5
	var pitch: float = _get_pitch_scale(degree) * octave_mult
	var target_volume: float = BUCKET_VOLUME_DB + (4.0 if is_advanced else 0.0)
	var sp: Dictionary = instrument.resolve(pitch)

	# New coin hands off from the previous chord's lingering drones.
	_fade_lingering_drones()

	# Eviction runs AFTER linger-clear so freed slots are counted first.
	_evict_oldest_drone_if_full(is_advanced)
	if _drone_free.is_empty():
		return
	var voice_count: int = _count_drones_of_type(is_advanced)
	var voice_attenuation_db: float = _voice_attenuation_db(voice_count)
	var idx: int = _drone_free.pop_back()
	_kill_fade_tween(idx)
	var player: AudioStreamPlayer = _drone_pool[idx]
	player.stream = sp["stream"]
	player.pitch_scale = _apply_tape_wobble(sp["pitch_scale"])
	player.volume_db = target_volume + voice_attenuation_db
	player.play()
	var tail: float = maxf(_chord_timer, MIN_BUCKET_RING_SECONDS)
	_active_drones[key] = _make_drone_entry(idx, tail, degree, octave_mult, DroneState.ACTIVE, is_advanced)


## DISABLED — sparkle audio clashes with the chord-gated bucket layer. Peg
## ring VFX still fires via should_sparkle/_beat_armed. A follow-up feature
## will redesign the sparkle voice to layer on top of the bucket melody.
func play_peg_sparkle(_board_type: Enums.BoardType) -> void:
	return


func play_peg_click(board_type: Enums.BoardType) -> void:
	if board_type != _active_board:
		return
	_activity_detected = true
	var player: AudioStreamPlayer = _click_pool[_click_idx]
	_click_idx = (_click_idx + 1) % _click_pool.size()
	player.pitch_scale = randf_range(0.8, 1.2)
	player.play()


func set_active_board(board_type: Enums.BoardType) -> void:
	if board_type == _active_board:
		return
	_active_board = board_type
	_crossfade_ambient(board_type)


## Keeps the ambient pad alive for the whole descent even on large boards
## where the 2s idle timeout would otherwise fade between sparkles.
func on_coin_dropped() -> void:
	_active_coin_count += 1
	_activity_detected = true


func on_coin_landed() -> void:
	_active_coin_count = maxi(0, _active_coin_count - 1)


## DISABLED — drums parked while harp timbre is being developed. Pools,
## buses, and tick scheduling stay intact for easy re-enable.
func play_manual_drop_drum(board_type: Enums.BoardType) -> void:
	return
	if board_type != _active_board:
		return
	if _player_drum_players.is_empty():
		return

	var now: float = Time.get_ticks_msec() / 1000.0
	var rapid: bool = (now - _last_player_drum_time) < DRUM_RAPID_FIRE_WINDOW
	_last_player_drum_time = now

	var player: AudioStreamPlayer = _player_drum_players[randi() % _player_drum_players.size()]
	player.pitch_scale = _get_ambient_pitch(board_type)
	player.volume_db = DRUM_POOL_PLAYER_VOLUME_DB + (DRUM_RAPID_FIRE_ATTENUATION_DB if rapid else 0.0)
	player.play()


## DISABLED — see play_manual_drop_drum. Normal autodropper → kick on the
## beat; advanced → hat on the offbeat (ADVANCED_DRUM_OFFSET later). Rotates
## through the pool in order.
func play_autodropper_drum(board_type: Enums.BoardType, is_advanced: bool) -> void:
	return
	if board_type != _active_board:
		return

	if is_advanced:
		get_tree().create_timer(ADVANCED_DRUM_OFFSET).timeout.connect(
			_play_advanced_drum_now.bind(board_type))
	else:
		_play_kick_now(board_type)


func _play_kick_now(board_type: Enums.BoardType) -> void:
	if _kick_drum_players.is_empty():
		return
	var player: AudioStreamPlayer = _kick_drum_players[_kick_rotation_idx]
	_kick_rotation_idx = (_kick_rotation_idx + 1) % _kick_drum_players.size()
	player.pitch_scale = _get_ambient_pitch(board_type)
	player.play()


func _play_advanced_drum_now(board_type: Enums.BoardType) -> void:
	# Re-check active board — player may have switched during the delay.
	if board_type != _active_board:
		return
	if _hat_drum_players.is_empty():
		return
	var player: AudioStreamPlayer = _hat_drum_players[_hat_rotation_idx]
	_hat_rotation_idx = (_hat_rotation_idx + 1) % _hat_drum_players.size()
	player.pitch_scale = _get_ambient_pitch(board_type)
	player.play()


# ── Legacy API (kept for backward compatibility) ─────────────────────

func play(sound_name: StringName, pitch: float = 0.0, max_duration: float = 0.0) -> void:
	if sound_name not in _pools:
		return
	var pool: Array = _pools[sound_name]
	var idx: int = _indices[sound_name]
	var player: AudioStreamPlayer = pool[idx]
	_indices[sound_name] = (idx + 1) % pool.size()

	if pitch <= 0.0:
		pitch = randf_range(0.9, 1.1)
	player.pitch_scale = pitch
	player.play()

	if max_duration > 0.0:
		get_tree().create_timer(max_duration).timeout.connect(func():
			if player.playing:
				player.stop()
		)


func play_prestige(play_duration: float = 3.0, fade_duration: float = 2.0) -> void:
	pass


# ── Musical internals ────────────────────────────────────────────────

func _get_pitch_scale(scale_degree: int) -> float:
	var entry: Dictionary = _current_chord_entry()
	if entry.is_empty():
		return 1.0
	var chord: Array = entry["chord"]
	var semitones: int = chord[scale_degree % chord.size()] + int(entry["root"])
	return pow(2.0, semitones / 12.0)


## Current chord entry from theme.progression. Empty dict if no progression.
func _current_chord_entry() -> Dictionary:
	var prog: Array = _theme_progression()
	if prog.is_empty():
		return {}
	return prog[_chord_index % prog.size()]


## DISABLED — tape wobble added "old recording" character that fought the
## clean harp timbre. Kept for potential revival.
func _apply_tape_wobble(pitch: float) -> float:
	return pitch
	var t: float = Time.get_ticks_msec() / 1000.0
	return pitch * (1.0 + sin(t * 3.0) * 0.004)


func is_active_board(board_type: Enums.BoardType) -> bool:
	return board_type == _active_board


## Beat-grid sparkle gate. True at most once per beat slot — the first peg
## hit while the beat is armed AND the motif position has a real note (not -1).
## Rests consume the beat silently. Always flags _chord_had_sparkle so a
## rest-heavy chord isn't mistaken for "no activity."
func should_sparkle(board_type: Enums.BoardType) -> bool:
	if board_type != _active_board:
		return false
	if not _beat_armed:
		return false
	_beat_armed = false
	var motif: Array = _current_chord_entry().get("motif", [0])
	var note: int = motif[_motif_position % motif.size()]
	_chord_had_sparkle = true
	return note >= 0


## Snap the beat grid to this autodropper tick. Beat period is derived from
## the interval so sparkle cadence tracks the drum (not hardcoded).
func notify_autodropper_beat(interval: float) -> void:
	_autodrop_interval = interval
	_beat_period = interval / float(BEATS_PER_BAR)
	_beat_phase = 0.0
	_motif_position += 1
	_beat_armed = true


# ── DEPRECATED: Ambient pad (unused; kept for potential revival) ─────
#
# Per-board sustained harmonic beds, crossfaded on board switch and auto-
# faded during idle. `_fade_in_ambient` early-returns so no audible pad ever
# reaches the mixer. Kept because the planned audio refactor may resurrect
# the pad as its own instrument role.
#
# Full removal would also delete: the `AMBIENT_*` constants, the
# `_ambient_pad_streams` dict + its init in `_ready`, the `_ambient_a` /
# `_ambient_b` / `_ambient_active` players + their init, the idle-timer hooks
# in `_process` that call the two fade helpers, the `_crossfade_ambient` call
# in `_on_board_switched`, and the `_generate_ambient_pad` synth.
# NOTE: `_generate_ambient_pad` is also reused to build `_sine_drone_stream`
# for the bucket drone pool — if you remove it, port that one call to its
# own sine-synth helper first.
# NOTE: `_get_ambient_pitch` lives in this section by legacy but is still
# used by the drum layer to match board chords — do NOT remove with the pad.

func _fade_in_ambient() -> void:
	# Over-dense with drums + bucket drones. Re-enable by removing this return.
	return
	_ambient_fading_in = true
	if not _ambient_active.playing:
		_ambient_active.stream = _ambient_pad_streams.get(_active_board, _ambient_pad_streams[Enums.BoardType.GOLD])
		_ambient_active.pitch_scale = 1.0
		_ambient_active.play()
	var tween := create_tween()
	tween.tween_property(_ambient_active, "volume_db", AMBIENT_VOLUME_DB, AMBIENT_FADE_DURATION)


func _fade_out_ambient() -> void:
	_ambient_fading_in = false
	var player := _ambient_active
	var tween := create_tween()
	tween.tween_property(player, "volume_db", -80.0, AMBIENT_FADE_DURATION * 1.5)
	tween.tween_callback(player.stop)


func _crossfade_ambient(board_type: Enums.BoardType) -> void:
	var old_player := _ambient_active
	var new_player := _ambient_b if _ambient_active == _ambient_a else _ambient_a
	_ambient_active = new_player

	if old_player.playing:
		var out_tween := create_tween()
		out_tween.tween_property(old_player, "volume_db", -80.0, AMBIENT_FADE_DURATION)
		out_tween.tween_callback(old_player.stop)

	if _ambient_fading_in:
		new_player.stream = _ambient_pad_streams.get(board_type, _ambient_pad_streams[Enums.BoardType.GOLD])
		new_player.pitch_scale = 1.0
		new_player.volume_db = -80.0
		new_player.play()
		var in_tween := create_tween()
		in_tween.tween_property(new_player, "volume_db", AMBIENT_VOLUME_DB, AMBIENT_FADE_DURATION)


func _update_bucket_drones(delta: float) -> void:
	var expired: Array[String] = []
	for drone_key: String in _active_drones:
		var drone: Dictionary = _active_drones[drone_key]
		# ACTIVE drones are chord-managed — skip so the timer can't cut them
		# off mid-chord.
		if drone["state"] == DroneState.ACTIVE:
			continue
		drone.timer -= delta
		if drone.timer <= 0.0:
			var player: AudioStreamPlayer = _drone_pool[drone.idx]
			player.volume_db = move_toward(player.volume_db, -80.0, BUCKET_DRONE_FADE_RATE * delta)
			if player.volume_db <= -79.0:
				player.stop()
				_drone_fade_tweens.erase(drone.idx)
				_drone_free.append(drone.idx)
				expired.append(drone_key)
	for key: String in expired:
		_active_drones.erase(key)


## Pitch multiplier for a C4-rooted instrument to match the board's current
## root. Still used by the drum layer (name is legacy — no longer ambient).
func _get_ambient_pitch(_board_type: Enums.BoardType) -> float:
	var entry: Dictionary = _current_chord_entry()
	if entry.is_empty():
		return 1.0
	var semitones: int = int(entry["root"])
	return pow(2.0, semitones / 12.0)


# ── Theme-gated lofi effects ─────────────────────────────────────────

func _on_theme_changed() -> void:
	if not ThemeProvider.theme:
		return

	# Low-pass kept off while the harp is being developed. Re-enable with the
	# lofi gate: `var lofi := ...; set_bus_effect_enabled(..., lofi)`.
	if _melody_bus_idx >= 0 and _melody_lowpass_effect_idx >= 0:
		AudioServer.set_bus_effect_enabled(_melody_bus_idx, _melody_lowpass_effect_idx, false)

	_on_theme_swap()


# ── Audio bus setup ──────────────────────────────────────────────────

func _setup_buses() -> void:
	# Add buses if they don't already exist
	if AudioServer.get_bus_index(&"Melody") < 0:
		_melody_bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_melody_bus_idx, &"Melody")
		AudioServer.set_bus_send(_melody_bus_idx, &"Master")
		# Reverb muted (wet=0) — Godot's built-in reverb fights the dry harp.
		# Re-enable by raising wet (e.g. 0.15–0.25).
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.55
		reverb.wet = 0.0
		reverb.dry = 1.0
		reverb.damping = 0.7
		AudioServer.add_bus_effect(_melody_bus_idx, reverb)
		# Low-pass for lofi warmth — toggled in _on_theme_changed.
		var lowpass := AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = MELODY_LOWPASS_CUTOFF
		lowpass.resonance = 0.5
		AudioServer.add_bus_effect(_melody_bus_idx, lowpass)
		_melody_lowpass_effect_idx = AudioServer.get_bus_effect_count(_melody_bus_idx) - 1
		AudioServer.set_bus_effect_enabled(_melody_bus_idx, _melody_lowpass_effect_idx, false)
	else:
		_melody_bus_idx = AudioServer.get_bus_index(&"Melody")

	if AudioServer.get_bus_index(&"Click") < 0:
		_click_bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_click_bus_idx, &"Click")
		AudioServer.set_bus_send(_click_bus_idx, &"Master")
	else:
		_click_bus_idx = AudioServer.get_bus_index(&"Click")

	if AudioServer.get_bus_index(&"Ambient") < 0:
		_ambient_bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_ambient_bus_idx, &"Ambient")
		AudioServer.set_bus_send(_ambient_bus_idx, &"Master")
	else:
		_ambient_bus_idx = AudioServer.get_bus_index(&"Ambient")

	# Drone-voice bus. Compressor first (tames the dry stack as voice count
	# grows), then reverb. Order matters — reverb-before-comp would pump the
	# tail with every new hit.
	if AudioServer.get_bus_index(&"Drones") < 0:
		_drones_bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_drones_bus_idx, &"Drones")
		AudioServer.set_bus_send(_drones_bus_idx, &"Master")
		var comp := AudioEffectCompressor.new()
		comp.threshold = -18.0
		comp.ratio = 3.0
		comp.attack_us = 10000.0
		comp.release_ms = 500.0
		AudioServer.add_bus_effect(_drones_bus_idx, comp)
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.4
		reverb.damping = 0.5
		reverb.wet = 0.2
		reverb.dry = 0.8
		reverb.hipass = 0.2  # cut muddy buildup on dense stacks
		AudioServer.add_bus_effect(_drones_bus_idx, reverb)
	else:
		_drones_bus_idx = AudioServer.get_bus_index(&"Drones")


# ── Placeholder tone generation ──────────────────────────────────────

func _generate_tone(freq: float, duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var env: float = 1.0
		if t < 0.01:
			env = t / 0.01
		elif t > duration * 0.6:
			env = (duration - t) / (duration * 0.4)
		var value: float = sin(TAU * freq * t) * env * 0.4
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav


func _generate_chime(freq: float, duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var env: float = exp(-t * 5.0)
		var value: float = (sin(TAU * freq * t) * 0.6 + sin(TAU * freq * 3.0 * t) * 0.2) * env * 0.35
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav


func _generate_ambient_pad(duration: float, mix_rate: int = 44100, frequencies: Array = [131.0, 196.0]) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = int(duration * mix_rate)
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	# Integer-Hz frequencies auto-align to zero-crossings at loop boundary.
	# 0.25 Hz amplitude modulation adds a gentle breath so the pad doesn't
	# feel static. Per-voice amplitude scales so the sum doesn't clip.
	var amplitude: float = 0.3 / sqrt(float(frequencies.size()))
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var breath: float = 0.7 + 0.3 * sin(TAU * 0.25 * t)
		var sum: float = 0.0
		for freq: float in frequencies:
			sum += sin(TAU * freq * t)
		var value: float = sum * amplitude * breath
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav


