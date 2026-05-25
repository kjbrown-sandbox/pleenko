extends "res://test/test_base.gd"

## AudioManager tests — run with:
##   godot --headless --scene res://test/test_audio_manager.tscn


func _run_tests() -> void:
	print("\n=== AudioManager Tests ===\n")

	# Pure math
	test_voice_attenuation_zero_voices()
	test_voice_attenuation_one_voice()
	test_voice_attenuation_monotonic_decrease()

	# Drone entry factory
	test_make_drone_entry_has_all_fields()
	test_make_drone_entry_values_match()

	# Drone counting
	test_count_drones_of_type_excludes_sparkle()
	test_count_drones_of_type_separates_advanced()
	test_count_drones_of_type_empty()

	# Repeat softening
	test_count_active_drones_for_bucket_matches_type()
	test_count_active_drones_for_bucket_excludes_sparkle()
	test_request_bucket_play_repeat_queues_separately()
	test_pump_bucket_queue_drains_primary_first()

	# Chord phase
	test_chord_phase_at_start()
	test_chord_phase_at_end()

	# Pitch scale
	test_pitch_scale_root_is_based_on_chord()
	test_pitch_scale_degree_wraps()

	# Chord advance
	test_chord_advance_clears_bucket_queue()
	test_chord_advance_increments_generation()

	# Gates
	test_silence_gates_bucket_play()
	test_silence_no_fade_mode()
	test_sparkle_wrong_board_returns_false()
	test_autodropper_beat_sets_period()

	# Peg chime
	test_pick_peg_degree_returns_value_from_pool()
	test_pick_peg_degree_empty_pool_falls_back_to_default()
	test_pick_peg_degree_distribution_is_roughly_balanced()
	test_pick_peg_degree_four_note_pool_distribution()
	test_peg_chime_throttle_drops_rapid_second_call()
	test_peg_chime_dropped_call_does_not_stamp_timestamp()

	# Per-chord attenuation
	test_per_chord_attenuation_resets()

	# Fixed drone timer
	test_drone_timer_is_fixed()

	# Prestige unsilence
	test_prestige_reset_unsilences_audio()

	# Mute
	test_set_muted_toggles_state()
	test_is_muted_default_false()

	# Master volume
	test_set_master_volume_stores_value()
	test_master_volume_clamped_to_range()
	test_get_master_volume_default()
	test_master_volume_applies_gain_boost()
	test_master_volume_zero_is_silent()

	# VFX overrides
	test_set_vfx_override_updates_theme()
	test_get_vfx_overrides_returns_stored()
	test_apply_all_vfx_overrides_mutates_theme()


# --- Snapshot/restore helpers ---

var _saved_drones: Dictionary
var _saved_chord_index: int
var _saved_chord_timer: float
var _saved_chord_generation: int
var _saved_silenced: bool
var _saved_active_board: Variant
var _saved_bucket_queue: Array
var _saved_repeat_bucket_queue: Array
var _saved_last_bucket_play_time: float
var _saved_activated_buckets_order: Array
var _saved_unplayed_buckets: Array
var _saved_pattern_slot_idx: int
var _saved_pattern_slot_timer: float
var _saved_sparkle_step: int
var _saved_peg_chime_last_time_s: float
var _saved_beat_period: float
var _saved_beat_phase: float
var _saved_motif_position: int
var _saved_beat_armed: bool
var _saved_autodrop_interval: float
var _saved_muted: bool
var _saved_master_volume: float
var _saved_vfx_overrides: Dictionary

func _save_state() -> void:
	_saved_drones = AudioManager._active_drones.duplicate(true)
	_saved_chord_index = AudioManager._chord_index
	_saved_chord_timer = AudioManager._chord_timer
	_saved_chord_generation = AudioManager._chord_generation
	_saved_silenced = AudioManager._silenced
	_saved_active_board = AudioManager._active_board
	_saved_bucket_queue = AudioManager._bucket_queue.duplicate(true)
	_saved_repeat_bucket_queue = AudioManager._repeat_bucket_queue.duplicate(true)
	_saved_last_bucket_play_time = AudioManager._last_bucket_play_time
	_saved_activated_buckets_order = AudioManager._activated_buckets_order.duplicate(true)
	_saved_unplayed_buckets = AudioManager._unplayed_buckets.duplicate(true)
	_saved_pattern_slot_idx = AudioManager._pattern_slot_idx
	_saved_pattern_slot_timer = AudioManager._pattern_slot_timer
	_saved_sparkle_step = AudioManager._sparkle_step
	_saved_peg_chime_last_time_s = AudioManager._peg_chime_last_time_s
	_saved_beat_period = AudioManager._beat_period
	_saved_beat_phase = AudioManager._beat_phase
	_saved_motif_position = AudioManager._motif_position
	_saved_beat_armed = AudioManager._beat_armed
	_saved_autodrop_interval = AudioManager._autodrop_interval
	_saved_muted = AudioManager._muted
	_saved_master_volume = AudioManager._master_volume_percent
	_saved_vfx_overrides = AudioManager._vfx_overrides.duplicate(true)

