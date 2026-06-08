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

# Bomb-detonation sample lives on its own dedicated player (see
# _bomb_detonation_player below), NOT in the legacy `_sounds` pool — pinning
# its volume_db through that path proved brittle.
const _BOMB_DETONATION_STREAM := preload("res://assets/sounds/sfx/dragon-studio-loud-explosion-425457.mp3")

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
# 0.75x as loud as a bucket hit: bucket combined is -24.4 dB (-17.5 + 20*log10(0.45 harp gain));
# Click's synth gain is 0.30 (-10.5 dB), so -16.5 + (-10.5) = -27.0 dB ≈ bucket - 2.5 dB = 0.75x.
const PEG_CLICK_VOLUME_DB := -16.5
const BUCKET_VOLUME_DB := -17.5

# Peg-collision chime: brief bell-tone, 50/50 root or 5th of the current chord.
# Throttled globally — heavy coin volume produces a steady ~10 Hz tick rather
# than a burst-then-silence pattern that a per-second voice cap would give.
const PEG_CHIME_MIN_INTERVAL_S := 0.25
# 1/8 amplitude of BUCKET_VOLUME_DB (-17.5): 20*log10(0.125) ≈ -18 dB → -35.5.
const PEG_CHIME_VOLUME_DB := -35.5
const PEG_CHIME_SUSTAIN_S := 0.6
# Default chord-tone pool for the chime. Chord arrays are stored as
# root/3rd/5th/7th/octave/.../etc, so [0, 2] = root or 5th. Callers can
# override per-call (MenuBoard passes a richer [0, 1, 2, 4] pool).
const PEG_CHIME_DEGREES_DEFAULT: Array[int] = [0, 2]

var _click_pool: Array[AudioStreamPlayer] = []
var _click_idx: int = 0

var _active_board: Enums.BoardType = Enums.BoardType.GOLD

## When true, `_process` divides its incoming delta by Engine.time_scale so the
## beat grid + chord progression + chime quantizer keep ticking at wall-clock
## rate during a brief cinematic slow-mo (the forbidden-bucket zoom). Default
## off: prestige + cap-raise keep their existing scaled-delta behavior. Set via
## `set_real_time_delta(enabled)` — animators turn it on at start, off at
## teardown.
var _real_time_delta_enabled: bool = false

var _chord_timer: float = 6.0  # overwritten from theme.chord_duration on _ready
var _chord_idle_timer: float = 0.0
var _chord_had_landing: bool = false

var _autodrop_interval: float = DEFAULT_AUTODROP_INTERVAL
var _beat_period: float = DEFAULT_AUTODROP_INTERVAL / BEATS_PER_BAR
var _beat_phase: float = 0.0
var _beat_armed: bool = false
var _motif_position: int = 0

var _active_coin_count: int = 0

# Global throttle for peg chimes — last play timestamp in seconds.
var _peg_chime_last_time_s: float = -1000.0
# UI hover arpeggio — mirrors MainMenu's mechanism so gameplay buttons sing the
# same way. One shared MenuHoverArpeggiator across every button advances ONE
# note per hover (ping-pong up the chord, resets after idle); notes are queued
# and a quantize timer pops one per grid tick. AudioManager owns it (single
# owner, single chord source) just as MainMenu owns the menu's instance.
var _ui_hover_arp := MenuHoverArpeggiator.new()
var _ui_hover_pitch_queue: Array[float] = []
var _peg_chime_rng: RandomNumberGenerator = RandomNumberGenerator.new()
# Quantize mode (theme.peg_chime_quantize_seconds > 0): peg hits within a
# quantum collapse to one chime fired on the next quantum boundary. The most
# recent call's `degrees` pool wins if multiple call sites stack up — they
# don't in practice (only one screen owns input at a time).
var _peg_chime_pending: bool = false
var _peg_chime_pending_degrees: Array[int] = []
var _peg_chime_pending_volume_db: float = PEG_CHIME_VOLUME_DB
var _peg_chime_quantum_timer: float = 0.0

# Sparkle state — pegs sparkle only within 100ms of a bucket drone firing.
# Each sparkle walks up the chord from the root, climbing into higher octaves
# across successive bucket fires. Resets on chord advance. Sparkle is the
# rare event; the chime is the common-case fallback when sparkle doesn't fire.
var _last_bucket_fire_ms: float = -1000.0
var _sparkles_this_fire: int = 0
var _sparkle_step: int = 0

# Drone lifecycle:
#   SPARKLE — peg sparkle; timer-decayed by _update_bucket_drones.
#   ACTIVE  — bucket, prestige, or peg-chime note; timer-decayed, plays to
#             natural end (or until pool slot is reclaimed by a newer play).
# No voice caps — pool exhaustion is the only limit (graceful silent drop).
enum DroneState { SPARKLE, ACTIVE }

const SPARKLE_VOLUME_DB := -22.0
const SPARKLE_PROXIMITY_MS := 100.0
const MAX_SPARKLES_PER_FIRE := 2

# Per-voice attenuation: voice N plays at VOICE_ATTENUATION_RATIO^(N-1) of
# base amplitude (~2.5 dB drop per added voice at 0.75). Sparkle-only —
# bucket plays use per-bucket repeat softening instead (REPEAT_ATTENUATION_DB).
const VOICE_ATTENUATION_RATIO := 0.75

