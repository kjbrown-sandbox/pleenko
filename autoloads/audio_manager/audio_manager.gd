extends Node

## Pool of AudioStreamPlayers per sound for overlapping playback.
## Bucket hits are capped at MAX_BUCKET_SOUNDS concurrent plays — extras are silently dropped.

# Emitted when the active AudioStyle advances to the next chord in its progression.
# Only fires in AudioStyle mode — the default per-board harp path doesn't emit.
# PlinkoBoard listens and fades chord-activated buckets back to their faded color.
signal chord_changed(chord_index: int)

# Floor for chord-gated chime tail length. If a bucket is hit in the last ~0.5s
# of a chord, the natural tail would clip before becoming audible — this keeps
# at least one second of ring before the chord_changed fade starts.
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

# Chord quality: semitone offsets above the chord's root, stacked thirds.
# Bucket distance from center maps to an index in this array — center = root,
# ±1 = 3rd, ±2 = 5th, ±3 = 7th, ±4 = octave, etc. Multiple buckets landing
# together build an actual jazz chord rather than a pentatonic cluster.
const CHORD_MAJ7 := [0, 4, 7, 11, 12, 16, 19, 23]   # 1, 3, 5, 7, 8ve, 8ve+3, 8ve+5, 8ve+7
const CHORD_DOM7 := [0, 4, 7, 10, 12, 16, 19, 22]   # major 3, minor 7 (the V chord)
const CHORD_MIN7 := [0, 3, 7, 10, 12, 15, 19, 22]   # minor 3, minor 7
# Plain triads (no 7ths) — used by arcade / rock styles that want power-chord
# clarity instead of jazz color. Voicing mirrors the 7th chords' 8-slot layout.
const CHORD_MAJ := [0, 4, 7, 12, 16, 19, 24, 28]    # major triad + octave doubles
const CHORD_MIN := [0, 3, 7, 12, 15, 19, 24, 27]    # minor triad + octave doubles

# Per-board chord progressions. Each entry is { "root": int, "chord": Array }
# and the active chord cycles on CHORD_DURATION while the active board sees
# activity. All chord tones stay diatonic to C major so cross-board multi-drops
# stay consonant.
var _board_progressions: Dictionary = {}  # BoardType -> Array[{ "root", "chord" }]
var _current_chord_index: Dictionary = {}  # BoardType -> int

const CHORD_DURATION := 6.0           # seconds per chord before advancing
const CHORD_IDLE_RESET := 2.0         # seconds of idle before harmonic rhythm resets

# Beat grid: sparkles fire on a 4/4 grid derived from the autodropper tick.
# Beat period = autodrop interval / BEATS_PER_BAR. The beat clock free-runs
# from DEFAULT_AUTODROP_INTERVAL until the first real autodropper tick, which
# snaps the phase and updates the interval.
const DEFAULT_AUTODROP_INTERVAL := 1.5
const BEATS_PER_BAR := 4

const MELODY_POOL_SIZE := 12
const CLICK_POOL_SIZE := 8
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

# Harmonic rhythm state.
var _chord_timer: float = CHORD_DURATION
var _chord_idle_timer: float = 0.0
var _chord_had_sparkle: bool = false  # tracks whether any sparkle fired during the current chord

# Beat grid + motif state.
var _autodrop_interval: float = DEFAULT_AUTODROP_INTERVAL
var _beat_period: float = DEFAULT_AUTODROP_INTERVAL / BEATS_PER_BAR
var _beat_phase: float = 0.0       # time into current beat slot, 0.._beat_period
var _beat_armed: bool = false      # current beat's note hasn't been consumed yet
var _motif_position: int = 0       # index into the current chord's motif

# Ambient pad double-buffer. Each board has its own pre-generated pad stream
# at the board's chord voicing (e.g., Cmaj7 for gold, G7 for orange). Board
# switches assign the new stream to the inactive player before crossfading.
var _ambient_a: AudioStreamPlayer
var _ambient_b: AudioStreamPlayer
var _ambient_active: AudioStreamPlayer
var _ambient_pad_streams: Dictionary = {}  # BoardType -> AudioStreamWAV
var _ambient_fading_in: bool = false
var _idle_timer: float = 0.0
var _activity_detected: bool = false
# Tracks coins currently in-flight on active boards. Ambient pad stays alive
# while this is > 0 and for AMBIENT_IDLE_TIMEOUT seconds after it hits 0.
var _active_coin_count: int = 0

# Bucket drones: one sustained note per unique bucket pitch. Shared with peg
# sparkles so both get the same harp-like sustain profile. Drone lifecycle is
# tracked via DroneState:
#   SPARKLE   — peg sparkle note; timer-decayed by _update_bucket_drones.
#   ACTIVE    — bucket note ringing in current chord; chord-managed, not
#               timer-decayed (chord advance flips it to LINGERING instead).
#   LINGERING — previous chord's bucket note carrying across silence; timer
#               set to the synthesized sample length so the pool slot releases
#               after the audible decay ends, even if no new coin hits.
#
# Three separate fade-duration knobs live on VisualTheme, each tied to a
# different trigger:
#   bucket_fade_duration    — visual bucket color tween on chord change.
#   linger_fade_duration    — audio handoff fade when a new coin lands and
#                             clears the previous chord's LINGERING drones.
#   eviction_fade_duration  — audio fade when the voice cap steals an older
#                             drone's slot to make room for a new allocation.
enum DroneState { SPARKLE, ACTIVE, LINGERING }

# Per-coin-type voice caps (replaces the previous shared MAX_ACTIVE_DRONES).
# Normal coins are the melodic top layer; advanced coins are the slower, deeper
# bass punctuation layer. They occupy different registers so they don't dim or
# evict each other — two independent pools, each tuned for its own role.
const MAX_NORMAL_DRONES := 5
const MAX_ADVANCED_DRONES := 3

# Per-voice exponential attenuation ratio: voice N allocated while N-1 drones
# are already ringing plays at VOICE_ATTENUATION_RATIO^(N-1) of base amplitude.
# 0.75 = ~2.5 dB drop per additional voice. The compressor on the Drones bus
# is tuned against this curve; retune both together if either changes.
const VOICE_ATTENUATION_RATIO := 0.75

const BUCKET_DRONE_FADE_RATE := 24.0  # dB/sec — 3s fade over the ~72 dB range
const SPARKLE_DRONE_SUSTAIN := 3.5     # sparkles ring a bit shorter than bucket drones
const BUCKET_DRONE_POOL_SIZE := 24
var _drone_pool: Array[AudioStreamPlayer] = []
var _drone_free: Array[int] = []
var _active_drones: Dictionary = {}  # String key -> { "idx", "timer", "degree", "octave_mult", "state" }
# Active fade tweens keyed by drone pool idx. Reusing a pool slot kills any
# in-flight fade tween first so it can't keep writing to the new drone's
# volume_db after reassignment.
var _drone_fade_tweens: Dictionary = {}

