extends Node

## Pool of AudioStreamPlayers per sound for overlapping playback.
## Bucket hits are capped at MAX_BUCKET_SOUNDS concurrent plays — extras are silently dropped.

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

# Pachelbel progression I-V-vi-iii-IV-I with 7ths added. Each board knows its
# chord root offset (semitones from C) and its chord quality. All chord tones
# across all boards are diatonic to C major — cross-board multi-drops stay
# consonant.
var _board_chords: Dictionary = {}  # BoardType -> { "root": int, "chord": Array }

const MELODY_POOL_SIZE := 12
const CLICK_POOL_SIZE := 8
const MAX_MELODY_PER_SECOND := 8
const AMBIENT_FADE_DURATION := 2.0
const AMBIENT_IDLE_TIMEOUT := 2.0
const AMBIENT_VOLUME_DB := -6.0
const PEG_SPARKLE_CHANCE := 0.5
const PEG_CLICK_VOLUME_DB := -18.0
const PEG_SPARKLE_VOLUME_DB := -8.0
const BUCKET_VOLUME_DB := -8.0

var _cello_pool: Array[AudioStreamPlayer] = []
var _chime_pool: Array[AudioStreamPlayer] = []
var _click_pool: Array[AudioStreamPlayer] = []
var _cello_idx: int = 0
var _chime_idx: int = 0
var _click_idx: int = 0

var _active_board: Enums.BoardType = Enums.BoardType.GOLD
var _melody_timestamps: Array[float] = []

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

# Bucket drones: one sustained note per unique bucket pitch. Each bucket's note
# starts on first hit and extends on repeat hits. Fades after SUSTAIN seconds idle.
const BUCKET_DRONE_SUSTAIN := 3.0
const BUCKET_DRONE_FADE_RATE := 24.0  # dB/sec — ~3s tail from -8 to -80 dB
const BUCKET_DRONE_POOL_SIZE := 16
var _drone_pool: Array[AudioStreamPlayer] = []
var _drone_free: Array[int] = []
var _active_drones: Dictionary = {}  # String key -> { "idx": int, "timer": float }
# Two drone streams — zen uses the sine pad loop (matches the ambient pad
# texture); lofi uses the FM electric piano one-shot. Selected per-play in
# play_bucket based on the active theme's audio_lofi_enabled flag.
var _sine_drone_stream: AudioStreamWAV
var _piano_drone_stream: AudioStream = preload("res://assets/sounds/instrument_samples/Ensoniq-ESQ-1-FM-Piano-C4.wav")

# Vinyl crackle bed — continuous texture under the ambient pad when lofi
# active. Fades in/out via the theme_changed handler.
const CRACKLE_VOLUME_DB := -28.0
const CRACKLE_FADE_DURATION := 1.0
var _crackle_player: AudioStreamPlayer

# Low-pass filter on the Melody bus — enabled when lofi active, disabled
# otherwise. The index tracks where in the bus effect chain it sits.
const MELODY_LOWPASS_CUTOFF := 3000.0
var _melody_lowpass_effect_idx: int = -1

# ── Lofi drum system ─────────────────────────────────────────────────
# Player drops pick randomly from a pool of snare/clap/rim variants.
# Normal autodropper cycles through a pool of kick variants.
# Advanced autodropper cycles through a pool of hat/rim variants, delayed
# by 0.5s from the tick so it lands on the offbeat.
const DRUM_POOL_PLAYER_VOLUME_DB := 2.0
const DRUM_POOL_KICK_VOLUME_DB := 4.0
const DRUM_POOL_HAT_VOLUME_DB := -2.0
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

	# ── Board chord mapping (Pachelbel I–V–vi–iii–IV–I with 7ths) ────
	_board_chords[Enums.BoardType.GOLD] = { "root": 0, "chord": CHORD_MAJ7 }    # Cmaj7 (I)
	_board_chords[Enums.BoardType.ORANGE] = { "root": 7, "chord": CHORD_DOM7 }  # G7    (V)
	_board_chords[Enums.BoardType.RED] = { "root": 9, "chord": CHORD_MIN7 }     # Am7   (vi)
	# Future boards: iii = Em7 (root 4, MIN7), IV = Fmaj7 (root 5, MAJ7),
	# I' = Cmaj7 octave (root 12, MAJ7).

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

	# Vinyl crackle bed — averaged white noise with occasional pops.
	var crackle_stream := _generate_vinyl_crackle(6.0)

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

	# ── Vinyl crackle player ────────────────────────────────────────
	_crackle_player = AudioStreamPlayer.new()
	_crackle_player.stream = crackle_stream
	_crackle_player.bus = &"Ambient"
	_crackle_player.volume_db = -80.0
	add_child(_crackle_player)

	# ── Bucket drone pool ───────────────────────────────────────────
	# Each player's stream is (re)assigned per-play in play_bucket based on
	# the active theme: sine drone for zen, FM piano one-shot for lofi. The
	# default here is the sine stream so players have something valid at
	# construction time.
	for i in BUCKET_DRONE_POOL_SIZE:
		var drone := AudioStreamPlayer.new()
		drone.stream = _sine_drone_stream
		drone.bus = &"Melody"
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

	# Listen for theme swaps so lofi-gated effects (low-pass, crackle) can
	# toggle at runtime. Call once to sync initial state against the loaded
	# theme (via call_deferred so ThemeProvider autoload is fully ready).
	ThemeProvider.theme_changed.connect(_on_theme_changed)
	_on_theme_changed.call_deferred()

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

	_update_bucket_drones(delta)