const SPARKLE_DRONE_SUSTAIN := 2.5

# Repeat-bucket softening: when a coin lands in a bucket already singing, the
# repeat play is queued on a lower-priority queue and attenuated linearly per
# concurrent active drone for that bucket. Past the cap, the hit is dropped.
const REPEAT_ATTENUATION_DB := 5.0
const REPEAT_COUNT_CAP := 4

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

# Bomb hazard volumes. Detonation sample ships hot; -24 dB lands it in the
# same perceived band as the other SFX. Hum is the sustained pad behind the
# melody — quiet bed, well below the melody's BUCKET_VOLUME_DB.
const BOMB_DETONATION_VOLUME_DB := -24.0
const BOMB_HUM_VOLUME_DB := -10.0
# Native pitch of the synthesized Triangle instrument — every theme-tuned
# pitch (melody notes, bomb hum, bomb defuse) is computed as a multiplier
# above/below this. Same value Triangle.gd uses internally.
const C4_FREQ_HZ := 261.63
# Global gain boost applied on top of the user's master volume slider. 6x linear ≈ +15.56 dB.
const MASTER_GAIN_BOOST_DB := 15.563025
var _silenced: bool = false  # gates all new sounds (prestige, scene transitions)
var _muted: bool = false  # user preference — mutes the Master bus
var _master_volume_percent: float = 50.0
var _vfx_overrides: Dictionary = {}
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
## Lower-priority queue for repeat hits (a coin landed in a bucket that was
## already singing). Drained only when _bucket_queue is empty so brand-new
## buckets always take precedence; can starve under heavy primary load.
var _repeat_bucket_queue: Array[Dictionary] = []

var _last_bucket_play_time: float = -999.0

# Arpeggio-mode only. Cleared on chord advance.
var _activated_buckets_order: Array[Dictionary] = []
var _unplayed_buckets: Array[Dictionary] = []
var _pattern_slot_idx: int = -1
var _pattern_slot_timer: float = 0.0

# Sequencer (drum-layer mode): drives both melody and drum-layer playback.
# Starts on first challenge tick. Tick rate is theme.melody_slot_seconds
# (default SLOT_DURATION = 0.25s). Themes can slow it down (glow_dark = 1.0s).
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

# Bomb hazard one-shot + hum players. The defuse fires the current chord
# root two octaves up (Triangle, same timbre as the melody); the hum is a
# sustained low pad that joins after the melody has played through once and
# changes pitch on every chord boundary. _bomb_detonation_player is its own
# dedicated player rather than going through the legacy `_sounds` pool —
# previous attempts to set the pool's volume_db kept getting overridden or
# ignored somewhere along the way.
var _bomb_defuse_player: AudioStreamPlayer
var _bomb_detonation_player: AudioStreamPlayer
var _bomb_hum_player: AudioStreamPlayer
var _bomb_hum_active: bool = false
var _bomb_hum_last_root_midi: int = -999

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
var _soft_chime: SoftChime
var _music_box: MusicBox
var _peg_tick: PegTick
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
	_soft_chime = SoftChime.new()
	_music_box = MusicBox.new()
	_peg_tick = PegTick.new()
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

	# Bomb defuse one-shot — Triangle on the Melody bus so it lives in the
	# same timbral space as the melody it borrows its pitch from.
	_bomb_defuse_player = AudioStreamPlayer.new()
	_bomb_defuse_player.bus = &"Melody"
	_bomb_defuse_player.volume_db = BUCKET_VOLUME_DB + 6.0
	add_child(_bomb_defuse_player)

	# Bomb detonation — dedicated player so we can pin its volume_db without
	# any pool round-robin / key-comparison quirks getting in the way. The
	# dragon-studio sample ships extremely hot; -24 dB lands it in the same
	# perceived band as the rest of the SFX.
	_bomb_detonation_player = AudioStreamPlayer.new()
	_bomb_detonation_player.bus = &"Master"
	_bomb_detonation_player.stream = _BOMB_DETONATION_STREAM
	_bomb_detonation_player.volume_db = BOMB_DETONATION_VOLUME_DB
	add_child(_bomb_detonation_player)

	# Bomb root hum — same triangle timbre as the melody but stripped of the
	# per-note attack/release envelope so it sustains. C4 (261.63 Hz) is the
	# native pitch; _update_bomb_hum pitch_scales it to the current chord
	# root one octave down. Routed through Drones so it sits "behind" the
	# Melody bus the triangle melody owns — same colour, different layer.
	_bomb_hum_player = AudioStreamPlayer.new()
	_bomb_hum_player.bus = &"Drones"
	_bomb_hum_player.volume_db = BOMB_HUM_VOLUME_DB
	_bomb_hum_player.stream = _generate_sustained_triangle(1.0, C4_FREQ_HZ)
	add_child(_bomb_hum_player)

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

	# Free-running eighth-note grid that pops queued UI-hover notes (mirrors
	# MainMenu's _hover_quantize_timer). Cheap when the queue is empty.
	var ui_hover_timer := Timer.new()
	ui_hover_timer.wait_time = UI_HOVER_QUANTIZE_SECONDS
	ui_hover_timer.autostart = true
	ui_hover_timer.timeout.connect(_on_ui_hover_quantize_tick)
	add_child(ui_hover_timer)

	set_master_volume(50.0)
	set_process(true)


func _process(delta: float) -> void:
	var has_activity: bool = _active_coin_count > 0
	# During the forbidden-bucket zoom (and any future opt-in cinematic),
	# Engine.time_scale is slowed but we want the beat grid + chord progression
	# to keep marching at wall-clock rate so the chord-bed doesn't stretch and
	# active buckets stay visually in sync with their audio chord. Bucket
	# chimes from coin landings are unaffected — those fire on tween callbacks
	# (already scaled) which is correct (slower coin = fewer chimes).
	if _real_time_delta_enabled:
		delta = delta / maxf(Engine.time_scale, 0.0001)

	_tick_harmonic_rhythm(delta, has_activity)
	_tick_beat_grid(delta)
	_pump_bucket_queue()
	_tick_pattern(delta)
	_tick_sequencer(delta)
	_update_bucket_drones(delta)
	_tick_prestige_arpeggio()
	_tick_peg_chime_quantize(delta)


## Toggle wall-clock delta for the beat grid + chord progression. The
## ForbiddenBucketRevealAnimator turns it on while it owns the slow-mo and
## off on teardown — keeps the chord-bed steady and active buckets in sync
## with their chord even while game time is at 0.35x.
func set_real_time_delta(enabled: bool) -> void:
	_real_time_delta_enabled = enabled


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
	# Reset every piece of chime state so a swap can't carry a stale throttle
	# timestamp (suppressing the first chime in the new theme) or pending
	# degrees/volume from a prior quantize-mode theme.
	_peg_chime_pending = false
	_peg_chime_pending_degrees = []
	_peg_chime_pending_volume_db = PEG_CHIME_VOLUME_DB
	_peg_chime_quantum_timer = 0.0
	_peg_chime_last_time_s = -1000.0
	var kick: Instrument = _instrument_for(_theme_kick_type())
	if kick:
		_kick_player.stream = kick.resolve(0.0).stream


## Maps the Instrument.Type enum to the singleton instance. null = SILENT.
func _instrument_for(type: int) -> Instrument:
	match type:
		Instrument.Type.HARP: return _harp
		Instrument.Type.TRIANGLE: return _triangle
		Instrument.Type.BELL: return _bell
		Instrument.Type.SOFT_CHIME: return _soft_chime
		Instrument.Type.MUSIC_BOX: return _music_box
		Instrument.Type.PEG_TICK: return _peg_tick
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


## Counts ACTIVE drones currently allocated for this bucket+type. Used by
## _play_bucket_now as the implicit "repeat index" for progressive softening —
## no _repeat_counts dict to maintain; expiration is the natural reset.
func _count_active_drones_for_bucket(bucket_idx: int, is_advanced: bool) -> int:
	var prefix: String = ("A_" if is_advanced else "N_") + str(bucket_idx) + "_"
	var count: int = 0
	for key: String in _active_drones:
		if not key.begins_with(prefix):
			continue
		if _active_drones[key]["state"] != DroneState.ACTIVE:
			continue
		count += 1
	return count


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
	_repeat_bucket_queue.clear()
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
		_slot_timer = _theme_melody_slot_seconds()
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
## `is_repeat` (queue mode only): when true, the entry is routed to the
## lower-priority `_repeat_bucket_queue` instead, never preempts primary,
## and the per-bucket count check in `_play_bucket_now` softens or caps it.
## In drum-layer and arpeggio modes the flag is ignored — softening only
## applies in queue mode where the harp drones overlap.
func request_bucket_play(board_type: Enums.BoardType, bucket_idx: int, degree: int, is_advanced: bool, is_repeat: bool = false) -> bool:
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

	# Queue mode. Repeats never preempt the primary queue — always queued,
	# and only drained when _bucket_queue is empty (see _pump_bucket_queue).
	if is_repeat:
		_repeat_bucket_queue.push_back(entry)
		return true

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


## Dequeues pending bucket plays spaced by BUCKET_WAIT. Primary queue drains
## before the repeat queue so brand-new buckets always take precedence.
func _pump_bucket_queue() -> void:
	if _silenced:
		return
	if _bucket_queue.is_empty() and _repeat_bucket_queue.is_empty():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	while now - _last_bucket_play_time >= BUCKET_WAIT:
		var entry: Dictionary
		if not _bucket_queue.is_empty():
			entry = _bucket_queue.pop_front()
		elif not _repeat_bucket_queue.is_empty():
			entry = _repeat_bucket_queue.pop_front()
		else:
			return
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
## theme.melody_slot_seconds. Starts on first challenge tick, stops on theme swap.
func _tick_sequencer(delta: float) -> void:
	if _silenced or not _sequencer_running:
		return
	_slot_timer -= delta
	while _slot_timer <= 0.0:
		_global_slot_idx += 1
		_slot_timer += _theme_melody_slot_seconds()
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
		# Bomb root hum: starts after the first full melody pass and updates
		# at every chord boundary. Run unconditionally per slot (even on rests
		# — _melody_idx still advanced) so the activation timing is exact.
		_update_bomb_hum(seq)

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
	# The hum was tied to the just-stopped melody — kill it so a fresh
	# sequencer start (new theme / new challenge) doesn't leave it sustained
	# at the previous root.
	_stop_bomb_hum()


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
	# Repeat softening: count this bucket's currently-active drones; each one
	# already singing softens the new drone by REPEAT_ATTENUATION_DB. Past the
	# cap, drop the hit silently rather than allocate another voice.
	var repeat_count: int = _count_active_drones_for_bucket(bucket_idx, is_advanced)
	if repeat_count >= REPEAT_COUNT_CAP:
		return
	var idx: int = _drone_free.pop_back()
	_kill_fade_tween(idx)
	var player: AudioStreamPlayer = _drone_pool[idx]
	player.stream = sp["stream"]
	player.pitch_scale = sp["pitch_scale"]
	player.volume_db = target_volume - REPEAT_ATTENUATION_DB * repeat_count
	player.play()
	_active_drones[key] = _make_drone_entry(idx, Harp.DECAY_SECONDS, degree, octave_mult, DroneState.ACTIVE, is_advanced)


