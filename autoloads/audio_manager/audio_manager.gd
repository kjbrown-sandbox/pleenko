extends Node

# Fires when the chord progression advances. PlinkoBoard listens and fades
# chord-activated buckets back to faded.
signal chord_changed(chord_index: int)

# Fired only on slots where the tier's pattern has an "x" (a drum hit). Rest
# slots ("-") don't emit — the bucket shouldn't pulse when there's no sound.
# PlinkoBoard listens to pulse every bucket at the given distance-from-center.
signal drum_tier_fired(tier: int)

# Fired once when a tier's active lifetime runs out (chord_duration after the
# last activation). PlinkoBoard fades every bucket at that distance back to
# faded. Independent of drum_tier_fired (which emits many times per lifetime).
signal drum_tier_expired(tier: int)


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
var _chord_generation: int = 0  # incremented on chord advance; per-chord attenuation scope
const CHORD_IDLE_RESET := 2.0

# Beat grid: 4/4 derived from the autodropper tick. Beat clock free-runs at
# DEFAULT_AUTODROP_INTERVAL until the first real tick snaps the phase.
const DEFAULT_AUTODROP_INTERVAL := 1.5
const BEATS_PER_BAR := 4

const MELODY_POOL_SIZE := 12
const CLICK_POOL_SIZE := 8
const PEG_CLICK_VOLUME_DB := -18.0
const PEG_SPARKLE_VOLUME_DB := -8.0
const BUCKET_VOLUME_DB := -17.5

var _click_pool: Array[AudioStreamPlayer] = []
var _click_idx: int = 0

var _active_board: Enums.BoardType = Enums.BoardType.GOLD

var _chord_timer: float = 6.0  # overwritten from theme.chord_duration on _ready
var _chord_idle_timer: float = 0.0
var _chord_had_landing: bool = false

var _autodrop_interval: float = DEFAULT_AUTODROP_INTERVAL
var _beat_period: float = DEFAULT_AUTODROP_INTERVAL / BEATS_PER_BAR
var _beat_phase: float = 0.0
var _beat_armed: bool = false
var _motif_position: int = 0

var _active_coin_count: int = 0

# Sparkle state — pegs sparkle only within 100ms of a bucket drone firing.
# Each sparkle walks up the chord from the root, climbing into higher octaves
# across successive bucket fires. Resets on chord advance.
var _last_bucket_fire_ms: float = -1000.0
var _sparkles_this_fire: int = 0
var _sparkle_step: int = 0

# Drone lifecycle:
#   SPARKLE — peg sparkle; timer-decayed by _update_bucket_drones.
#   ACTIVE  — bucket or prestige note; timer-decayed, plays to natural end.
# No voice caps — pool exhaustion is the only limit (graceful silent drop).
enum DroneState { SPARKLE, ACTIVE }

const SPARKLE_VOLUME_DB := -22.0
const SPARKLE_PROXIMITY_MS := 100.0
const MAX_SPARKLES_PER_FIRE := 2

# Per-voice attenuation: voice N plays at VOICE_ATTENUATION_RATIO^(N-1) of
# base amplitude (~2.5 dB drop per added voice at 0.75). The Drones-bus
# compressor is tuned against this curve — retune both together.
const VOICE_ATTENUATION_RATIO := 0.75

const SPARKLE_DRONE_SUSTAIN := 2.5
const BUCKET_DRONE_POOL_SIZE := 24
var _drone_pool: Array[AudioStreamPlayer] = []
var _drone_free: Array[int] = []
var _active_drones: Dictionary = {}  # String key -> { "idx", "timer", "degree", "octave_mult", "state" }
# Keyed by drone pool idx. Killed before a slot is reused so an in-flight fade
# can't keep writing to the new drone's volume_db.
var _drone_fade_tweens: Dictionary = {}