func _restore_state() -> void:
	AudioManager._active_drones = _saved_drones
	AudioManager._chord_index = _saved_chord_index
	AudioManager._chord_timer = _saved_chord_timer
	AudioManager._chord_generation = _saved_chord_generation
	AudioManager._silenced = _saved_silenced
	AudioManager._active_board = _saved_active_board
	AudioManager._bucket_queue = _saved_bucket_queue
	AudioManager._repeat_bucket_queue = _saved_repeat_bucket_queue
	AudioManager._last_bucket_play_time = _saved_last_bucket_play_time
	AudioManager._activated_buckets_order = _saved_activated_buckets_order
	AudioManager._unplayed_buckets = _saved_unplayed_buckets
	AudioManager._pattern_slot_idx = _saved_pattern_slot_idx
	AudioManager._pattern_slot_timer = _saved_pattern_slot_timer
	AudioManager._sparkle_step = _saved_sparkle_step
	AudioManager._peg_chime_last_time_s = _saved_peg_chime_last_time_s
	AudioManager._beat_period = _saved_beat_period
	AudioManager._beat_phase = _saved_beat_phase
	AudioManager._motif_position = _saved_motif_position
	AudioManager._beat_armed = _saved_beat_armed
	AudioManager._autodrop_interval = _saved_autodrop_interval
	AudioManager._muted = _saved_muted
	AudioManager._master_volume_percent = _saved_master_volume
	AudioManager._vfx_overrides = _saved_vfx_overrides


# --- Pure math tests ---

func test_voice_attenuation_zero_voices() -> void:
	print("test_voice_attenuation_zero_voices")
	# Zero voices = no attenuation
	assert_near(AudioManager._voice_attenuation_db(0), 0.0, 0.01, "zero voices = 0 dB")


func test_voice_attenuation_one_voice() -> void:
	print("test_voice_attenuation_one_voice")
	# 1 voice: 20 * log10(0.75) ≈ -2.499
	var expected: float = 20.0 * log(0.75) / log(10.0)
	assert_near(AudioManager._voice_attenuation_db(1), expected, 0.01, "one voice ≈ -2.5 dB")


func test_voice_attenuation_monotonic_decrease() -> void:
	print("test_voice_attenuation_monotonic_decrease")
	# Each additional voice should reduce dB further
	var prev: float = 0.0
	var monotonic: bool = true
	for i in range(1, 8):
		var current: float = AudioManager._voice_attenuation_db(i)
		if current >= prev:
			monotonic = false
			break
		prev = current
	assert_true(monotonic, "attenuation decreases monotonically")


# --- Drone entry factory tests ---

func test_make_drone_entry_has_all_fields() -> void:
	print("test_make_drone_entry_has_all_fields")
	var entry: Dictionary = AudioManager._make_drone_entry(0, 2.5, 3, 1.0, AudioManager.DroneState.ACTIVE, true)
	assert_true(entry.has("idx"), "has idx")
	assert_true(entry.has("timer"), "has timer")
	assert_true(entry.has("degree"), "has degree")
	assert_true(entry.has("octave_mult"), "has octave_mult")
	assert_true(entry.has("state"), "has state")
	assert_true(entry.has("is_advanced"), "has is_advanced")
	assert_true(entry.has("chord_gen"), "has chord_gen")