# ── Public API: musical sounds ───────────────────────────────────────

func play_bucket(board_type: Enums.BoardType, bucket_distance_from_center: int, is_advanced: bool = false) -> void:
	if board_type != _active_board:
		return
	_activity_detected = true

	var degree: int = bucket_distance_from_center
	var key: String = ("A_" if is_advanced else "N_") + str(degree)
	var lofi: bool = ThemeProvider.theme.audio_lofi_enabled

	if key in _active_drones:
		_active_drones[key].timer = BUCKET_DRONE_SUSTAIN
		var player: AudioStreamPlayer = _drone_pool[_active_drones[key].idx]
		if player.volume_db < BUCKET_VOLUME_DB - 1.0:
			player.volume_db = BUCKET_VOLUME_DB
		# Retrigger fix for one-shot piano samples: if the sample has decayed
		# to silence while the slot is still "active", re-play it on the next
		# bucket hit. Sine drones loop, so they're always .playing — no-op for zen.
		if not player.playing:
			player.play()
		return

	if _drone_free.is_empty():
		return
	var idx: int = _drone_free.pop_back()
	var player: AudioStreamPlayer = _drone_pool[idx]
	player.stream = _piano_drone_stream if lofi else _sine_drone_stream
	# Drop buckets one octave below their chord-tone position so they feel
	# like the foundation of the mix rather than a melodic voice up top.
	var pitch: float = _get_pitch_scale(degree, board_type) * 0.5
	if is_advanced:
		pitch *= 0.5  # advanced coins: another octave down for extra punch
	player.pitch_scale = _apply_tape_wobble(pitch)
	player.volume_db = BUCKET_VOLUME_DB + (4.0 if is_advanced else 0.0)
	player.play()
	_active_drones[key] = { "idx": idx, "timer": BUCKET_DRONE_SUSTAIN }


func play_peg_sparkle(board_type: Enums.BoardType) -> void:
	if board_type != _active_board:
		return
	if not _check_density():
		return
	_activity_detected = true
	# Pick from the full chord range (8 chord tones including octave-up set)
	# so sparkles feel airier and more varied — not just hovering around the root.
	var degree: int = randi() % 8
	var pitch := _get_pitch_scale(degree, board_type)
	var player: AudioStreamPlayer = _chime_pool[_chime_idx]
	_chime_idx = (_chime_idx + 1) % _chime_pool.size()
	player.pitch_scale = _apply_tape_wobble(pitch)
	player.play()


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
	var board_chord: Dictionary = _board_chords.get(board_type, _board_chords[Enums.BoardType.GOLD])
	var chord: Array = board_chord["chord"]
	var semitones: int = chord[scale_degree % chord.size()]
	semitones += board_chord["root"]
	return pow(2.0, semitones / 12.0)


## Tape wobble: a tiny sine LFO applied to pitch for lofi's analog feel.
## Returns pitch unchanged for non-lofi themes.
func _apply_tape_wobble(pitch: float) -> float:
	if not ThemeProvider.theme.audio_lofi_enabled:
		return pitch
	var t: float = Time.get_ticks_msec() / 1000.0
	return pitch * (1.0 + sin(t * 3.0) * 0.004)


func _check_density() -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	while not _melody_timestamps.is_empty() and now - _melody_timestamps[0] >= 1.0:
		_melody_timestamps.remove_at(0)
	if _melody_timestamps.size() >= MAX_MELODY_PER_SECOND:
		return false
	_melody_timestamps.append(now)
	return true