# Prestige audio — ascending maj7 arpeggio from bass to bell at contact.
const PRESTIGE_ARPEGGIO_INTERVAL := 0.125  # seconds between arpeggio notes (real-time)
const PRESTIGE_BASS_VOLUME_DB := -10.0
const PRESTIGE_BELL_VOLUME_DB := -12.0
const PRESTIGE_ARPEGGIO_VOLUME_DB := -14.0
var _silenced: bool = false  # gates all new sounds (prestige, scene transitions)
var _prestige_arpeggio_active: bool = false
var _prestige_arpeggio_step: int = 0
var _prestige_arpeggio_last_ms: int = 0
var _prestige_arpeggio_notes: Array[float] = []  # pre-computed pitch_mult values

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
var _harp_long: HarpLong
var _triangle: Triangle
var _bell: Bell
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
var _melody_lowpass_effect_idx: int = -1

var _melody_bus_idx: int = -1
var _drones_bus_idx: int = -1
var _click_bus_idx: int = -1
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
	# Buses are defined in default_bus_layout.tres (loaded at startup).
	# Adding buses at runtime via AudioServer.add_bus() breaks web audio.
	_melody_bus_idx = AudioServer.get_bus_index(&"Melody")
	if _melody_bus_idx >= 0:
		# Low-pass is the last effect on the Melody bus — see default_bus_layout.tres
		_melody_lowpass_effect_idx = AudioServer.get_bus_effect_count(_melody_bus_idx) - 1
	_click_bus_idx = AudioServer.get_bus_index(&"Click")
	_drones_bus_idx = AudioServer.get_bus_index(&"Drones")

	# ── Instruments ─────────────────────────────────────────────────
	_harp = Harp.new()
	_harp_long = HarpLong.new()
	_triangle = Triangle.new()
	_bell = Bell.new()
	_arcade_kick = ArcadeKick.new()
	_click = Click.new()
	_drum_kick_deep = DrumKick.new(60.0, 0.22)
	_drum_kick_thin = DrumKick.new(100.0, 0.09)
	_drum_kick_bass = DrumKick.new(40.0, 0.3)
	_drum_snare = DrumSnare.new(180.0, 0.18)
	_drum_clap = DrumClap.new(0.2)
	_drum_rim = DrumRim.new(400.0, 0.08)
	_drum_hat = DrumHat.new(6000.0, 0.05)

	var click_stream: AudioStream = _click.resolve(0.0).stream

	# Zen default drone stream.
	_sine_drone_stream = _generate_ambient_pad(2.0, 44100, [262.0, 392.0])

	_kick_player = AudioStreamPlayer.new()
	_kick_player.stream = _arcade_kick.resolve(0.0).stream
	_kick_player.bus = &"Melody"
	_kick_player.volume_db = -4.0
	add_child(_kick_player)

	# ── Click pool ──────────────────────────────────────────────────
	for i in CLICK_POOL_SIZE:
		var click := AudioStreamPlayer.new()
		click.stream = click_stream
		click.bus = &"Click"
		click.volume_db = PEG_CLICK_VOLUME_DB
		add_child(click)
		_click_pool.append(click)

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
	PrestigeManager.prestige_phase_changed.connect(_on_prestige_phase_changed)
	_on_theme_swap.call_deferred()

	set_process(true)


func _process(delta: float) -> void:
	var has_activity: bool = _active_coin_count > 0

	_tick_harmonic_rhythm(delta, has_activity)
	_tick_beat_grid(delta)
	_pump_bucket_queue()
	_tick_pattern(delta)
	_tick_sequencer(delta)
	_update_bucket_drones(delta)
	_tick_prestige_arpeggio()


## Advances the chord index through theme.progression while there's activity.
## Idle > CHORD_IDLE_RESET resets to the root chord; a full chord with no
## bucket landings also resets (board too quiet to sustain the progression).
func _tick_harmonic_rhythm(delta: float, has_activity: bool) -> void:
	var prog: Array = _theme_progression()
	if prog.is_empty():
		return

	if has_activity:
		_chord_idle_timer = 0.0
		_chord_timer -= delta
		if _chord_timer <= 0.0:
			if not _chord_had_landing:
				_reset_harmonic_state()
			elif prog.size() > 1:
				_chord_index = (_chord_index + 1) % prog.size()
				_motif_position = 0
			_chord_timer = _theme_chord_duration()
			_chord_had_landing = false
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
	_chord_had_landing = false
	# Idle reset counts as a chord change for visuals (buckets need to fade).
	_handle_chord_advance()