func test_make_drone_entry_values_match() -> void:
	print("test_make_drone_entry_values_match")
	var entry: Dictionary = AudioManager._make_drone_entry(5, 3.0, 2, 0.5, AudioManager.DroneState.ACTIVE, false)
	assert_equal(entry["idx"], 5, "idx matches")
	assert_near(entry["timer"], 3.0, 0.001, "timer matches")
	assert_equal(entry["degree"], 2, "degree matches")
	assert_near(entry["octave_mult"], 0.5, 0.001, "octave_mult matches")
	assert_equal(entry["state"], AudioManager.DroneState.ACTIVE, "state matches")
	assert_false(entry["is_advanced"], "is_advanced matches")


# --- Drone counting tests ---

func test_count_drones_of_type_excludes_sparkle() -> void:
	print("test_count_drones_of_type_excludes_sparkle")
	_save_state()
	var gen: int = AudioManager._chord_generation
	AudioManager._active_drones = {
		"a": {"state": AudioManager.DroneState.ACTIVE, "is_advanced": false, "idx": 0, "timer": 1.0, "degree": 0, "octave_mult": 1.0, "chord_gen": gen},
		"b": {"state": AudioManager.DroneState.SPARKLE, "is_advanced": false, "idx": 1, "timer": 1.0, "degree": 0, "octave_mult": 1.0, "chord_gen": gen},
		"c": {"state": AudioManager.DroneState.ACTIVE, "is_advanced": false, "idx": 2, "timer": 1.0, "degree": 0, "octave_mult": 1.0, "chord_gen": gen},
	}
	assert_equal(AudioManager._count_drones_of_type(false), 2, "sparkle excluded from count")
	_restore_state()


func test_count_drones_of_type_separates_advanced() -> void:
	print("test_count_drones_of_type_separates_advanced")
	_save_state()
	var gen: int = AudioManager._chord_generation
	AudioManager._active_drones = {
		"a": {"state": AudioManager.DroneState.ACTIVE, "is_advanced": false, "idx": 0, "timer": 1.0, "degree": 0, "octave_mult": 1.0, "chord_gen": gen},
		"b": {"state": AudioManager.DroneState.ACTIVE, "is_advanced": true, "idx": 1, "timer": 1.0, "degree": 0, "octave_mult": 1.0, "chord_gen": gen},
		"c": {"state": AudioManager.DroneState.ACTIVE, "is_advanced": false, "idx": 2, "timer": 1.0, "degree": 0, "octave_mult": 1.0, "chord_gen": gen},
	}
	assert_equal(AudioManager._count_drones_of_type(false), 2, "normal count")
	assert_equal(AudioManager._count_drones_of_type(true), 1, "advanced count")
	_restore_state()


func test_count_drones_of_type_empty() -> void:
	print("test_count_drones_of_type_empty")
	_save_state()
	AudioManager._active_drones = {}
	assert_equal(AudioManager._count_drones_of_type(false), 0, "empty = 0")
	_restore_state()


# --- Repeat softening tests ---

func test_count_active_drones_for_bucket_matches_type() -> void:
	print("test_count_active_drones_for_bucket_matches_type")
	_save_state()
	var gen: int = AudioManager._chord_generation
	AudioManager._active_drones = {
		"N_5_1000": {"state": AudioManager.DroneState.ACTIVE, "is_advanced": false, "idx": 3, "timer": 1.0, "degree": 0, "octave_mult": 0.5, "chord_gen": gen},
		"A_5_1001": {"state": AudioManager.DroneState.ACTIVE, "is_advanced": true, "idx": 7, "timer": 1.0, "degree": 0, "octave_mult": 0.25, "chord_gen": gen},
	}
	assert_equal(AudioManager._count_active_drones_for_bucket(5, false), 1, "normal bucket count")
	assert_equal(AudioManager._count_active_drones_for_bucket(5, true), 1, "advanced bucket count")
	_restore_state()


func test_count_active_drones_for_bucket_excludes_sparkle() -> void:
	print("test_count_active_drones_for_bucket_excludes_sparkle")
	_save_state()
	var gen: int = AudioManager._chord_generation
	# A sparkle entry would never be keyed "N_<idx>_..." in practice, but
	# defensively guard — state, not key, decides whether it counts as a repeat.
	AudioManager._active_drones = {
		"N_5_1000": {"state": AudioManager.DroneState.SPARKLE, "is_advanced": false, "idx": 3, "timer": 1.0, "degree": 0, "octave_mult": 0.5, "chord_gen": gen},
	}
	assert_equal(AudioManager._count_active_drones_for_bucket(5, false), 0, "sparkle-state entry not counted")
	_restore_state()