## Plays a bell sparkle that walks up the chord from the root. Each sparkle
## within a chord advances one step, climbing into higher octaves as it wraps.
## Resets to root on chord advance (see _handle_chord_advance). Rare by design
## (gated by should_sparkle's proximity window); the chime is the common-case
## fallback when sparkle doesn't fire.
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


## Records a peg-contact event for the chime layer. Two timing modes selected
## by the active theme:
##   Throttle (default): play immediately if PEG_CHIME_MIN_INTERVAL_S has
##     elapsed since the last play, else drop.
##   Quantize (theme.peg_chime_quantize_seconds > 0): mark "pending" and let
##     _tick_peg_chime_quantize fire exactly one chime on the next quantum
##     boundary, regardless of how many pegs were hit since.
## `degrees`: chord-array indices the chime randomly picks from (chord arrays
## are stored as root/3rd/5th/7th/octave/...). Empty = default [0, 2]
## (root/5th). Per-call-site override exists so future themes/screens can
## pass a richer pool without a theme-field round-trip.
## `min_interval_seconds`: per-call-site throttle override in throttle mode.
## Negative = use PEG_CHIME_MIN_INTERVAL_S.
## `volume_db`: per-call-site loudness override. NAN = use PEG_CHIME_VOLUME_DB.
## No board gate — call sites self-gate (PlinkoBoard via flash_nearest_peg's
## is_active_board check).
func play_peg_chime(degrees: Array[int] = [], min_interval_seconds: float = -1.0, volume_db: float = NAN) -> void:
	if _silenced:
		return
	if not _theme_peg_chime_enabled():
		return
	if not _soft_chime or _theme_progression().is_empty():
		return

	var pool: Array[int] = degrees if not degrees.is_empty() else PEG_CHIME_DEGREES_DEFAULT
	var vol_db: float = volume_db if not is_nan(volume_db) else PEG_CHIME_VOLUME_DB

	if _theme_peg_chime_quantize_s() > 0.0:
		_peg_chime_pending_degrees = pool
		_peg_chime_pending_volume_db = vol_db
		_peg_chime_pending = true
		return

	var throttle: float = min_interval_seconds if min_interval_seconds >= 0.0 else PEG_CHIME_MIN_INTERVAL_S
	var now_s: float = Time.get_ticks_msec() / 1000.0
	if now_s - _peg_chime_last_time_s < throttle:
		return

	if not _do_play_peg_chime(pool, vol_db):
		return
	_peg_chime_last_time_s = now_s


## Actual chime playback — picks a chord-tone index from `degrees`, allocates
## a drone slot, plays the bell at `volume_db`. Returns false on missing chord
## / empty pool so callers can decide whether to update throttle bookkeeping.
func _do_play_peg_chime(degrees: Array[int], volume_db: float) -> bool:
	var entry: Dictionary = _current_chord_entry()
	var chord: Array = entry["chord"]
	if chord.is_empty():
		return false

	if _drone_free.is_empty():
		return false

	# Count chimes as activity so the chord progression advances on screens
	# with no bucket landings (main menu). Without this, _tick_harmonic_rhythm
	# resets to root each chord_duration because _chord_had_landing stayed false.
	_chord_had_landing = true

	var degree: int = pick_peg_degree(_peg_chime_rng, degrees)
	var pitch: float = _get_pitch_scale(degree)
	return _play_chime_voice(_soft_chime, pitch, volume_db, PEG_CHIME_SUSTAIN_S, degree) >= 0


## Plays a chime-style voice at a caller-specified pitch_mult — bypasses random
## degree picking, throttling, AudioStyle chord lookup, and `_chord_had_landing`
## side effects. Used by MenuBoard for both its chord-bed melody (MUSIC_BOX)
## and its peg-contact ticks (PEG_TICK); independent of any theme's progression.
## `instrument_type` selects the timbre (defaults to SOFT_CHIME for callers
## that don't care). `volume_db` / `sustain_s` default to the gameplay
## peg-chime values when NAN.
func play_pitched_chime(pitch_mult: float, volume_db: float = NAN,
		sustain_s: float = NAN,
		instrument_type: Instrument.Type = Instrument.Type.SOFT_CHIME) -> void:
	if _silenced:
		return
	var instrument: Instrument = _instrument_for(instrument_type)
	if instrument == null:
		return
	var vol_db: float = volume_db if not is_nan(volume_db) else PEG_CHIME_VOLUME_DB
	var sustain: float = sustain_s if not is_nan(sustain_s) else PEG_CHIME_SUSTAIN_S
	_play_chime_voice(instrument, pitch_mult, vol_db, sustain, 0)