## Theme swap: hard-stop all drones, reset chord state, rebind kick stream.
func _on_theme_swap() -> void:
	_chord_index = 0
	_motif_position = 0
	_beat_phase = 0.0
	_beat_armed = true
	_challenge_tick_received = false
	_chord_timer = _theme_chord_duration()
	_beat_period = _autodrop_interval / float(BEATS_PER_BAR)
	_hard_stop_all_drones()
	_stop_sequencer()
	var kick: Instrument = _instrument_for(_theme_kick_type())
	if kick:
		_kick_player.stream = kick.resolve(0.0).stream


## Maps the Instrument.Type enum to the singleton instance. null = SILENT.
func _instrument_for(type: int) -> Instrument:
	match type:
		Instrument.Type.HARP: return _harp
		Instrument.Type.TRIANGLE: return _triangle
		Instrument.Type.BELL: return _bell
		Instrument.Type.HARP_LONG: return _harp_long
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


## Immediately stops all drones without fading. Used by theme swaps.
func _hard_stop_all_drones() -> void:
	for drone_key in _active_drones.keys():
		var drone: Dictionary = _active_drones[drone_key]
		var idx: int = int(drone["idx"])
		_kill_fade_tween(idx)
		_drone_pool[idx].stop()
		if not _drone_free.has(idx):
			_drone_free.append(idx)
	_active_drones.clear()


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


## Counts bucket drones of the given type in the CURRENT chord only.
## Old-chord drones still ringing don't count toward attenuation, so the
## first hit of a new chord plays at full volume.
func _count_drones_of_type(is_advanced: bool) -> int:
	var count: int = 0
	for drone_key in _active_drones:
		var drone: Dictionary = _active_drones[drone_key]
		if drone["state"] == DroneState.SPARKLE:
			continue
		if drone.get("is_advanced", false) != is_advanced:
			continue
		if drone.get("chord_gen", -1) != _chord_generation:
			continue
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
		"chord_gen": _chord_generation,
	}




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


## Chord advance: resets per-chord state (queue, attenuation generation,
## activated set). Drones from the previous chord keep playing on their
## fixed timers — no state flip, no fade. Emits chord_changed for any
## remaining visual listeners (drum-layer mode).
func _handle_chord_advance() -> void:
	_chord_generation += 1
	_bucket_queue.clear()
	_chord_activated_buckets.clear()
	_last_bucket_play_time = -999.0
	_activated_buckets_order.clear()
	_unplayed_buckets.clear()
	_pattern_slot_idx = -1
	_pattern_slot_timer = 0.0
	_sparkle_step = 0
	# Drum tiers are time-based (one chord_duration from activation) and
	# NOT cleared here — they persist past chord boundaries until expiration.
	chord_changed.emit(_chord_index)



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
## NOTE: `degree` = bucket's distance from center. Drum-layer mode indexes
## its parallel arrays (drum_instruments, drum_patterns, drum_volumes) by
## this same value, where it's called a "tier." Arpeggio / harp modes use
## it as a chord-tone offset via _get_pitch_scale. Three words, one concept.
func request_bucket_play(board_type: Enums.BoardType, bucket_idx: int, degree: int, is_advanced: bool) -> bool:
	if _silenced:
		return false
	if board_type != _active_board:
		return false

	# Drum-layer mode: activate the tier. Tier stays active for one chord
	# duration from this activation.
	if _theme_drum_instruments().size() > 0:
		if degree < _theme_drum_instruments().size():
			var now: float = Time.get_ticks_msec() / 1000.0
			_active_drum_tiers[degree] = now + _theme_chord_duration()
		_chord_had_landing = true
		return true

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