# Audio rate-limit for new drone voices, scaled to the autodropper interval
# so pacing tracks gameplay tempo. Cooldown = _autodrop_interval /
# RATE_DIVISOR. Per-type so normal and advanced never block each other.
# Normal: up to 4 hits per autodrop cycle (~375 ms at default 1.5 s).
# Advanced: 1 hit per full cycle (~1500 ms) — slow bass punctuation.
const NORMAL_RATE_DIVISOR := 4.0
const ADVANCED_RATE_DIVISOR := 1.0

# Harmony grace: if a second coin lands within this window of the previous
# accepted activation, allow it through even though the normal cooldown
# hasn't elapsed. Gives multi-drop its two-voice harmony chord without
# opening the door to 3+ voices slamming together (grace is a one-shot
# per burst — third hit still hits the normal cooldown).
const HARMONY_GRACE_WINDOW := 0.2  # 200 ms

var _last_normal_activation_time: float = -999.0
var _last_advanced_activation_time: float = -999.0
var _normal_harmony_grace_used: bool = false
var _advanced_harmony_grace_used: bool = false
var _sparkle_counter: int = 0  # monotonic id for unique sparkle drone keys
# Two drone streams — zen uses the sine pad loop (matches the ambient pad
# texture); lofi uses the FM electric piano one-shot. Selected per-play in
# play_bucket based on the active theme's audio_lofi_enabled flag.
var _sine_drone_stream: AudioStreamWAV
var _piano_drone_stream: AudioStream = preload("res://assets/sounds/instrument_samples/Ensoniq-ESQ-1-FM-Piano-C4.wav")

# Procedural harp — multi-sampled at two pitches so notes never pitch-shift
# more than about an octave from their native sample. This keeps high notes
# from turning tinny (huge upshift amplifies upper harmonics into sibilance)
# and low notes from turning muddy. HIGH sample uses a darker harmonic profile
# so it doesn't sound bright when shifted up to C6-ish territory.
const HARP_LOW_FREQ := 130.81           # C3 — native frequency of low sample
const HARP_HIGH_FREQ := 523.25          # C5 — native frequency of high sample
const HARP_CROSSOVER_FREQ := 261.63     # C4 — below uses low, at/above uses high
const HARP_BASE_FREQ := 261.63          # C4 — used by call sites as the semantic anchor
const HARP_DECAY_SECONDS := 4.0
var _harp_low_stream: AudioStreamWAV    # warm, C3-native
var _harp_high_stream: AudioStreamWAV   # dark, C5-native

# Arcade square-wave instrument — generated at startup, C4-native. Duration
# also governs how long each sparkle rings (sparkles use this same stream
# through the drone pool). Bumped up so they don't feel clipped.
const SQUARE_BASE_FREQ := 261.63        # C4
const SQUARE_DURATION := 1.0            # audible ring length for each note
const KICK_DURATION := 0.18
var _square_stream: AudioStreamWAV
var _kick_stream: AudioStreamWAV
var _kick_player: AudioStreamPlayer

# In the final N seconds of a challenge, the kick drum doubles (2 per second)
# for a visible intensity ramp. No other rhythmic changes happen in arcade.
const FINAL_COUNTDOWN_SECONDS := 10

# Currently-active AudioStyle — null means "use default harp behavior."
# Reselected on theme change or challenge start/end.
var _active_audio_style: AudioStyle = null
# Chord index within the active style's progression (separate from the
# per-board harp progression index).
var _style_chord_index: int = 0
# Whether we've received at least one challenge tick since the active style
# was selected. The arcade backing stays silent until the player's first coin
# drop starts the challenge timer (which produces the first tick).
var _challenge_tick_received: bool = false

# Low-pass filter on the Melody bus — enabled when lofi active, disabled
# otherwise. The index tracks where in the bus effect chain it sits.
const MELODY_LOWPASS_CUTOFF := 3000.0
var _melody_lowpass_effect_idx: int = -1

# ── Lofi drum system ─────────────────────────────────────────────────
# Player drops pick randomly from a pool of snare/clap/rim variants.
# Normal autodropper cycles through a pool of kick variants.
# Advanced autodropper cycles through a pool of hat/rim variants, delayed
# by 0.5s from the tick so it lands on the offbeat.
const DRUM_POOL_PLAYER_VOLUME_DB := -2.0
const DRUM_POOL_KICK_VOLUME_DB := 0.0
const DRUM_POOL_HAT_VOLUME_DB := -6.0
const DRUM_RAPID_FIRE_WINDOW := 0.25  # seconds — drops within this are attenuated
const DRUM_RAPID_FIRE_ATTENUATION_DB := -6.0
const ADVANCED_DRUM_OFFSET := 0.75  # seconds after the autodropper tick — half of 1.5s tick interval

var _player_drum_players: Array[AudioStreamPlayer] = []  # random pick
var _kick_drum_players: Array[AudioStreamPlayer] = []    # cycle
var _hat_drum_players: Array[AudioStreamPlayer] = []     # cycle
var _kick_rotation_idx: int = 0
var _hat_rotation_idx: int = 0
var _last_player_drum_time: float = -999.0