# ── Ambient pad ──────────────────────────────────────────────────────

func _fade_in_ambient() -> void:
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
		drone.timer -= delta
		if drone.timer <= 0.0:
			var player: AudioStreamPlayer = _drone_pool[drone.idx]
			player.volume_db = move_toward(player.volume_db, -80.0, BUCKET_DRONE_FADE_RATE * delta)
			if player.volume_db <= -79.0:
				player.stop()
				_drone_free.append(drone.idx)
				expired.append(drone_key)
	for key: String in expired:
		_active_drones.erase(key)


## Returns the pitch multiplier for an instrument rooted at C4 to play at the
## given board's root note. Used by drums to stay consonant with the chord
## progression. The ambient pad no longer uses this — each board has its
## own pre-voiced pad stream.
func _get_ambient_pitch(board_type: Enums.BoardType) -> float:
	var board_chord: Dictionary = _board_chords.get(board_type, _board_chords[Enums.BoardType.GOLD])
	var semitones: int = board_chord["root"]
	return pow(2.0, semitones / 12.0)


# ── Theme-gated lofi effects ─────────────────────────────────────────

func _on_theme_changed() -> void:
	if not ThemeProvider.theme:
		return
	var lofi: bool = ThemeProvider.theme.audio_lofi_enabled

	# Toggle the Melody bus low-pass filter.
	if _melody_bus_idx >= 0 and _melody_lowpass_effect_idx >= 0:
		AudioServer.set_bus_effect_enabled(_melody_bus_idx, _melody_lowpass_effect_idx, lofi)

	# Fade the crackle bed in/out.
	if _crackle_player:
		var tween := create_tween()
		if lofi:
			if not _crackle_player.playing:
				_crackle_player.volume_db = -80.0
				_crackle_player.play()
			tween.tween_property(_crackle_player, "volume_db", CRACKLE_VOLUME_DB, CRACKLE_FADE_DURATION)
		else:
			tween.tween_property(_crackle_player, "volume_db", -80.0, CRACKLE_FADE_DURATION)
			tween.tween_callback(_crackle_player.stop)


# ── Audio bus setup ──────────────────────────────────────────────────

func _setup_buses() -> void:
	# Add buses if they don't already exist
	if AudioServer.get_bus_index(&"Melody") < 0:
		_melody_bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_melody_bus_idx, &"Melody")
		AudioServer.set_bus_send(_melody_bus_idx, &"Master")
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.85
		reverb.wet = 0.4
		reverb.dry = 0.6
		reverb.damping = 0.5
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


# ── Vinyl crackle generator ──────────────────────────────────────────

## Generates a seamless loop of vinyl-crackle texture: pops and clicks at
## varying amplitudes, with near-silent space between. No constant white-noise
## hiss — just occasional crackle events, with a small chance of forming
## clusters so it feels like actual vinyl defects rather than ambient noise.
func _generate_vinyl_crackle(duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = int(duration * mix_rate)
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	# Pre-generate pop events. Each has a position and amplitude. Every pop
	# has a 15% chance of spawning a short cluster of follow-up pops, which
	# gives the impression of actual vinyl damage rather than evenly spaced ticks.
	var pop_events: Array[Dictionary] = []
	var pops_per_second: float = 7.0
	var total_pops := int(duration * pops_per_second)
	for i in total_pops:
		var pos := randi() % num_samples
		pop_events.append({ "pos": pos, "amp": randf_range(0.3, 1.0) })
		if randf() < 0.15:
			var cluster_size: int = randi_range(1, 3)
			for j in cluster_size:
				var delay := randi_range(int(mix_rate * 0.003), int(mix_rate * 0.015))
				pop_events.append({
					"pos": (pos + delay * (j + 1)) % num_samples,
					"amp": randf_range(0.2, 0.6)
				})

	# Very subtle room presence — almost inaudible (0.015 amplitude vs the
	# old 0.5). Provides a hint of texture without being a constant hiss.
	var prev_sample: float = 0.0
	for i in num_samples:
		var raw: float = randf_range(-1.0, 1.0)
		var hum: float = prev_sample * 0.85 + raw * 0.15
		prev_sample = hum
		var value: float = hum * 0.015

		# Layer in any pop events that fire within the next 30 samples.
		for event: Dictionary in pop_events:
			var dist: int = i - event["pos"]
			if dist >= 0 and dist < 30:
				var pop_env: float = exp(-float(dist) * 0.25)
				value += randf_range(-1.0, 1.0) * pop_env * event["amp"]

		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