## Activates a bucket immediately, bypassing the queue and BUCKET_WAIT cooldown.
## In drum-layer mode, activates the drum tier so it plays on its next beat.
## Used by the bucket-value upgrade ripple which orchestrates its own timing.
func force_play_bucket(board_type: Enums.BoardType, bucket_idx: int, degree: int, is_advanced: bool) -> void:
	if _silenced:
		return
	if board_type != _active_board:
		return
	if _theme_drum_instruments().size() > 0:
		if degree < _theme_drum_instruments().size():
			var now: float = Time.get_ticks_msec() / 1000.0
			_active_drum_tiers[degree] = now + _theme_chord_duration()
	else:
		_play_bucket_now(bucket_idx, degree, is_advanced)


## Dequeues pending bucket plays spaced by BUCKET_WAIT. Called from _process.
func _pump_bucket_queue() -> void:
	if _silenced or _bucket_queue.is_empty():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	while not _bucket_queue.is_empty() and now - _last_bucket_play_time >= BUCKET_WAIT:
		var entry: Dictionary = _bucket_queue.pop_front()
		_play_bucket_now(int(entry["bucket_idx"]), int(entry["degree"]), bool(entry["is_advanced"]))
		_last_bucket_play_time = now


## Pattern mode: advance the slot timer, pick and play on "x" slots, rest on
## "-" slots. No-op if the active theme has no pattern (queue mode).
func _tick_pattern(delta: float) -> void:
	if _silenced:
		return
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
	if _silenced or not _sequencer_running:
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
	player.volume_db = -2.0 + volume_offset
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
	if _silenced:
		return
	_last_bucket_fire_ms = Time.get_ticks_msec()
	_sparkles_this_fire = 0
	_chord_had_landing = true

	var instrument: Instrument = _instrument_for(_theme_bucket_type())
	if not instrument or _theme_progression().is_empty():
		return

	# Unique key per allocation — old drones play out fully, no re-attack.
	var key: String = ("A_" if is_advanced else "N_") + str(bucket_idx) + "_" + str(Time.get_ticks_msec())

	var octave_mult: float = 0.25 if is_advanced else 0.5
	var pitch: float = _get_pitch_scale(degree) * octave_mult
	var target_volume: float = BUCKET_VOLUME_DB + (4.0 if is_advanced else 0.0)
	var sp: Dictionary = instrument.resolve(pitch)

	if _drone_free.is_empty():
		return
	var voice_count: int = _count_drones_of_type(is_advanced)
	var voice_attenuation_db: float = _voice_attenuation_db(voice_count)
	var idx: int = _drone_free.pop_back()
	_kill_fade_tween(idx)
	var player: AudioStreamPlayer = _drone_pool[idx]
	player.stream = sp["stream"]
	player.pitch_scale = sp["pitch_scale"]
	player.volume_db = target_volume + voice_attenuation_db
	player.play()
	_active_drones[key] = _make_drone_entry(idx, Harp.DECAY_SECONDS, degree, octave_mult, DroneState.ACTIVE, is_advanced)


## Plays a bell sparkle that walks up the chord from the root. Each sparkle
## within a chord advances one step, climbing into higher octaves as it wraps.
## Resets to root on chord advance (see _handle_chord_advance).
func play_peg_sparkle(board_type: Enums.BoardType) -> void:
	if _silenced:
		return
	if board_type != _active_board:
		return
	if not _bell or _theme_progression().is_empty():
		return

	var entry: Dictionary = _current_chord_entry()
	var chord: Array = entry["chord"]
	if chord.is_empty():
		return

	# Walk up: step 0 = root, step 1 = 3rd, step 2 = 5th, ... wrapping into
	# higher octaves. Start one octave above the middle bucket register (0.5).
	# Second sparkle from the same bucket fire plays an octave above the first
	# without advancing the melody step.
	var degree: int = _sparkle_step % chord.size()
	var extra_octaves: int = _sparkle_step / chord.size()
	var sparkle_octave: float = 1.0 * pow(2.0, extra_octaves + _sparkles_this_fire)
	var pitch: float = _get_pitch_scale(degree) * sparkle_octave
	var sp: Dictionary = _bell.resolve(pitch)

	if _drone_free.is_empty():
		return

	var sparkle_count: int = 0
	for dk in _active_drones:
		if _active_drones[dk]["state"] == DroneState.SPARKLE:
			sparkle_count += 1
	var voice_attenuation_db: float = _voice_attenuation_db(sparkle_count)

	var idx: int = _drone_free.pop_back()
	_kill_fade_tween(idx)
	var player: AudioStreamPlayer = _drone_pool[idx]
	player.stream = sp["stream"]
	player.pitch_scale = sp["pitch_scale"]
	player.volume_db = SPARKLE_VOLUME_DB + voice_attenuation_db
	player.play()

	if _sparkles_this_fire == 0:
		_sparkle_step += 1
	_sparkles_this_fire += 1
	var key: String = "SP_" + str(Time.get_ticks_msec()) + "_" + str(idx)
	_active_drones[key] = _make_drone_entry(idx, SPARKLE_DRONE_SUSTAIN, degree, sparkle_octave, DroneState.SPARKLE, false)