# Bus indices (set in _ready)
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

	# ── Per-board chord progressions ─────────────────────────────────
	# Gold cycles Cmaj7 → Em7 → Fmaj7 → G7 (I-iii-IV-V, 24s full cycle at
	# 6s/chord). Each chord carries a hand-authored motif: an array of
	# chord-tone indices (0..7) and rests (-1). Motifs advance on a 4/4
	# beat grid derived from the autodropper tick. Orange/Red single-chord;
	# placeholder motifs to tune later.
	# Motifs: each index is one beat (quarter note at 4/4). -1 = rest, which
	# extends the prior note's ring (since sparkles share the drone pool and
	# sustain). Rhythm language: note followed by 1 rest = half, 2 rests =
	# dotted half, 3 rests = whole. Most common note length is a half, with
	# occasional quarters for forward motion.
	var default_motif: Array = [0, -1, 2, -1, 4, -1, 5, -1]
	_board_progressions[Enums.BoardType.GOLD] = [
		# Cmaj7 (I) — all halves, ascending outline: root · 5th · 8ve · 8ve+3
		{ "root": 0, "chord": CHORD_MAJ7, "motif": [0, -1, 2, -1, 4, -1, 5, -1] },
		# Em7 (iii) — falling cadence: 7th (half) · 5th (half) · root (whole)
		{ "root": 4, "chord": CHORD_MIN7, "motif": [3, -1, 2, -1, 0, -1, -1, -1] },
		# Fmaj7 — airy lift: 5th (dotted half) · octave (half) · 8ve+3 (dotted half)
		{ "root": 5, "chord": CHORD_MAJ7, "motif": [2, -1, -1, 4, -1, 5, -1, -1] },
		# G7 — tension with kinetic quarter: root (q) · 7th (half) · octave (half) · 5th (dotted half)
		{ "root": 7, "chord": CHORD_DOM7, "motif": [0, 3, -1, 4, -1, 2, -1, -1] },
	]
	_board_progressions[Enums.BoardType.ORANGE] = [
		{ "root": 7, "chord": CHORD_DOM7, "motif": default_motif },  # G7
	]
	_board_progressions[Enums.BoardType.RED] = [
		{ "root": 9, "chord": CHORD_MIN7, "motif": default_motif },  # Am7
	]
	for bt in _board_progressions:
		_current_chord_index[bt] = 0

	# ── Audio buses ──────────────────────────────────────────────────
	_setup_buses()

	# ── Placeholder tones (swap for real samples later) ──────────────
	var cello_stream := _generate_tone(196.0, 0.8)      # G3
	var chime_stream := _generate_chime(784.0, 0.6)      # G5 + shimmer
	var click_stream := _generate_click(0.05)

	# Per-board ambient pad voicings — each board's chord as a 4-note stack.
	# Frequencies chosen to keep the overall pad in the bass/low-mid range.
	_ambient_pad_streams[Enums.BoardType.GOLD] = _generate_ambient_pad(4.0, 44100,
		[130.81, 164.81, 196.00, 246.94])  # Cmaj7: C3 E3 G3 B3
	_ambient_pad_streams[Enums.BoardType.ORANGE] = _generate_ambient_pad(4.0, 44100,
		[98.00, 123.47, 146.83, 174.61])   # G7:    G2 B2 D3 F3
	_ambient_pad_streams[Enums.BoardType.RED] = _generate_ambient_pad(4.0, 44100,
		[110.00, 130.81, 164.81, 196.00])  # Am7:   A2 C3 E3 G3

	# Zen uses a simple sine drone for bucket notes; lofi swaps to the FM piano
	# preload. Generated here so the drone pool has a default stream on startup.
	_sine_drone_stream = _generate_ambient_pad(2.0, 44100, [262.0, 392.0])

	# Procedural harp — two samples so notes never pitch-shift more than ~1
	# octave from their source. The high sample uses a darker profile so it
	# doesn't brighten further when shifted up.
	_harp_low_stream = _generate_harp(HARP_LOW_FREQ, HARP_DECAY_SECONDS, false)
	_harp_high_stream = _generate_harp(HARP_HIGH_FREQ, HARP_DECAY_SECONDS, true)

	# Arcade — square wave + noise-burst kick. Square is staccato (short
	# envelope) so it reads as plucky/bleepy rather than sustained.
	_square_stream = _generate_square(SQUARE_BASE_FREQ, SQUARE_DURATION)
	_kick_stream = _generate_arcade_kick(KICK_DURATION)
	_kick_player = AudioStreamPlayer.new()
	_kick_player.stream = _kick_stream
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
	# Each player's stream is (re)assigned per-play in play_bucket based on
	# the active theme: sine drone for zen, FM piano one-shot for lofi. The
	# default here is the sine stream so players have something valid at
	# construction time.
	for i in BUCKET_DRONE_POOL_SIZE:
		var drone := AudioStreamPlayer.new()
		drone.stream = _sine_drone_stream
		drone.bus = &"Drones"
		drone.volume_db = -80.0
		add_child(drone)
		_drone_pool.append(drone)
		_drone_free.append(i)

	# ── Lofi drum pools ─────────────────────────────────────────────
	# Player drops: snare, clap, rim shot — random pick per drop.
	var player_drum_streams: Array[AudioStreamWAV] = [
		_generate_snare(180.0, 0.18),
		_generate_clap(0.2),
		_generate_rim(400.0, 0.08),
	]
	for stream in player_drum_streams:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = &"Click"
		p.volume_db = DRUM_POOL_PLAYER_VOLUME_DB
		add_child(p)
		_player_drum_players.append(p)

	# Normal autodropper: kick variants — rotating pattern.
	# First = deep foundation. Second = noticeably thinner, higher-pitched,
	# shorter — more of a ticky kick than a boomy one.
	var kick_streams: Array[AudioStreamWAV] = [
		_generate_kick(60.0, 0.22),      # deeper
		_generate_kick(100.0, 0.09),     # thin & ticky
	]
	for stream in kick_streams:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = &"Click"
		p.volume_db = DRUM_POOL_KICK_VOLUME_DB
		add_child(p)
		_kick_drum_players.append(p)

	# Advanced autodropper: single closed hat. Same sound every tick — light
	# and consistent on the offbeat. If we add more variants here later,
	# rotation still works because we reference the array by index.
	var hat_streams: Array[AudioStreamWAV] = [
		_generate_hat(6000.0, 0.05),     # closed
	]
	for stream in hat_streams:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = &"Click"
		p.volume_db = DRUM_POOL_HAT_VOLUME_DB
		add_child(p)
		_hat_drum_players.append(p)

	# Listen for theme swaps so lofi-gated effects (low-pass) can toggle at
	# runtime. Call once to sync initial state against the loaded theme (via
	# call_deferred so ThemeProvider autoload is fully ready).
	ThemeProvider.theme_changed.connect(_on_theme_changed)
	_on_theme_changed.call_deferred()

	# Arcade audio routing: re-select on theme changes, challenge start/end,
	# and per-tick for the backing kick + beat-grid phase-lock.
	ChallengeManager.challenge_state_changed.connect(_reselect_audio_style)
	ChallengeManager.tick.connect(_on_challenge_tick)
	_reselect_audio_style.call_deferred()

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
	_update_bucket_drones(delta)