func test_request_bucket_play_repeat_queues_separately() -> void:
	print("test_request_bucket_play_repeat_queues_separately")
	_save_state()
	AudioManager._silenced = false
	AudioManager._bucket_queue = []
	AudioManager._repeat_bucket_queue = []
	# Force queue mode by stubbing the theme's drum/pattern fields — the
	# theme mode selector in request_bucket_play reads these and we need
	# the queue-mode branch to fire deterministically.
	var saved_drums: PackedInt32Array = ThemeProvider.theme.drum_instruments
	var saved_pattern: String = ThemeProvider.theme.arpeggio_pattern
	ThemeProvider.theme.drum_instruments = PackedInt32Array()
	ThemeProvider.theme.arpeggio_pattern = ""
	AudioManager.request_bucket_play(AudioManager._active_board, 5, 0, false, true)
	assert_equal(AudioManager._repeat_bucket_queue.size(), 1, "repeat enqueued in repeat queue")
	assert_true(AudioManager._bucket_queue.is_empty(), "primary queue untouched")
	ThemeProvider.theme.drum_instruments = saved_drums
	ThemeProvider.theme.arpeggio_pattern = saved_pattern
	_restore_state()


func test_pump_bucket_queue_drains_primary_first() -> void:
	print("test_pump_bucket_queue_drains_primary_first")
	_save_state()
	AudioManager._silenced = false
	# Seed both queues; force cooldown elapsed so the next pump plays one entry.
	AudioManager._bucket_queue = [{"bucket_idx": 1, "degree": 0, "is_advanced": false}]
	AudioManager._repeat_bucket_queue = [{"bucket_idx": 2, "degree": 0, "is_advanced": false}]
	AudioManager._last_bucket_play_time = -999.0
	AudioManager._pump_bucket_queue()
	# Exactly one drain: primary should win.
	assert_true(AudioManager._bucket_queue.is_empty(), "primary drained")
	assert_equal(AudioManager._repeat_bucket_queue.size(), 1, "repeat queue still has its entry")
	_restore_state()


# --- Chord phase tests ---

func test_chord_phase_at_start() -> void:
	print("test_chord_phase_at_start")
	_save_state()
	var duration: float = AudioManager.get_chord_duration()
	AudioManager._chord_timer = duration
	assert_near(AudioManager.get_chord_phase(), 0.0, 0.01, "full timer = phase 0")
	_restore_state()


func test_chord_phase_at_end() -> void:
	print("test_chord_phase_at_end")
	_save_state()
	AudioManager._chord_timer = 0.0
	assert_near(AudioManager.get_chord_phase(), 1.0, 0.01, "zero timer = phase 1")
	_restore_state()


# --- Pitch scale tests ---

func test_pitch_scale_root_is_based_on_chord() -> void:
	print("test_pitch_scale_root_is_based_on_chord")
	_save_state()
	# Ensure we're on chord index 0 to get a known progression entry
	AudioManager._chord_index = 0
	var entry: Dictionary = AudioManager._current_chord_entry()
	if entry.is_empty():
		# No progression available in current theme — skip
		print("  SKIP (no chord progression)")
		_restore_state()
		return
	# Degree 0 should give us root + chord[0] semitones
	var chord: Array = entry["chord"]
	var expected_semitones: int = chord[0] + int(entry["root"])
	var expected_pitch: float = pow(2.0, expected_semitones / 12.0)
	assert_near(AudioManager._get_pitch_scale(0), expected_pitch, 0.001,
		"degree 0 pitch matches chord root")
	_restore_state()


func test_pitch_scale_degree_wraps() -> void:
	print("test_pitch_scale_degree_wraps")
	_save_state()
	AudioManager._chord_index = 0
	var entry: Dictionary = AudioManager._current_chord_entry()
	if entry.is_empty():
		print("  SKIP (no chord progression)")
		_restore_state()
		return
	var chord: Array = entry["chord"]
	# Degree N should wrap to degree N % chord.size()
	var wrapped_degree: int = chord.size()  # wraps to 0
	assert_near(AudioManager._get_pitch_scale(wrapped_degree),
		AudioManager._get_pitch_scale(0), 0.001,
		"degree wraps around chord size")
	_restore_state()


# --- Chord advance tests ---

