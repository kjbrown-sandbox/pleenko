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

# Pentatonic scale: semitone offsets from root. Wraps for larger bucket counts.
const PENTATONIC := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21]

# Pachelbel Canon progression: board_type → semitone offset from C
var _board_keys: Dictionary = {}

const MELODY_POOL_SIZE := 12
const CLICK_POOL_SIZE := 8
const MAX_MELODY_PER_SECOND := 8
const AMBIENT_FADE_DURATION := 2.0
const AMBIENT_IDLE_TIMEOUT := 2.0
const AMBIENT_VOLUME_DB := -6.0
const PEG_SPARKLE_CHANCE := 0.25
const PEG_CLICK_VOLUME_DB := -18.0
const PEG_SPARKLE_VOLUME_DB := -14.0
const BUCKET_VOLUME_DB := -8.0

var _cello_pool: Array[AudioStreamPlayer] = []
var _chime_pool: Array[AudioStreamPlayer] = []
var _click_pool: Array[AudioStreamPlayer] = []
var _cello_idx: int = 0
var _chime_idx: int = 0
var _click_idx: int = 0

var _active_board: Enums.BoardType = Enums.BoardType.GOLD
var _melody_timestamps: Array[float] = []

# Ambient pad double-buffer
var _ambient_a: AudioStreamPlayer
var _ambient_b: AudioStreamPlayer
var _ambient_active: AudioStreamPlayer
var _ambient_pad_stream: AudioStreamWAV
var _ambient_fading_in: bool = false
var _idle_timer: float = 0.0
var _activity_detected: bool = false

# Bucket drones: one sustained note per unique bucket pitch. Each bucket's note
# starts on first hit and extends on repeat hits. Fades after SUSTAIN seconds idle.
const BUCKET_DRONE_SUSTAIN := 2.0
const BUCKET_DRONE_FADE_RATE := 60.0  # dB/sec during fade-out
const BUCKET_DRONE_POOL_SIZE := 16
var _drone_pool: Array[AudioStreamPlayer] = []
var _drone_free: Array[int] = []
var _active_drones: Dictionary = {}  # String key -> { "idx": int, "timer": float }

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

	# ── Board key mapping (Pachelbel I–V–vi–iii–IV–I) ────────────────
	_board_keys[Enums.BoardType.GOLD] = 0      # C  (I)
	_board_keys[Enums.BoardType.ORANGE] = 7    # G  (V)
	_board_keys[Enums.BoardType.RED] = 9       # Am (vi)
	# Future boards: iii = +4 (Em), IV = +5 (F), I' = +12 (C octave)

	# ── Audio buses ──────────────────────────────────────────────────
	_setup_buses()

	# ── Placeholder tones (swap for real samples later) ──────────────
	var cello_stream := _generate_tone(196.0, 0.8)      # G3
	var chime_stream := _generate_chime(1568.0, 0.6)     # G6 + shimmer
	var click_stream := _generate_click(0.05)
	_ambient_pad_stream = _generate_ambient_pad(4.0)

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
	_ambient_a = AudioStreamPlayer.new()
	_ambient_a.stream = _ambient_pad_stream
	_ambient_a.bus = &"Ambient"
	_ambient_a.volume_db = -80.0
	add_child(_ambient_a)

	_ambient_b = AudioStreamPlayer.new()
	_ambient_b.stream = _ambient_pad_stream
	_ambient_b.bus = &"Ambient"
	_ambient_b.volume_db = -80.0
	add_child(_ambient_b)

	_ambient_active = _ambient_a

	# ── Bucket drone pool ───────────────────────────────────────────
	var drone_stream := _generate_ambient_pad(2.0, 44100, 262.0, 392.0)
	for i in BUCKET_DRONE_POOL_SIZE:
		var drone := AudioStreamPlayer.new()
		drone.stream = drone_stream
		drone.bus = &"Melody"
		drone.volume_db = -80.0
		add_child(drone)
		_drone_pool.append(drone)
		_drone_free.append(i)

	set_process(true)


func _process(delta: float) -> void:
	if _activity_detected:
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

	if key in _active_drones:
		_active_drones[key].timer = BUCKET_DRONE_SUSTAIN
		var player: AudioStreamPlayer = _drone_pool[_active_drones[key].idx]
		if player.volume_db < BUCKET_VOLUME_DB - 1.0:
			player.volume_db = BUCKET_VOLUME_DB
		return

	if _drone_free.is_empty():
		return
	var idx: int = _drone_free.pop_back()
	var player: AudioStreamPlayer = _drone_pool[idx]
	var pitch: float = _get_pitch_scale(degree, board_type)
	if is_advanced:
		pitch *= 0.5
	player.pitch_scale = pitch
	player.volume_db = BUCKET_VOLUME_DB + (4.0 if is_advanced else 0.0)
	player.play()
	_active_drones[key] = { "idx": idx, "timer": BUCKET_DRONE_SUSTAIN }


func play_peg_sparkle(board_type: Enums.BoardType) -> void:
	if board_type != _active_board:
		return
	if not _check_density():
		return
	_activity_detected = true
	var degree: int = randi() % 5
	var pitch := _get_pitch_scale(degree, board_type)
	var player: AudioStreamPlayer = _chime_pool[_chime_idx]
	_chime_idx = (_chime_idx + 1) % _chime_pool.size()
	player.pitch_scale = pitch
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
	var semitones: int = PENTATONIC[scale_degree % PENTATONIC.size()]
	semitones += _board_keys.get(board_type, 0)
	return pow(2.0, semitones / 12.0)


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
		_ambient_active.pitch_scale = _get_ambient_pitch(_active_board)
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

	# Fade in new at the new key
	if _ambient_fading_in:
		new_player.pitch_scale = _get_ambient_pitch(board_type)
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


func _get_ambient_pitch(board_type: Enums.BoardType) -> float:
	var semitones: int = _board_keys.get(board_type, 0)
	return pow(2.0, semitones / 12.0)


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


func _generate_ambient_pad(duration: float, mix_rate: int = 44100, freq_root: float = 131.0, freq_fifth: float = 196.0) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = int(duration * mix_rate)
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	# Both 131 Hz and 196 Hz complete exact integer cycles in 4 seconds
	# (524 and 784), so the waveform is at zero-crossing at the loop
	# boundary — no envelope needed for seamless looping.
	# Slow amplitude modulation (0.25 Hz = one full breath per 4s loop)
	# gives the pad a gentle pulse so it doesn't feel static.
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var breath: float = 0.7 + 0.3 * sin(TAU * 0.25 * t)
		var value: float = (sin(TAU * freq_root * t) * 0.5 + sin(TAU * freq_fifth * t) * 0.3) * breath * 0.3
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