## Advances the active board's chord index while activity is present. After
## CHORD_IDLE_RESET seconds of inactivity, resets the progression so each new
## session starts grounded on the root chord. If a whole chord elapsed without
## any sparkle firing (no pegs hit), also reset — the board is too quiet to
## sustain the progression and the listener loses the phrasing.
func _tick_harmonic_rhythm(delta: float, has_activity: bool) -> void:
	# When an AudioStyle is active, it owns the chord progression (one global
	# index rather than per-board), advances on a fixed cadence (chord_duration)
	# regardless of peg activity, and doesn't do the "no-sparkle reset" logic
	# since arcade backing keeps the audio alive independent of pegs.
	if _active_audio_style and not _active_audio_style.progression.is_empty():
		_chord_timer -= delta
		if _chord_timer <= 0.0:
			_style_chord_index = (_style_chord_index + 1) % _active_audio_style.progression.size()
			_motif_position = 0
			_chord_timer = _active_audio_style.chord_duration
			_handle_chord_advance()
		return

	if has_activity:
		_chord_idle_timer = 0.0
		_chord_timer -= delta
		if _chord_timer <= 0.0:
			var progression: Array = _board_progressions.get(_active_board, [])
			if not _chord_had_sparkle:
				# Whole chord elapsed with no sparkles — reset to root chord.
				_reset_harmonic_state()
			elif progression.size() > 1:
				_current_chord_index[_active_board] = (_current_chord_index[_active_board] + 1) % progression.size()
				_motif_position = 0
			_chord_timer = CHORD_DURATION
			_chord_had_sparkle = false
			_handle_chord_advance()
	else:
		_chord_idle_timer += delta
		if _chord_idle_timer >= CHORD_IDLE_RESET:
			_chord_idle_timer = 0.0
			_reset_harmonic_state()


func _reset_harmonic_state() -> void:
	for bt in _current_chord_index:
		_current_chord_index[bt] = 0
	_chord_timer = CHORD_DURATION
	_motif_position = 0
	_beat_phase = 0.0
	_beat_armed = true
	_chord_had_sparkle = false
	# Treat the idle reset as a chord change for visuals — buckets need to
	# fade back to their faded color even when silence triggered the reset.
	_handle_chord_advance()


## Selects the applicable AudioStyle based on current theme + challenge state.
## Called on theme changes and challenge start/end. A null result means the
## default harp code path runs unchanged.
func _reselect_audio_style() -> void:
	var desired: AudioStyle = null
	if ThemeProvider and ThemeProvider.theme:
		var style: AudioStyle = ThemeProvider.theme.audio_style
		if style and (not style.active_during_challenge_only or ChallengeManager.is_active_challenge):
			desired = style
	if desired == _active_audio_style:
		return
	# Fade any still-ringing drones from the previous musical world before
	# switching over — avoids the outgoing style bleeding into the new one.
	var transitioning: bool = _active_audio_style != desired
	_active_audio_style = desired
	_style_chord_index = 0
	_motif_position = 0
	_beat_phase = 0.0
	_beat_armed = true
	_challenge_tick_received = false
	if _active_audio_style:
		_chord_timer = _active_audio_style.chord_duration
		_beat_period = 1.0 / float(maxi(1, _active_audio_style.beats_per_tick))
	else:
		_chord_timer = CHORD_DURATION
		_beat_period = _autodrop_interval / float(BEATS_PER_BAR)
	if transitioning:
		_fade_all_drones(1.0)


## Tweens every currently-playing drone's volume to -80 dB over `duration`
## seconds, then stops the player and returns its pool slot. Used to clear the
## previous musical world's lingering notes on style transitions.
func _fade_all_drones(duration: float) -> void:
	for drone_key in _active_drones.keys():
		var drone: Dictionary = _active_drones[drone_key]
		_fade_drone(int(drone["idx"]), duration)
	_active_drones.clear()


func _fade_drone(idx: int, duration: float) -> void:
	_kill_fade_tween(idx)
	var player: AudioStreamPlayer = _drone_pool[idx]
	var tween := create_tween()
	# EASE_OUT on volume_db matches loudness perception — drop fast early,
	# trail off slowly. (Visual fades on Bucket use EASE_IN to match the
	# bucket_pulse motion feel; the asymmetry is intentional.)
	tween.tween_property(player, "volume_db", -80.0, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_finish_drone_fade.bind(idx))
	_drone_fade_tweens[idx] = tween


## Kills any fade tween targeting the given pool slot. Called before a slot
## is reassigned (play_bucket / play_peg_sparkle) or restarted (_fade_drone).
## Prevents an old tween from continuing to drive volume_db on a reused player.
func _kill_fade_tween(idx: int) -> void:
	var tween: Tween = _drone_fade_tweens.get(idx)
	if tween and tween.is_valid():
		tween.kill()
	_drone_fade_tweens.erase(idx)


## Converts a voice count into the dB attenuation for the next allocated
## voice: VOICE_ATTENUATION_RATIO^N expressed in decibels.
func _voice_attenuation_db(voice_count: int) -> float:
	return 20.0 * log(pow(VOICE_ATTENUATION_RATIO, voice_count)) / log(10.0)


## Counts currently-allocated drones matching the requested coin type.
## Used by per-type voice caps + attenuation so normal and advanced pools
## don't interfere with each other.
func _count_drones_of_type(is_advanced: bool) -> int:
	var count: int = 0
	for drone_key in _active_drones:
		var drone: Dictionary = _active_drones[drone_key]
		if drone["state"] == DroneState.SPARKLE:
			continue
		if drone.get("is_advanced", false) == is_advanced:
			count += 1
	return count


## Factory for `_active_drones` entries. Every allocation site goes through
## this so `created_at`, `is_advanced`, and the other fields can't drift
## per-site. `is_advanced` defaults to false so sparkle allocations (which
## never take the parameter) get correct bookkeeping automatically.
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


## Eviction priority for the voice cap: fade LINGERING (trailing tails) before
## SPARKLE (decorative plucks) before ACTIVE (melody in the current chord).
## Higher return value = evict first. Decoupled from enum declaration order.
func _eviction_priority(state: int) -> int:
	match state:
		DroneState.LINGERING: return 2
		DroneState.SPARKLE: return 1
		DroneState.ACTIVE: return 0
		_: return 0


## Voice cap enforcement (per coin-type pool): when the matching pool is at
## its cap, pick the drone with the highest eviction priority from THAT pool
## (oldest first as tiebreaker) and fade it over `eviction_fade_duration` so
## the caller has a free pool slot. No-op below cap.
##
## NOTE: chord advances flip many ACTIVE drones to LINGERING in one frame
## without allocating, so a pool can transiently exceed its cap immediately
## after. That's by design — the compressor on the Drones bus is the safety
## net for that burst; the cap bites on the next allocation and brings the
## count back under.
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
	# Erase first so any subsequent lookups (e.g. during the fade tween's
	# tick callback) can't see a half-dead entry.
	_active_drones.erase(victim_key)
	_fade_drone(int(victim["idx"]), fade_duration)