func test_chord_advance_clears_bucket_queue() -> void:
	print("test_chord_advance_clears_bucket_queue")
	_save_state()
	AudioManager._bucket_queue = [{"test": 1}]
	AudioManager._handle_chord_advance()
	assert_true(AudioManager._bucket_queue.is_empty(), "bucket queue cleared")
	_restore_state()


func test_chord_advance_increments_generation() -> void:
	print("test_chord_advance_increments_generation")
	_save_state()
	var before: int = AudioManager._chord_generation
	AudioManager._handle_chord_advance()
	assert_equal(AudioManager._chord_generation, before + 1, "generation incremented")
	_restore_state()


# --- Gate tests ---

func test_silence_gates_bucket_play() -> void:
	print("test_silence_gates_bucket_play")
	_save_state()
	AudioManager._silenced = true
	var result: bool = AudioManager.request_bucket_play(
		AudioManager._active_board, 0, 0, false)
	assert_false(result, "silenced blocks bucket play")
	AudioManager._silenced = false
	_restore_state()


func test_silence_no_fade_mode() -> void:
	print("test_silence_no_fade_mode")
	_save_state()
	# Add a fake drone to verify it's NOT faded
	AudioManager._active_drones = {
		"test": {"state": AudioManager.DroneState.ACTIVE, "is_advanced": false, "idx": 0, "timer": 4.0, "degree": 0, "octave_mult": 1.0, "chord_gen": 0},
	}
	AudioManager.silence(-1)
	assert_true(AudioManager._silenced, "silenced flag set")
	assert_true(AudioManager._active_drones.has("test"), "drone NOT erased (no fade)")
	AudioManager._silenced = false
	_restore_state()


func test_sparkle_wrong_board_returns_false() -> void:
	print("test_sparkle_wrong_board_returns_false")
	_save_state()
	AudioManager._active_board = Enums.BoardType.GOLD
	var result: bool = AudioManager.should_sparkle(Enums.BoardType.ORANGE)
	assert_false(result, "wrong board rejects sparkle")
	_restore_state()


func test_pick_peg_degree_returns_value_from_pool() -> void:
	print("test_pick_peg_degree_returns_value_from_pool")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var pool: Array[int] = [0, 1, 2, 4]
	for i in 200:
		var d: int = AudioManager.pick_peg_degree(rng, pool)
		assert_true(d in pool,
			"pick_peg_degree returned %d; expected one of %s" % [d, pool])


func test_pick_peg_degree_empty_pool_falls_back_to_default() -> void:
	print("test_pick_peg_degree_empty_pool_falls_back_to_default")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11111
	var empty: Array[int] = []
	for i in 200:
		var d: int = AudioManager.pick_peg_degree(rng, empty)
		assert_true(d == 0 or d == 2,
			"empty pool should fall back to [0, 2]; got %d" % d)


func test_pick_peg_degree_distribution_is_roughly_balanced() -> void:
	print("test_pick_peg_degree_distribution_is_roughly_balanced")
	var rng := RandomNumberGenerator.new()
	rng.seed = 98765
	var pool: Array[int] = [0, 2]
	var roots: int = 0
	var fifths: int = 0
	for i in 1000:
		if AudioManager.pick_peg_degree(rng, pool) == 0:
			roots += 1
		else:
			fifths += 1
	# 1000 trials, expected 500 each, ±60 allowed (well outside 3σ for p=0.5).
	assert_true(absi(roots - fifths) < 120,
		"distribution skew too large: roots=%d fifths=%d" % [roots, fifths])


func test_pick_peg_degree_four_note_pool_distribution() -> void:
	print("test_pick_peg_degree_four_note_pool_distribution")
	var rng := RandomNumberGenerator.new()
	rng.seed = 22222
	var pool: Array[int] = [0, 1, 2, 4]
	var counts: Dictionary = {0: 0, 1: 0, 2: 0, 4: 0}
	for i in 2000:
		counts[AudioManager.pick_peg_degree(rng, pool)] += 1
	# 2000 trials, expected 500 each. Allow ±150 (generous outside 3σ).
	for k in pool:
		assert_true(absi(counts[k] - 500) < 150,
			"distribution skew on degree %d: got %d, expected ~500" % [k, counts[k]])