## Milestone "coin frenzy" pop — theme-driven so each world's frenzy sounds native.
## Themes with frenzy_pop_uses_chord_root play the CURRENT chord's root note two
## octaves up through the bucket instrument (so it harmonizes with the tonal
## background — 3 octaves above the drone / 2 above the base note). Other themes
## play a fixed bell two octaves up. Volume = 2/3 of a bucket hit (amplitude).
## `step` (the coin's index in the frenzy) is used ONLY by chord_root mode, to
## arpeggiate through the progression; melody_root and bell modes ignore it.
func play_frenzy_pop(step: int = 0) -> void:
	if _silenced:
		return
	var theme: VisualTheme = ThemeProvider.theme
	var vol_db: float = BUCKET_VOLUME_DB + linear_to_db(2.0 / 3.0)
	if theme.frenzy_pop_uses_melody_root:
		# Live chord root from the melody (one chord per 16 notes). Read fresh on
		# every pop so a chord change mid-frenzy is reflected; all pops within a
		# chord share the same pitch. *4 = the base note two octaves up.
		var root_midi: int = get_current_chord_root_midi()
		if root_midi >= 0:
			# Normal pops sit two octaves up (*4); the final chord of the cycle
			# pops three octaves up (*8) for a brighter resolve.
			var is_final_chord: bool = get_current_chord_index() == _CHORD_ROOT_MIDI_CYCLE.size() - 1
			var octave_mult: float = 8.0 if is_final_chord else 4.0
			var pitch: float = pow(2.0, float(root_midi - 60) / 12.0) * octave_mult
			play_pitched_chime(pitch, vol_db, NAN, theme.bucket_instrument)
			return
	if theme.frenzy_pop_uses_chord_root:
		var prog: Array = _theme_progression()
		if not prog.is_empty():
			# Walk the progression's chord roots so a frenzy arpeggiates through all
			# chords (the 4 notes) instead of repeating one. `step` (the coin index)
			# advances one chord per pop, starting from the live chord.
			var entry: Dictionary = prog[(_chord_index + step) % prog.size()]
			var chord: Array = entry["chord"]
			var semitones: int = int(entry["root"]) + (int(chord[0]) if not chord.is_empty() else 0)
			var pitch: float = pow(2.0, semitones / 12.0) * 4.0  # base note, two octaves up
			play_pitched_chime(pitch, vol_db, NAN, theme.bucket_instrument)
			return
	play_pitched_chime(4.0, vol_db, NAN, Instrument.Type.BELL)


## −10 dB below the bucket hit so the 4-voice chord sums to roughly bucket-hit
## loudness rather than 4x. Tweens from `quiet → peak → quiet` over the swell.
const MILESTONE_PEAK_OFFSET_DB := -10.0
## Depth of the swell tails — quiet floor sits this many dB below the peak.
const MILESTONE_SWELL_DEPTH_DB := 24.0
const MILESTONE_ATTACK_S := 0.5
const MILESTONE_RELEASE_S := 1.0


## One-shot 4-note block chord (root, 3rd, 5th, 7th-or-octave) drawn from the
## CURRENT chord of the active progression, with a quiet→loud→quiet swell
## envelope so the milestone celebration sits in the mix rather than stabbing.
## Plays through the theme's bucket instrument so the timbre matches buckets.
## Called by LevelSection on every milestone reached.
func play_milestone_chord() -> void:
	if _silenced:
		return
	var entry: Dictionary = _current_chord_entry()
	if entry.is_empty():
		return
	var chord: Array = entry.get("chord", [])
	var root: int = int(entry.get("root", 0))
	if chord.size() < 4:
		return
	var peak_db: float = BUCKET_VOLUME_DB + MILESTONE_PEAK_OFFSET_DB
	var quiet_db: float = peak_db - MILESTONE_SWELL_DEPTH_DB
	var sustain_s: float = MILESTONE_ATTACK_S + MILESTONE_RELEASE_S
	var instrument: Instrument = _instrument_for(_theme_bucket_type())
	if instrument == null:
		return
	for d in [0, 1, 2, 3]:
		var semitones: int = int(chord[d]) + root
		var pitch_mult: float = pow(2.0, semitones / 12.0)
		# Allocate the voice at the quiet floor so the tween starts from
		# silence and the attack ramp is what the player hears first.
		var idx: int = _play_chime_voice(instrument, pitch_mult, quiet_db, sustain_s, d)
		if idx < 0:
			continue
		var player: AudioStreamPlayer = _drone_pool[idx]
		var swell := player.create_tween()
		swell.tween_property(player, "volume_db", peak_db, MILESTONE_ATTACK_S) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		swell.tween_property(player, "volume_db", quiet_db, MILESTONE_RELEASE_S) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		# Register the swell in `_drone_fade_tweens` so when the slot is
		# popped from `_drone_free` for the next chime, `_play_chime_voice`'s
		# `_kill_fade_tween(idx)` kills our tween — otherwise the swell
		# would keep writing volume_db onto the now-reassigned voice.
		_drone_fade_tweens[idx] = swell


## Shared voice allocation — pops a free drone, configures stream / pitch /
## volume, marks the slot active. Returns the drone-pool index of the
## allocated voice (so callers can tween its volume for envelopes), or -1
## when no slot is free. Used by both the random-degree peg chime path
## (always SoftChime) and `play_pitched_chime` (caller-selectable instrument).
func _play_chime_voice(instrument: Instrument, pitch_mult: float, volume_db: float,
		sustain_s: float, degree: int) -> int:
	if _drone_free.is_empty():
		return -1
	var sp: Dictionary = instrument.resolve(pitch_mult)
	var idx: int = _drone_free.pop_back()
	_kill_fade_tween(idx)
	var player: AudioStreamPlayer = _drone_pool[idx]
	player.stream = sp["stream"]
	player.pitch_scale = sp["pitch_scale"]
	player.volume_db = volume_db
	player.play()
	var key: String = "PC_" + str(Time.get_ticks_msec()) + "_" + str(idx)
	_active_drones[key] = _make_drone_entry(idx, sustain_s, degree, 1.0, DroneState.ACTIVE, false)
	return idx


## Pure uniform-random picker over the supplied chord-tone index pool. Empty
## pool falls back to PEG_CHIME_DEGREES_DEFAULT. Injected RNG for headless
## distribution tests.
static func pick_peg_degree(rng: RandomNumberGenerator, degrees: Array[int]) -> int:
	var pool: Array[int] = degrees if not degrees.is_empty() else PEG_CHIME_DEGREES_DEFAULT
	return pool[rng.randi() % pool.size()]


## Quantize-mode driver: when the active theme sets a quantize interval, accumulates
## delta and fires one chime per quantum if any peg hit registered. Multiple
## peg hits within a quantum collapse to one chime.
func _tick_peg_chime_quantize(delta: float) -> void:
	var quantize: float = _theme_peg_chime_quantize_s()
	if quantize <= 0.0:
		_peg_chime_pending = false
		_peg_chime_quantum_timer = 0.0
		return
	if _silenced:
		_peg_chime_pending = false
		return
	_peg_chime_quantum_timer += delta
	if _peg_chime_quantum_timer >= quantize:
		# fmod handles the rare case of low FPS skipping multiple quanta.
		# We deliberately fire at most one chime per tick (collapse).
		_peg_chime_quantum_timer = fmod(_peg_chime_quantum_timer, quantize)
		if _peg_chime_pending:
			_peg_chime_pending = false
			_do_play_peg_chime(_peg_chime_pending_degrees, _peg_chime_pending_volume_db)


func _theme_peg_chime_enabled() -> bool:
	if ThemeProvider and ThemeProvider.theme:
		return ThemeProvider.theme.peg_chime_enabled
	return true


func _theme_peg_chime_quantize_s() -> float:
	if ThemeProvider and ThemeProvider.theme:
		return ThemeProvider.theme.peg_chime_quantize_seconds
	return 0.0


func _theme_melody_slot_seconds() -> float:
	if ThemeProvider and ThemeProvider.theme:
		return ThemeProvider.theme.melody_slot_seconds
	return SLOT_DURATION


# UI hover audio — faithful copy of the main-menu hover (MainMenu._on_menu_button_hover):
# each hover commits ONE note from the shared arpeggiator to a small queue; the
# quantize timer pops one per 0.125s grid tick and rings it through the board's
# bucket instrument (one octave up) so the buttons sing in the game's own voice.
# Queue-full hovers are dropped WITHOUT advancing the arpeggiator, so the
# progression stays aligned with what's actually audible. The arpeggiator walks
# up the current chord one step per hover and resets after a short idle.
const UI_HOVER_QUANTIZE_SECONDS := 0.125
const UI_HOVER_QUEUE_CAPACITY := 3
const UI_HOVER_NOTE_SUSTAIN_S := 3.0
# Volume below a bucket hit. A literal "2/3 amplitude" (-3.5 dB) was inaudible —
# the note is an octave up (the ear reads higher pitches as louder) and sits
# below the Drones compressor threshold, so it needs a real cut. THE knob to
# tune by ear: more negative = quieter.
const UI_HOVER_VOLUME_OFFSET_DB := -8.0
# Normal-bucket register (matches _play_bucket_now's octave_mult). We build the
# chord pitches down here so the arpeggiator's built-in +1 octave lands the hover
# note exactly ONE octave above the buckets (not two).
const UI_HOVER_BUCKET_OCTAVE := 0.5

func play_ui_hover() -> void:
	if _silenced:
		return
	if _ui_hover_pitch_queue.size() >= UI_HOVER_QUEUE_CAPACITY:
		return
	var note: Vector2i = _ui_hover_arp.advance(Time.get_ticks_msec())
	# Current chord's 4 note multipliers at the bucket register; pitch_mult_for
	# adds the arpeggiator's one octave → one octave above the buckets.
	var pitches := PackedFloat32Array([
		_get_pitch_scale(0) * UI_HOVER_BUCKET_OCTAVE,
		_get_pitch_scale(1) * UI_HOVER_BUCKET_OCTAVE,
		_get_pitch_scale(2) * UI_HOVER_BUCKET_OCTAVE,
		_get_pitch_scale(3) * UI_HOVER_BUCKET_OCTAVE])
	_ui_hover_pitch_queue.append(MenuHoverArpeggiator.pitch_mult_for(note.x, note.y, pitches))