func _finish_drone_fade(idx: int) -> void:
	var player: AudioStreamPlayer = _drone_pool[idx]
	player.stop()
	_drone_fade_tweens.erase(idx)
	if not _drone_free.has(idx):
		_drone_free.append(idx)


## How long the current chord has left before the next chord_changed emit.
func get_time_until_next_chord() -> float:
	return _chord_timer


## Total length of the current chord (AudioStyle override if active, else
## the default harp-path CHORD_DURATION). Used alongside get_time_until_
## next_chord to compute a normalized 0..1 phase for visual animations.
func get_chord_duration() -> float:
	if _active_audio_style:
		return _active_audio_style.chord_duration
	return CHORD_DURATION


## Current position within the chord as a 0..1 fraction (0 = chord just
## started, 1 = chord about to change). Global — all readers see the same
## value at the same moment, so a shared visual pulse stays in sync across
## every bucket regardless of when each was activated.
func get_chord_phase() -> float:
	var duration: float = get_chord_duration()
	if duration <= 0.0:
		return 0.0
	return clampf(1.0 - (_chord_timer / duration), 0.0, 1.0)


## Rate-limit gate for new drone voices. Returns true if the caller should
## proceed with mark_active + play_bucket; false if still inside the per-type
## cooldown window. Visual activation is intentionally coupled to this gate
## in PlinkoBoard.finalize_coin_landing — a rate-limited hit leaves the
## bucket faded so the next tone-producing coin owns the activation.
## Independent cooldowns per coin type so a normal cadence never blocks an
## advanced hit. A one-shot harmony grace admits a second voice within the
## HARMONY_GRACE_WINDOW (~200 ms) of the previous accepted activation so
## multi-drop produces a two-note chord; the third hit of the same type is
## always gated by the normal cooldown. Grace resets on fresh accept AND in
## the rejection path once elapsed leaves the grace sub-window — without
## the latter, sustained sub-cooldown activity would keep grace permanently
## consumed and kill future bursts' harmony.
func try_consume_bucket_activation(is_advanced: bool = false) -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	var divisor: float = ADVANCED_RATE_DIVISOR if is_advanced else NORMAL_RATE_DIVISOR
	var window: float = _autodrop_interval / divisor
	var last: float = _last_advanced_activation_time if is_advanced else _last_normal_activation_time
	var grace_used: bool = _advanced_harmony_grace_used if is_advanced else _normal_harmony_grace_used
	var elapsed: float = now - last
	if elapsed < window:
		# Inside cooldown — but a brief grace admits one second voice
		# for the harmony case (multi-drop).
		if elapsed < HARMONY_GRACE_WINDOW and not grace_used:
			if is_advanced:
				_advanced_harmony_grace_used = true
				_last_advanced_activation_time = now
			else:
				_normal_harmony_grace_used = true
				_last_normal_activation_time = now
			return true
		# Rejected. Once we're past the grace sub-window the burst is
		# effectively over — reset the grace flag so the *next* burst
		# (starting on a future fresh accept) gets its harmony voice
		# back. Doesn't admit a voice here because elapsed >=
		# HARMONY_GRACE_WINDOW already disqualifies the grace branch
		# above.
		if elapsed >= HARMONY_GRACE_WINDOW and grace_used:
			if is_advanced:
				_advanced_harmony_grace_used = false
			else:
				_normal_harmony_grace_used = false
		return false
	# Fresh accept outside cooldown — reset the grace budget for the next burst.
	if is_advanced:
		_last_advanced_activation_time = now
		_advanced_harmony_grace_used = false
	else:
		_last_normal_activation_time = now
		_normal_harmony_grace_used = false
	return true


## Runs on chord advance (default harp path + AudioStyle path). Chord changes
## are a VISUAL event here — they fire chord_changed so buckets revert to their
## faded color, and flip ACTIVE drones to LINGERING so the bucket-activation
## gate no longer suppresses re-hits. They do NOT fade audio. Lingering drones
## keep ringing naturally via the synthesized decay until a new coin lands
## (handed off by `_fade_lingering_drones`), or until the sample runs out
## (pool slot released by `_update_bucket_drones`).
func _handle_chord_advance() -> void:
	for drone_key in _active_drones.keys():
		var drone: Dictionary = _active_drones[drone_key]
		if drone["state"] == DroneState.ACTIVE:
			drone["state"] = DroneState.LINGERING
			# Pool slot will release once the synthesized decay has run its
			# course, even if no new coin ever lands.
			drone["timer"] = HARP_DECAY_SECONDS
	var idx: int = _style_chord_index if _active_audio_style else _current_chord_index.get(_active_board, 0)
	chord_changed.emit(idx)


## Fades every lingering drone. Called when a new coin lands after a chord
## advance — the new note hands off from the old chord's tail. Audio fade is
## longer than the visual fade so the handoff doesn't feel abrupt against the
## sustained linger; tuned via theme.linger_fade_duration.
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


## Called every second by ChallengeManager.tick. Fires the kick on the
## downbeat and phase-locks the beat grid. In the final 10 seconds a second
## kick fires 0.5s later for a 2/sec intensity ramp.
func _on_challenge_tick(seconds_remaining: int) -> void:
	if not _active_audio_style:
		return
	_challenge_tick_received = true
	_beat_phase = 0.0
	_beat_armed = true
	if _active_audio_style.has_backing_kick:
		_kick_player.play()
		if seconds_remaining <= FINAL_COUNTDOWN_SECONDS:
			get_tree().create_timer(0.5).timeout.connect(_kick_player.play, CONNECT_ONE_SHOT)


## Advances the beat grid. Each boundary bumps the motif position (sparkle
## schedule in harp mode) and arms the next sparkle slot.
func _tick_beat_grid(delta: float) -> void:
	if _active_audio_style and not _challenge_tick_received:
		return
	_beat_phase += delta
	while _beat_phase >= _beat_period:
		_beat_phase -= _beat_period
		_motif_position += 1
		_beat_armed = true


# ── Public API: musical sounds ───────────────────────────────────────