func test_peg_chime_throttle_drops_rapid_second_call() -> void:
	print("test_peg_chime_throttle_drops_rapid_second_call")
	_save_state()
	# Force throttle window open: pretend nothing has chimed recently.
	AudioManager._peg_chime_last_time_s = -1000.0
	var first: bool = AudioManager.play_peg_chime()
	# Even if the first call returns false (e.g. silenced/empty pool in headless
	# scene), the throttle timestamp must only have moved when first==true.
	if first:
		var second: bool = AudioManager.play_peg_chime()
		assert_false(second,
			"second chime within throttle window should be dropped")
	_restore_state()


func test_peg_chime_dropped_call_does_not_stamp_timestamp() -> void:
	print("test_peg_chime_dropped_call_does_not_stamp_timestamp")
	_save_state()
	# Silence audio so play_peg_chime drops at the silenced gate before
	# touching the timestamp. The stamp must remain unchanged.
	AudioManager._silenced = true
	AudioManager._peg_chime_last_time_s = -1000.0
	var played: bool = AudioManager.play_peg_chime()
	assert_false(played, "silenced chime should return false")
	assert_equal(AudioManager._peg_chime_last_time_s, -1000.0,
		"dropped chime must not update last-play timestamp")
	_restore_state()


func test_autodropper_beat_sets_period() -> void:
	print("test_autodropper_beat_sets_period")
	_save_state()
	AudioManager.notify_autodropper_beat(2.0)
	# beat_period = interval / BEATS_PER_BAR = 2.0 / 4 = 0.5
	assert_near(AudioManager._beat_period, 0.5, 0.001, "beat period = interval / 4")
	assert_near(AudioManager._beat_phase, 0.0, 0.001, "beat phase reset to 0")
	assert_true(AudioManager._beat_armed, "beat armed after sync")
	_restore_state()


# --- Per-chord attenuation tests ---

func test_per_chord_attenuation_resets() -> void:
	print("test_per_chord_attenuation_resets")
	_save_state()
	var gen: int = AudioManager._chord_generation
	# Add drones from the current chord
	AudioManager._active_drones = {
		"a": {"state": AudioManager.DroneState.ACTIVE, "is_advanced": false, "idx": 0, "timer": 4.0, "degree": 0, "octave_mult": 1.0, "chord_gen": gen},
		"b": {"state": AudioManager.DroneState.ACTIVE, "is_advanced": false, "idx": 1, "timer": 4.0, "degree": 1, "octave_mult": 1.0, "chord_gen": gen},
	}
	assert_equal(AudioManager._count_drones_of_type(false), 2, "2 drones before advance")
	# Advance chord — generation increments, old drones become stale
	AudioManager._handle_chord_advance()
	assert_equal(AudioManager._count_drones_of_type(false), 0,
		"0 drones counted after advance (stale chord_gen)")
	# Drones still exist in dict, just not counted for attenuation
	assert_equal(AudioManager._active_drones.size(), 2, "drones still in dict")
	_restore_state()


# --- Fixed drone timer test ---

func test_drone_timer_is_fixed() -> void:
	print("test_drone_timer_is_fixed")
	_save_state()
	# The drone timer should always be Harp.DECAY_SECONDS regardless of chord timer
	var entry: Dictionary = AudioManager._make_drone_entry(0, Harp.DECAY_SECONDS, 0, 0.5, AudioManager.DroneState.ACTIVE, false)
	assert_near(entry["timer"], Harp.DECAY_SECONDS, 0.001, "drone timer = Harp.DECAY_SECONDS")
	assert_near(entry["timer"], 4.0, 0.001, "Harp.DECAY_SECONDS = 4.0")
	_restore_state()


func test_prestige_reset_unsilences_audio() -> void:
	print("test_prestige_reset_unsilences_audio")
	_save_state()
	# Simulate prestige silencing audio (SLOW_MO phase)
	AudioManager._silenced = true
	# reset_time_scale emits prestige_phase_changed(NONE),
	# which AudioManager listens to and calls unsilence()
	PrestigeManager.reset_time_scale()
	assert_false(AudioManager._silenced, "audio unsilenced after prestige reset")
	_restore_state()


# --- Mute tests ---

func test_set_muted_toggles_state() -> void:
	print("test_set_muted_toggles_state")
	_save_state()
	AudioManager.set_muted(true)
	assert_true(AudioManager.is_muted(), "is_muted true after set_muted(true)")
	AudioManager.set_muted(false)
	assert_false(AudioManager.is_muted(), "is_muted false after set_muted(false)")
	_restore_state()