func _on_ui_hover_quantize_tick() -> void:
	if _ui_hover_pitch_queue.is_empty():
		return
	var pitch_mult: float = _ui_hover_pitch_queue.pop_front()
	# Same instrument as the gameplay buckets (so the hover sings in the board's
	# voice), held clearly below them via UI_HOVER_VOLUME_OFFSET_DB.
	var vol_db: float = BUCKET_VOLUME_DB + UI_HOVER_VOLUME_OFFSET_DB
	play_pitched_chime(pitch_mult, vol_db, UI_HOVER_NOTE_SUSTAIN_S, _theme_bucket_type())


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
	_repeat_bucket_queue.clear()


## Re-enables sound production after a silence() call.
func unsilence() -> void:
	_silenced = false


func set_muted(muted: bool) -> void:
	_muted = muted
	AudioServer.set_bus_mute(0, muted)


func is_muted() -> bool:
	return _muted


func set_master_volume(percent: float) -> void:
	_master_volume_percent = clampf(percent, 0.0, 100.0)
	var linear: float = _master_volume_percent / 100.0
	AudioServer.set_bus_volume_db(0, linear_to_db(linear) + MASTER_GAIN_BOOST_DB if linear > 0.0 else -80.0)


func get_master_volume() -> float:
	return _master_volume_percent


func set_vfx_override(key: String, enabled: bool) -> void:
	_vfx_overrides[key] = enabled
	_apply_vfx_override(key, enabled, ThemeProvider.theme)


func get_vfx_overrides() -> Dictionary:
	return _vfx_overrides


func apply_all_vfx_overrides() -> void:
	var t: VisualTheme = ThemeProvider.theme
	if not t:
		return
	for key: String in _vfx_overrides:
		_apply_vfx_override(key, _vfx_overrides[key], t)


func _apply_vfx_override(key: String, enabled: bool, t: VisualTheme) -> void:
	match key:
		"peg_flash":          t.peg_flash_enabled = enabled
		"peg_pulse":          t.peg_pulse_enabled = enabled
		"peg_glow_halo":      t.peg_glow_halo_enabled = enabled
		"peg_ring":           t.peg_ring_enabled = enabled
		"bucket_pulse":       t.bucket_pulse_enabled = enabled
		"coin_halo":          t.coin_halo_enabled = enabled
		"coin_impact_squash": t.coin_impact_squash_enabled = enabled
		"drop_burst":         t.drop_burst_enabled = enabled
		"coin_burst":         t.coin_burst_enabled = enabled
		"level_bar_shimmer":  t.level_bar_shimmer_enabled = enabled
		"level_bar_particle": t.level_bar_particle_enabled = enabled
		"vignette":           t.vignette_enabled = enabled
		"board_glow":         t.board_glow_enabled = enabled
		"bg_particles":       t.bg_particles_enabled = enabled


## Bomb hazard audio. Light stubs for the v1 cut — bomb-tick is a soft peg
## click (synced to ChallengeManager.tick), detonation reuses the peg sparkle
## as a dramatic bell, and defuse uses the peg sparkle one register up.
## Replace with bespoke sounds once the hazard plays nice gameplay-wise.
func play_bomb_tick(_seconds_remaining: int, board_type: Enums.BoardType = Enums.BoardType.GOLD) -> void:
	if _silenced:
		return
	play_peg_click(board_type)


func play_bomb_detonation(_board_type: Enums.BoardType = Enums.BoardType.GOLD) -> void:
	if _silenced:
		return
	# Dedicated player (NOT the legacy pool) — see _ready for setup. Setting
	# volume_db every play as belt-and-braces in case something later in the
	# session resets it; pitch_scale pinned to 1.0 (every detonation should
	# sound identical, not randomised the way melody / coin plays are).
	_bomb_detonation_player.volume_db = BOMB_DETONATION_VOLUME_DB
	_bomb_detonation_player.pitch_scale = 1.0
	if _bomb_detonation_player.playing:
		_bomb_detonation_player.stop()
	_bomb_detonation_player.play()


func play_bomb_defuse(_board_type: Enums.BoardType = Enums.BoardType.GOLD) -> void:
	if _silenced:
		return
	var root_midi: int = get_current_chord_root_midi()
	if root_midi < 0:
		return
	# Two octaves above the current chord's root: a high flourish that sits
	# clearly above the melody's register without changing voice.
	var target_midi: int = root_midi + BOMB_DEFUSE_SEMITONE_OFFSET
	var pitch_mult: float = pow(2.0, float(target_midi - 60) / 12.0)
	var sp: Dictionary = _triangle.resolve(pitch_mult)
	_bomb_defuse_player.stream = sp["stream"]
	_bomb_defuse_player.pitch_scale = sp["pitch_scale"]
	_bomb_defuse_player.play()