func play_bucket(board_type: Enums.BoardType, bucket_distance_from_center: int, is_advanced: bool = false) -> void:
	if board_type != _active_board:
		return
	_activity_detected = true

	var degree: int = bucket_distance_from_center
	var key: String = ("A_" if is_advanced else "N_") + str(degree)
	var octave_mult: float = 0.25 if is_advanced else 0.5
	var pitch: float = _get_pitch_scale(degree, board_type) * octave_mult
	var target_volume: float = BUCKET_VOLUME_DB + (4.0 if is_advanced else 0.0)

	var sp: Dictionary = _tonal_stream_and_pitch(pitch)

	# First hit of a new chord: fade any drones left lingering from the
	# previous chord. The new note acts as the handoff signal so silence
	# between chords gets filled by the old chord's tones until activity
	# resumes.
	_fade_lingering_drones()

	# Each bucket rings once per chord — re-hits during the same chord are
	# visual-only (PlinkoBoard re-flashes the bucket). Restarting the sample
	# here would create a double-attack inside a still-ringing note.
	# Lingering drones don't gate — _fade_lingering_drones above already
	# cleared them so this branch only sees ACTIVE drones.
	if key in _active_drones and _active_drones[key]["state"] == DroneState.ACTIVE:
		return

	# Eviction runs AFTER _fade_lingering_drones (above) so the linger-clear's
	# natural reduction is counted first — we only evict when genuinely full.
	# Per-type: normal and advanced pools are capped independently.
	_evict_oldest_drone_if_full(is_advanced)
	if _drone_free.is_empty():
		return
	# Exponential per-voice attenuation, filtered by coin type — normal voices
	# only dim behind other normals, advanced only behind other advanceds.
	# Keeps each pool self-limiting without cross-interference between the
	# melodic top layer and the bass punctuation layer.
	var voice_count: int = _count_drones_of_type(is_advanced)
	var voice_attenuation_db: float = _voice_attenuation_db(voice_count)
	var idx: int = _drone_free.pop_back()
	_kill_fade_tween(idx)
	var player: AudioStreamPlayer = _drone_pool[idx]
	player.stream = sp["stream"]
	# Drop buckets one octave below their chord-tone position so they feel
	# like the foundation of the mix rather than a melodic voice up top.
	# Advanced coins drop another octave for extra punch.
	player.pitch_scale = _apply_tape_wobble(sp["pitch_scale"])
	player.volume_db = target_volume + voice_attenuation_db
	player.play()
	var tail: float = maxf(_chord_timer, MIN_BUCKET_RING_SECONDS)
	_active_drones[key] = _make_drone_entry(idx, tail, degree, octave_mult, DroneState.ACTIVE, is_advanced)


## Peg sparkle audio is currently suppressed — it clashes with the chord-gated
## bucket drone layer that carries the melody. Peg ring VFX still fires via
## `should_sparkle` / `_beat_armed`; a follow-up feature will redesign the
## sparkle voice to layer cleanly on top of the bucket melody.
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


## Called when a coin is launched on any board. Keeps the ambient pad alive
## for the whole descent even on large boards where the 2s idle timeout
## would otherwise fade it out between sparkles.
func on_coin_dropped() -> void:
	_active_coin_count += 1
	_activity_detected = true


## Called when a coin finishes landing. Ambient pad starts its fade-out
## timer once this drops the count to 0.
func on_coin_landed() -> void:
	_active_coin_count = maxi(0, _active_coin_count - 1)


## Plays a lofi drum on manual drop button press. Random pick from the player
## drum pool. Rapid-fire drops within DRUM_RAPID_FIRE_WINDOW seconds are
## attenuated so button-mashing doesn't fatigue.
func play_manual_drop_drum(board_type: Enums.BoardType) -> void:
	# Drums disabled while the harp timbre is being developed. Keeps the
	# infrastructure (pools, bus, tick scheduling) intact for easy re-enable.
	return
	if board_type != _active_board:
		return
	if not ThemeProvider.theme.audio_lofi_enabled:
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


## Plays a lofi drum on autodropper tick. Normal autodroppers fire a kick
## immediately (on the beat). Advanced autodroppers fire a hat/rim 0.5s later
## (on the offbeat), creating a boom-chk pattern when both are active.
## Rotates through the pool in order — not randomized.
func play_autodropper_drum(board_type: Enums.BoardType, is_advanced: bool) -> void:
	# Drums disabled while the harp timbre is being developed. Keeps the
	# infrastructure (pools, bus, tick scheduling) intact for easy re-enable.
	return
	if board_type != _active_board:
		return
	if not ThemeProvider.theme.audio_lofi_enabled:
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
	# Re-check active board in case the player switched during the 0.5s delay.
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


func play_bucket_hit() -> void:
	play_bucket(_active_board, 0)


func play_prestige(play_duration: float = 3.0, fade_duration: float = 2.0) -> void:
	pass


# ── Musical internals ────────────────────────────────────────────────

func _get_pitch_scale(scale_degree: int, board_type: Enums.BoardType) -> float:
	var entry: Dictionary = _current_chord_entry(board_type)
	var chord: Array = entry["chord"]
	var semitones: int = chord[scale_degree % chord.size()] + int(entry["root"])
	return pow(2.0, semitones / 12.0)


func _current_chord_entry(board_type: Enums.BoardType) -> Dictionary:
	# When an AudioStyle is active, its own progression overrides the per-board
	# harp progressions. The style is a single progression shared across boards
	# (arcade doesn't need per-board chord variation today).
	if _active_audio_style and not _active_audio_style.progression.is_empty():
		var style_prog: Array = _active_audio_style.progression
		return style_prog[_style_chord_index % style_prog.size()]
	var progression: Array = _board_progressions.get(board_type, _board_progressions[Enums.BoardType.GOLD])
	var idx: int = _current_chord_index.get(board_type, 0)
	return progression[idx % progression.size()]


## Picks the active tonal stream + pitch_scale. Branches on the active style's
## timbre: "square" returns the arcade sample; default falls through to the
## harp multi-sample picker.
func _tonal_stream_and_pitch(pitch_mult: float) -> Dictionary:
	if _active_audio_style and _active_audio_style.timbre == "square":
		return { "stream": _square_stream, "pitch_scale": pitch_mult }
	return _harp_stream_and_pitch(pitch_mult)


## Tape wobble: a tiny sine LFO applied to pitch for lofi's analog feel.
## Disabled while the harp timbre is being developed — the pitch drift
## reads as "old recording" and fights the clean harp character.
func _apply_tape_wobble(pitch: float) -> float:
	return pitch
	if not ThemeProvider.theme.audio_lofi_enabled:
		return pitch
	var t: float = Time.get_ticks_msec() / 1000.0
	return pitch * (1.0 + sin(t * 3.0) * 0.004)


## Whether the given board is the one currently in view. Used by non-audio
## systems (peg VFX, sparkle triggers) to silence inactive boards.
func is_active_board(board_type: Enums.BoardType) -> bool:
	return board_type == _active_board


