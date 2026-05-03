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

	# Per-chord attenuation
	test_per_chord_attenuation_resets()

	# Fixed drone timer
	test_drone_timer_is_fixed()


# --- Snapshot/restore helpers ---

var _saved_drones: Dictionary
var _saved_chord_index: int
var _saved_chord_timer: float
var _saved_chord_generation: int
var _saved_silenced: bool
var _saved_active_board: Variant
var _saved_bucket_queue: Array
var _saved_last_bucket_play_time: float
var _saved_activated_buckets_order: Array
var _saved_unplayed_buckets: Array
var _saved_pattern_slot_idx: int
var _saved_pattern_slot_timer: float
var _saved_sparkle_step: int
var _saved_beat_period: float
var _saved_beat_phase: float
var _saved_motif_position: int
var _saved_beat_armed: bool
var _saved_autodrop_interval: float

func _save_state() -> void:
	_saved_drones = AudioManager._active_drones.duplicate(true)
	_saved_chord_index = AudioManager._chord_index
	_saved_chord_timer = AudioManager._chord_timer
	_saved_chord_generation = AudioManager._chord_generation
	_saved_silenced = AudioManager._silenced
	_saved_active_board = AudioManager._active_board
	_saved_bucket_queue = AudioManager._bucket_queue.duplicate(true)
	_saved_last_bucket_play_time = AudioManager._last_bucket_play_time
	_saved_activated_buckets_order = AudioManager._activated_buckets_order.duplicate(true)
	_saved_unplayed_buckets = AudioManager._unplayed_buckets.duplicate(true)
	_saved_pattern_slot_idx = AudioManager._pattern_slot_idx
	_saved_pattern_slot_timer = AudioManager._pattern_slot_timer
	_saved_sparkle_step = AudioManager._sparkle_step
	_saved_beat_period = AudioManager._beat_period
	_saved_beat_phase = AudioManager._beat_phase
	_saved_motif_position = AudioManager._motif_position
	_saved_beat_armed = AudioManager._beat_armed
	_saved_autodrop_interval = AudioManager._autodrop_interval

func _restore_state() -> void:
	AudioManager._active_drones = _saved_drones
	AudioManager._chord_index = _saved_chord_index
	AudioManager._chord_timer = _saved_chord_timer
	AudioManager._chord_generation = _saved_chord_generation
	AudioManager._silenced = _saved_silenced
	AudioManager._active_board = _saved_active_board
	AudioManager._bucket_queue = _saved_bucket_queue
	AudioManager._last_bucket_play_time = _saved_last_bucket_play_time
	AudioManager._activated_buckets_order = _saved_activated_buckets_order
	AudioManager._unplayed_buckets = _saved_unplayed_buckets
	AudioManager._pattern_slot_idx = _saved_pattern_slot_idx
	AudioManager._pattern_slot_timer = _saved_pattern_slot_timer
	AudioManager._sparkle_step = _saved_sparkle_step
	AudioManager._beat_period = _saved_beat_period
	AudioManager._beat_phase = _saved_beat_phase
	AudioManager._motif_position = _saved_motif_position
	AudioManager._beat_armed = _saved_beat_armed
	AudioManager._autodrop_interval = _saved_autodrop_interval


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