## Roots of the 4 chords in the GLOW_DARK challenge progression: C3, Ab3,
## Bb3, G3 (midi 48, 56, 58, 55). Pinned by hand. Hum (root - 12) sits at
## C2, Ab2, Bb2, G2 — i-VI-VII-V minor walk. Defuse adds 24 → C5 Ab5 Bb5 G5.
##
## ⚠️ This table is glow_dark-specific. When a second challenge theme with
## a different progression introduces bombs, move these values onto
## VisualTheme (or AudioStyle) so each theme owns its own chord roots.
## Until then, get_current_chord_root_midi push_warnings if it's queried on
## a theme without a melody_sequence we recognise — keeps the silent-
## misbehaviour from sneaking up on someone.
const _CHORD_ROOT_MIDI_CYCLE: Array = [48, 56, 58, 55]
## Semitone offsets from the chord root used by the bomb audio cues. -12 is
## the hum's "one octave below" rule from the design; +24 is the defuse
## "two octaves above". Single source of truth — both _update_bomb_hum and
## play_bomb_defuse reference these.
const BOMB_HUM_SEMITONE_OFFSET := -12
const BOMB_DEFUSE_SEMITONE_OFFSET := 24


## The midi value of the "root" of the chord currently playing. The chord
## changes every 16 slots; we cycle through `_CHORD_ROOT_MIDI_CYCLE` indexed
## by (slot / 16) mod 4. Returns the most-recently-played chord's root.
## Reused by the bomb defuse cue and the sustained root-hum updater.
##
## NOTE: the lookup table is hand-pinned to glow_dark's progression. Other
## themes with their own progressions will get wrong-key bomb cues until
## the table is moved onto the theme/AudioStyle resource.
func get_current_chord_root_midi() -> int:
	var chord_idx: int = get_current_chord_index()
	if chord_idx < 0:
		return -1
	return _CHORD_ROOT_MIDI_CYCLE[chord_idx]


## Index (0-based) of the chord currently playing in the melody, or -1 if the
## theme has no melody. The chord changes every 16 melody slots; the last index
## is the "final" chord of the cycle. Single source of the chord-index math.
func get_current_chord_index() -> int:
	if not ThemeProvider or not ThemeProvider.theme:
		return -1
	var seq: PackedInt32Array = ThemeProvider.theme.melody_sequence
	if seq.is_empty():
		return -1
	# After playing the note at index N, _melody_idx == N + 1, so the most-recently
	# played note is at _melody_idx - 1. 16 melody slots per chord.
	var last_played: int = maxi(_melody_idx - 1, 0)
	@warning_ignore("integer_division")
	return (last_played / 16) % _CHORD_ROOT_MIDI_CYCLE.size()


## Drives the root-hum. After the melody has played a full pass, a low
## sustained pad joins it — pitched to (current chord root - 12 semitones)
## and rewritten on every chord boundary. Called from _play_slot after the
## melody / drum work has settled the new _melody_idx.
func _update_bomb_hum(seq: PackedInt32Array) -> void:
	if _silenced or seq.is_empty():
		_stop_bomb_hum()
		return
	if _melody_idx < seq.size():
		# First pass not yet complete — hum hasn't joined.
		return
	var root_midi: int = get_current_chord_root_midi()
	if root_midi < 0:
		return
	var root_changed: bool = root_midi != _bomb_hum_last_root_midi
	if root_changed:
		# Generate a fresh sustained-triangle WAV at the exact target pitch
		# rather than pitch_scaling a C4-native stream. In Godot 4, pitch_scale
		# on a LOOP_FORWARD AudioStreamWAV is sampled at the loop boundary,
		# NOT continuously — so the prior implementation only retook the new
		# rate on the FIRST chord and then kept resampling at the original C4
		# rate on subsequent boundaries. Regenerating sidesteps the issue
		# entirely (88 KB per chord change, ~once every 4 seconds — cheap;
		# the previous stream is RefCounted and freed when reassigned).
		var target_midi: int = root_midi + BOMB_HUM_SEMITONE_OFFSET
		var target_freq: float = C4_FREQ_HZ * pow(2.0, float(target_midi - 60) / 12.0)
		_bomb_hum_player.stop()
		_bomb_hum_player.stream = _generate_sustained_triangle(1.0, target_freq)
		_bomb_hum_player.pitch_scale = 1.0
		_bomb_hum_player.play()
		_bomb_hum_last_root_midi = root_midi
		_bomb_hum_active = true
		return
	# Belt + braces: if the loop ever stops (asset reload, sequencer hiccup),
	# kick it back to life rather than silently going AWOL.
	if not _bomb_hum_player.playing:
		_bomb_hum_player.play()
		_bomb_hum_active = true


func _stop_bomb_hum() -> void:
	if _bomb_hum_active:
		_bomb_hum_player.stop()
		_bomb_hum_active = false
	_bomb_hum_last_root_midi = -999


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

## Sustained triangle-wave loop for the bomb root hum. Same waveform family
## as the Triangle melody instrument (so the hum reads as the same voice)
## but stripped of the 0.25s attack/release envelope so it loops cleanly
## without re-attacking. Native pitch is C4; caller pitch-scales to the
## current chord root.
func _generate_sustained_triangle(duration: float, freq: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = int(duration * mix_rate)
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in num_samples:
		var t: float = float(i) / mix_rate
		# Gentle 0.25 Hz amplitude wobble keeps the hum breathing without
		# ever fading to silence.
		var breath: float = 0.85 + 0.15 * sin(TAU * 0.25 * t)
		var phase: float = fmod(freq * t, 1.0)
		var tri: float = 4.0 * absf(phase - 0.5) - 1.0
		var value: float = tri * breath * 0.3
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