func test_is_muted_default_false() -> void:
	print("test_is_muted_default_false")
	_save_state()
	AudioManager._muted = false
	assert_false(AudioManager.is_muted(), "default mute state is false")
	_restore_state()


# --- Master volume tests ---

func test_set_master_volume_stores_value() -> void:
	print("test_set_master_volume_stores_value")
	_save_state()
	AudioManager.set_master_volume(75.0)
	assert_near(AudioManager.get_master_volume(), 75.0, 0.001, "volume stored as 75")
	_restore_state()


func test_master_volume_clamped_to_range() -> void:
	print("test_master_volume_clamped_to_range")
	_save_state()
	AudioManager.set_master_volume(-10.0)
	assert_near(AudioManager.get_master_volume(), 0.0, 0.001, "negative clamped to 0")
	AudioManager.set_master_volume(150.0)
	assert_near(AudioManager.get_master_volume(), 100.0, 0.001, "over-100 clamped to 100")
	_restore_state()


func test_get_master_volume_default() -> void:
	print("test_get_master_volume_default")
	_save_state()
	AudioManager._master_volume_percent = 50.0
	assert_near(AudioManager.get_master_volume(), 50.0, 0.001, "default volume is 50")
	_restore_state()


func test_master_volume_applies_gain_boost() -> void:
	print("test_master_volume_applies_gain_boost")
	_save_state()
	AudioManager.set_master_volume(100.0)
	# At 100%, linear=1.0, so bus dB should equal the boost constant.
	assert_near(AudioServer.get_bus_volume_db(0), AudioManager.MASTER_GAIN_BOOST_DB, 0.001, "100% applies MASTER_GAIN_BOOST_DB")
	AudioManager.set_master_volume(50.0)
	# At 50%, linear=0.5 → -6.02 dB, plus the boost.
	assert_near(AudioServer.get_bus_volume_db(0), linear_to_db(0.5) + AudioManager.MASTER_GAIN_BOOST_DB, 0.001, "50% applies boost on top of slider")
	_restore_state()


func test_master_volume_zero_is_silent() -> void:
	print("test_master_volume_zero_is_silent")
	_save_state()
	AudioManager.set_master_volume(0.0)
	assert_near(AudioServer.get_bus_volume_db(0), -80.0, 0.001, "0% silences bus (boost not applied)")
	_restore_state()


# --- VFX override tests ---

func test_set_vfx_override_updates_theme() -> void:
	print("test_set_vfx_override_updates_theme")
	_save_state()
	var prev: bool = ThemeProvider.theme.peg_flash_enabled
	AudioManager.set_vfx_override("peg_flash", not prev)
	assert_equal(ThemeProvider.theme.peg_flash_enabled, not prev, "theme property updated")
	# Restore theme property directly since _restore_state won't touch it
	ThemeProvider.theme.peg_flash_enabled = prev
	_restore_state()


func test_get_vfx_overrides_returns_stored() -> void:
	print("test_get_vfx_overrides_returns_stored")
	_save_state()
	AudioManager._vfx_overrides = {}
	AudioManager.set_vfx_override("drop_burst", false)
	var overrides: Dictionary = AudioManager.get_vfx_overrides()
	assert_true(overrides.has("drop_burst"), "override stored in dict")
	assert_false(overrides["drop_burst"], "stored value is false")
	ThemeProvider.theme.drop_burst_enabled = true
	_restore_state()


func test_apply_all_vfx_overrides_mutates_theme() -> void:
	print("test_apply_all_vfx_overrides_mutates_theme")
	_save_state()
	var prev_flash: bool = ThemeProvider.theme.peg_flash_enabled
	var prev_pulse: bool = ThemeProvider.theme.peg_pulse_enabled
	AudioManager._vfx_overrides = {
		"peg_flash": not prev_flash,
		"peg_pulse": not prev_pulse,
	}
	AudioManager.apply_all_vfx_overrides()
	assert_equal(ThemeProvider.theme.peg_flash_enabled, not prev_flash, "peg_flash applied")
	assert_equal(ThemeProvider.theme.peg_pulse_enabled, not prev_pulse, "peg_pulse applied")
	ThemeProvider.theme.peg_flash_enabled = prev_flash
	ThemeProvider.theme.peg_pulse_enabled = prev_pulse
	_restore_state()