## Beat-grid sparkle gate. Returns true at most once per beat slot, the first
## time a peg hits while the beat is armed AND the motif position has a real
## note (not a rest). Rests consume the beat but return false so peg VFX stay
## silent on rest beats. Always flags _chord_had_sparkle on a consumed beat
## so the progression doesn't mistake a rest-heavy chord for "no activity."
func should_sparkle(board_type: Enums.BoardType) -> bool:
	if board_type != _active_board:
		return false
	if not _beat_armed:
		return false
	_beat_armed = false
	var motif: Array = _current_chord_entry(board_type).get("motif", [0])
	var note: int = motif[_motif_position % motif.size()]
	_chord_had_sparkle = true
	return note >= 0


## Called by BoardManager on each autodropper tick. Snaps the beat grid phase
## to this moment and refreshes the beat period from the current tick interval
## so sparkle cadence stays derived from (not hardcoded relative to) the drum.
func notify_autodropper_beat(interval: float) -> void:
	_autodrop_interval = interval
	_beat_period = interval / float(BEATS_PER_BAR)
	_beat_phase = 0.0
	_motif_position += 1
	_beat_armed = true


# ── Ambient pad ──────────────────────────────────────────────────────

func _fade_in_ambient() -> void:
	# Ambient pad disabled for now — was feeling over-dense with the drums
	# and bucket drones already in the mix. Early-return keeps the rest of
	# the pad infrastructure intact for easy re-enable later.
	return
	_ambient_fading_in = true
	if not _ambient_active.playing:
		# Stream is pre-voiced per board; no pitch shift needed.
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

	# Fade out old
	if old_player.playing:
		var out_tween := create_tween()
		out_tween.tween_property(old_player, "volume_db", -80.0, AMBIENT_FADE_DURATION)
		out_tween.tween_callback(old_player.stop)

	# Fade in new with the new board's pre-voiced chord stream.
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
		# ACTIVE drones are chord-managed (chord advance flips to LINGERING);
		# the timer-based ramp would cut them off mid-chord if a coin landed
		# near the chord's end, so skip them entirely.
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


## Returns the pitch multiplier for an instrument rooted at C4 to play at the
## given board's root note. Used by drums to stay consonant with the chord
## progression. The ambient pad no longer uses this — each board has its
## own pre-voiced pad stream.
func _get_ambient_pitch(board_type: Enums.BoardType) -> float:
	var entry: Dictionary = _current_chord_entry(board_type)
	var semitones: int = int(entry["root"])
	return pow(2.0, semitones / 12.0)


# ── Theme-gated lofi effects ─────────────────────────────────────────

func _on_theme_changed() -> void:
	if not ThemeProvider.theme:
		return

	# Low-pass filter kept off while the harp is being developed — the 3 kHz
	# cutoff was part of what made the sound read as "old movie." Re-enable
	# by restoring the lofi gate: `var lofi := ...; set_bus_effect_enabled(..., lofi)`.
	if _melody_bus_idx >= 0 and _melody_lowpass_effect_idx >= 0:
		AudioServer.set_bus_effect_enabled(_melody_bus_idx, _melody_lowpass_effect_idx, false)

	_reselect_audio_style()


# ── Audio bus setup ──────────────────────────────────────────────────

func _setup_buses() -> void:
	# Add buses if they don't already exist
	if AudioServer.get_bus_index(&"Melody") < 0:
		_melody_bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_melody_bus_idx, &"Melody")
		AudioServer.set_bus_send(_melody_bus_idx, &"Master")
		# Reverb muted while the harp is being developed — Godot's built-in
		# room reverb has an 80s/90s digital character that fights the dry
		# plucked tone. Re-enable by raising wet (e.g. 0.15-0.25).
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.55
		reverb.wet = 0.0
		reverb.dry = 1.0
		reverb.damping = 0.7
		AudioServer.add_bus_effect(_melody_bus_idx, reverb)
		# Low-pass filter for lofi warmth — disabled by default, toggled via
		# _on_theme_changed when the lofi theme is active.
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

	# Dedicated drone-voice bus. Compressor first (tames the dry stack as
	# voice count grows), then reverb (small-room "glue", blooms off the
	# compressed signal — order matters; reverb-before-comp would pump the
	# tail with every new hit).
	if AudioServer.get_bus_index(&"Drones") < 0:
		_drones_bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_drones_bus_idx, &"Drones")
		AudioServer.set_bus_send(_drones_bus_idx, &"Master")
		var comp := AudioEffectCompressor.new()
		comp.threshold = -18.0
		comp.ratio = 3.0
		comp.attack_us = 10000.0  # 10 ms
		comp.release_ms = 500.0
		AudioServer.add_bus_effect(_drones_bus_idx, comp)
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.4
		reverb.damping = 0.5
		reverb.wet = 0.2
		reverb.dry = 0.8
		reverb.hipass = 0.2  # cut muddy low-end buildup on dense stacks
		AudioServer.add_bus_effect(_drones_bus_idx, reverb)
	else:
		_drones_bus_idx = AudioServer.get_bus_index(&"Drones")


# ── Placeholder tone generation ──────────────────────────────────────
# These are replaced with preloaded samples once real audio arrives.

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


## Picks the closer-pitched harp sample for the target pitch multiplier (where
## 1.0 = C4), and returns the pitch_scale needed on that sample to hit it.
## Keeps pitch-shifting to under one octave in either direction.
func _harp_stream_and_pitch(pitch_mult: float) -> Dictionary:
	var target_freq: float = HARP_BASE_FREQ * pitch_mult
	var use_high: bool = target_freq >= HARP_CROSSOVER_FREQ
	var native_freq: float = HARP_HIGH_FREQ if use_high else HARP_LOW_FREQ
	return {
		"stream": _harp_high_stream if use_high else _harp_low_stream,
		"pitch_scale": target_freq / native_freq,
	}