func play_peg_click(board_type: Enums.BoardType) -> void:
	if _silenced:
		return
	if board_type != _active_board:
		return
	var player: AudioStreamPlayer = _click_pool[_click_idx]
	_click_idx = (_click_idx + 1) % _click_pool.size()
	player.pitch_scale = randf_range(0.8, 1.2)
	player.play()


func set_active_board(board_type: Enums.BoardType) -> void:
	if board_type == _active_board:
		return
	_active_board = board_type


## Keeps the ambient pad alive for the whole descent even on large boards
## where the 2s idle timeout would otherwise fade between sparkles.
func on_coin_dropped() -> void:
	_active_coin_count += 1


func on_coin_landed() -> void:
	_active_coin_count = maxi(0, _active_coin_count - 1)


func play_manual_drop_drum(_board_type: Enums.BoardType) -> void:
	pass


func play_autodropper_drum(_board_type: Enums.BoardType, _is_advanced: bool) -> void:
	pass


# ── Legacy API (kept for backward compatibility) ─────────────────────

func play(sound_name: StringName, pitch: float = 0.0, max_duration: float = 0.0) -> void:
	if _silenced:
		return
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


## Prevents new sounds from starting. With fade_duration > 0, also fades
## active drones (scene transitions). With fade_duration <= 0, drones ring
## out naturally (prestige SLOW_MO).
func silence(fade_duration: float = 0.5) -> void:
	_silenced = true
	if fade_duration > 0.0:
		_fade_all_drones(fade_duration)
	_bucket_queue.clear()


## Re-enables sound production after a silence() call.
func unsilence() -> void:
	_silenced = false


func play_prestige(_play_duration: float = 3.0, _fade_duration: float = 2.0) -> void:
	# Always use the first chord (I) so prestige is a I maj7, not whatever chord
	# the progression happened to be on.
	var prog: Array = _theme_progression()
	var root_semitones: int = int(prog[0]["root"]) if not prog.is_empty() else 0
	var root_pitch: float = pow(2.0, root_semitones / 12.0)

	# Bass: long harp at advanced-coin register (2 octaves below C4)
	var bass_pitch: float = root_pitch * 0.25
	var bass_sp: Dictionary = _harp_long.resolve(bass_pitch)
	_play_prestige_voice(bass_sp, PRESTIGE_BASS_VOLUME_DB, "prestige_bass")

	# Bell: 3 octaves above bass (1 octave above C4)
	var bell_pitch: float = root_pitch * 2.0
	var bell_sp: Dictionary = _bell.resolve(bell_pitch)
	_play_prestige_voice(bell_sp, PRESTIGE_BELL_VOLUME_DB, "prestige_bell")

	# Build ascending maj7 arpeggio from bass to bell (3 octaves)
	var maj7_semitones: Array[int] = [0, 4, 7, 11]  # I maj7 chord tones
	_prestige_arpeggio_notes.clear()
	for octave in 3:
		for semitone in maj7_semitones:
			var pitch: float = bass_pitch * pow(2.0, octave) * pow(2.0, semitone / 12.0)
			_prestige_arpeggio_notes.append(pitch)

	# Step 0 (root) was already played as bass — arpeggio starts at step 1
	_prestige_arpeggio_step = 1
	_prestige_arpeggio_last_ms = Time.get_ticks_msec()
	_prestige_arpeggio_active = true


## Allocates a drone pool voice for a prestige note. Fire-and-forget:
## _update_bucket_drones reclaims the slot after the 10s timer expires.
func _play_prestige_voice(sp: Dictionary, volume_db: float, key: String) -> void:
	if _drone_free.is_empty():
		return
	var idx: int = _drone_free.pop_back()
	_kill_fade_tween(idx)
	var player: AudioStreamPlayer = _drone_pool[idx]
	player.stream = sp["stream"]
	player.pitch_scale = sp["pitch_scale"]
	player.volume_db = volume_db
	player.play()
	_active_drones[key] = _make_drone_entry(idx, 10.0, 0, 1.0, DroneState.ACTIVE, false)


## Fires one arpeggio note per PRESTIGE_ARPEGGIO_INTERVAL using wall-clock time.
## Engine.time_scale is ~0.001 during prestige, so delta-based timing won't work.
func _tick_prestige_arpeggio() -> void:
	if not _prestige_arpeggio_active:
		return
	var now_ms: int = Time.get_ticks_msec()
	if (now_ms - _prestige_arpeggio_last_ms) / 1000.0 < PRESTIGE_ARPEGGIO_INTERVAL:
		return
	_prestige_arpeggio_last_ms = now_ms

	if _prestige_arpeggio_step >= _prestige_arpeggio_notes.size():
		_prestige_arpeggio_active = false
		return

	var pitch: float = _prestige_arpeggio_notes[_prestige_arpeggio_step]
	var sp: Dictionary = _harp_long.resolve(pitch)
	var key: String = "prestige_arp_" + str(_prestige_arpeggio_step)
	_play_prestige_voice(sp, PRESTIGE_ARPEGGIO_VOLUME_DB, key)
	_prestige_arpeggio_step += 1


func _on_prestige_phase_changed(phase: PrestigeManager.PrestigePhase) -> void:
	match phase:
		PrestigeManager.PrestigePhase.SLOW_MO:
			silence(-1)
		PrestigeManager.PrestigePhase.NONE:
			unsilence()
			_prestige_arpeggio_active = false
			_prestige_arpeggio_notes.clear()


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


func is_active_board(board_type: Enums.BoardType) -> bool:
	return board_type == _active_board


## Sparkle gate: peg hit must land in the window halfway between bucket sings
## (BUCKET_WAIT/2 to BUCKET_WAIT/2 + 100ms after the last fire). Harp theme
## only — other themes (e.g. glow_dark/triangle) don't sparkle.
func should_sparkle(board_type: Enums.BoardType) -> bool:
	if board_type != _active_board:
		return false
	if _theme_bucket_type() != Instrument.Type.HARP:
		return false
	if _sparkles_this_fire >= MAX_SPARKLES_PER_FIRE:
		return false
	var elapsed_ms: float = Time.get_ticks_msec() - _last_bucket_fire_ms
	if elapsed_ms > SPARKLE_PROXIMITY_MS:
		return false
	return true


## Snap the beat grid to this autodropper tick. Beat period is derived from
## the interval so sparkle cadence tracks the drum (not hardcoded).
func notify_autodropper_beat(interval: float) -> void:
	_autodrop_interval = interval
	_beat_period = interval / float(BEATS_PER_BAR)
	_beat_phase = 0.0
	_motif_position += 1
	_beat_armed = true


func _update_bucket_drones(delta: float) -> void:
	var expired: Array[String] = []
	for drone_key: String in _active_drones:
		var drone: Dictionary = _active_drones[drone_key]
		drone.timer -= delta
		if drone.timer <= 0.0:
			# Don't call player.stop() — the sample is finite and will
			# end on its own. Stopping early cuts off the harp tail.
			_drone_fade_tweens.erase(drone.idx)
			if not _drone_free.has(drone.idx):
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

# ── Tone generation ─────────────────────────────────────────────────

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