## Procedural harp: additive synthesis of the harmonic series with per-harmonic
## exponential decay. The fundamental sustains slowly (seconds); upper harmonics
## decay fast, which gives the initial attack brightness that mellows into a
## pure-ish sustained tone. A very brief noise burst in the first ~15ms sells
## the "plucked" character. When `darker` is true, upper harmonics are further
## attenuated and decay even faster — used for the high-register sample so it
## doesn't sound tinny when pitch-shifted up another octave.
## Procedural arcade square wave. Short envelope (sharp attack, brief sustain,
## quick release) yields a staccato "bleep" rather than a sustained pad.
func _generate_square(freq: float, duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var attack: float = 0.004
	var release_start: float = duration * 0.55
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var env: float = 1.0
		if t < attack:
			env = t / attack
		elif t > release_start:
			env = maxf(0.0, 1.0 - (t - release_start) / (duration - release_start))
		var sq: float = 1.0 if sin(TAU * freq * t) >= 0.0 else -1.0
		var value: float = sq * env * 0.22
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav


## Procedural arcade kick: low-frequency sine with a downward pitch sweep and
## a fast exponential decay. Evokes a classic "boom" without needing a sample.
func _generate_arcade_kick(duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var phase: float = 0.0
	for i in num_samples:
		var t: float = float(i) / mix_rate
		# Pitch sweep from 180 Hz down to 50 Hz over the sample length.
		var freq: float = lerpf(180.0, 50.0, minf(1.0, t / duration))
		phase += TAU * freq / float(mix_rate)
		var env: float = exp(-t * 18.0)
		# Tiny click at the very start for snap.
		if t < 0.003:
			env += (1.0 - t / 0.003) * 0.4
		var value: float = sin(phase) * env * 0.55
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav


func _generate_harp(freq: float, duration: float, darker: bool, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	# Harmonic weights — warm profile keeps some body in uppers; dark profile
	# rolls off hard so the high-register sample stays round even at C6.
	var harmonics: Array[float]
	var decays: Array[float]
	# Fundamental decay constants tuned against the 4-second HARP_DECAY_SECONDS
	# window — fundamental rings most of the sample, upper partials fade fast
	# so the attack is bright but the tail settles into a pure-ish sustained
	# tone. Darker profile rolls upper partials off harder.
	if darker:
		harmonics = [1.0, 0.30, 0.08, 0.02, 0.006, 0.002, 0.0005, 0.0001, 0.00005, 0.00002]
		decays    = [0.5, 0.9, 1.5, 3.0, 6.0, 10.0, 16.0, 24.0, 35.0, 50.0]
	else:
		harmonics = [1.0, 0.45, 0.20, 0.08, 0.04, 0.02, 0.01, 0.005, 0.003, 0.002]
		decays    = [0.5, 0.7, 1.2, 2.0, 3.0, 5.0, 7.0, 9.0, 12.0, 16.0]

	# Inharmonicity coefficient — real plucked strings have partials slightly
	# sharp of integer multiples (f · n · (1 + B·n²)). Using a small B value
	# breaks the perfectly periodic waveform and reads as "organic."
	const INHARMONICITY: float = 0.0003

	# Linear tail fade over the last TAIL_FADE seconds of the sample so the
	# stream ends at true zero amplitude. Without this, the fundamental's slow
	# exponential decay is still ~14% loud when the 4-second sample file ends,
	# and the player cuts off mid-tone producing an audible click/snap.
	const TAIL_FADE: float = 0.3
	var tail_start: float = duration - TAIL_FADE

	for i in num_samples:
		var t: float = float(i) / mix_rate
		var value: float = 0.0
		for h in harmonics.size():
			var n: float = float(h + 1)
			var harmonic_freq: float = freq * n * (1.0 + INHARMONICITY * n * n)
			var env: float = exp(-t * decays[h])
			value += sin(TAU * harmonic_freq * t) * harmonics[h] * env
		# Brief attack noise for pluck transient — kept subtle so it doesn't
		# add to the overall brightness of the sustained tone.
		if t < 0.015:
			value += randf_range(-1.0, 1.0) * (1.0 - t / 0.015) * 0.15
		value *= 0.45
		if t > tail_start:
			value *= (duration - t) / TAIL_FADE
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
		# Fundamental + 3rd harmonic for shimmer
		var value: float = (sin(TAU * freq * t) * 0.6 + sin(TAU * freq * 3.0 * t) * 0.2) * env * 0.35
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav


func _generate_click(duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var env: float = exp(-t * 60.0)
		var value: float = randf_range(-1.0, 1.0) * env * 0.3
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
	# Each frequency's cycles should land on zero-crossings at the loop
	# boundary to avoid pops. For a 4-second loop, any integer-Hz
	# frequency auto-aligns (since N seconds * F Hz = integer cycles).
	# Slow 0.25 Hz amplitude modulation adds a gentle breath so the pad
	# doesn't feel static.
	# Amplitude per voice scales so the sum doesn't clip.
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


# ── Drum generators ──────────────────────────────────────────────────

func _generate_kick(freq: float, duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	# Pitch-swept sine from freq*2.5 down to freq over first 15% of duration,
	# then sustained + exponential decay. Short click noise burst at t=0 for attack.
	var sweep_len: float = duration * 0.15
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var freq_at_t: float
		if t < sweep_len:
			freq_at_t = lerpf(freq * 2.5, freq, t / sweep_len)
		else:
			freq_at_t = freq
		var env: float = exp(-t * 8.0)
		var body: float = sin(TAU * freq_at_t * t) * env
		var click: float = 0.0
		if t < 0.003:
			click = randf_range(-1.0, 1.0) * (1.0 - t / 0.003) * 0.3
		var value: float = (body + click) * 0.7
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav


func _generate_snare(freq: float, duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	# Tonal body at freq + mid-range noise burst, both with exponential decay.
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var env: float = exp(-t * 15.0)
		var body: float = sin(TAU * freq * t) * env * 0.3
		var noise: float = randf_range(-1.0, 1.0) * env * 0.5
		var value: float = (body + noise) * 0.6
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav


func _generate_hat(freq: float, duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	# High-freq noise burst with fast decay. Slight tonal shimmer at freq.
	var decay_rate: float = 4.0 / duration
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var env: float = exp(-t * decay_rate)
		var noise: float = randf_range(-1.0, 1.0) * env * 0.6
		var shimmer: float = sin(TAU * freq * t) * env * 0.1
		var value: float = (noise + shimmer) * 0.5
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav


func _generate_clap(duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	# 3 layered noise bursts ~15ms apart for a "clap" impression, then sustain.
	var burst_offsets: Array[float] = [0.0, 0.013, 0.026]
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var value: float = 0.0
		for offset in burst_offsets:
			var dt: float = t - offset
			if dt >= 0.0:
				var env: float = exp(-dt * 40.0)
				value += randf_range(-1.0, 1.0) * env * 0.35
		# Trailing noise tail for body
		var tail_env: float = exp(-t * 20.0) * 0.2
		value += randf_range(-1.0, 1.0) * tail_env
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav


func _generate_rim(freq: float, duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	# Tight tonal click — narrow sine + very brief noise.
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var env: float = exp(-t * 35.0)
		var tonal: float = sin(TAU * freq * t) * env * 0.5
		var click: float = 0.0
		if t < 0.005:
			click = randf_range(-1.0, 1.0) * (1.0 - t / 0.005) * 0.4
		var value: float = (tonal + click) * 0.55
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav


