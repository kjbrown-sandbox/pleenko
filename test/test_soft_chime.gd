extends "res://test/test_base.gd"

## SoftChime tests — run with:
##   godot --headless --scene res://test/test_soft_chime.tscn


func _run_tests() -> void:
	print("\n=== SoftChime Tests ===\n")

	test_resolve_below_crossover_uses_low_stream()
	test_resolve_at_crossover_uses_high_stream()
	test_resolve_above_crossover_uses_high_stream()
	test_resolve_returns_unit_pitch_at_base_freq()
	test_resolve_pitch_scale_is_proportional()
	test_streams_are_nonempty()
	test_audio_manager_instrument_for_soft_chime()


func test_resolve_below_crossover_uses_low_stream() -> void:
	print("test_resolve_below_crossover_uses_low_stream")
	var chime := SoftChime.new()
	# pitch_mult = 1.0 → C4 (261.63Hz), well below ~G5 crossover.
	var sp: Dictionary = chime.resolve(1.0)
	assert_true(sp["stream"] != null, "low stream is non-null")
	# Low native is C5 → pitch_scale ≈ C4/C5 = 0.5
	assert_near(sp["pitch_scale"], 0.5, 0.001, "pitch_scale ≈ 0.5 at C4")


func test_resolve_at_crossover_uses_high_stream() -> void:
	print("test_resolve_at_crossover_uses_high_stream")
	var chime := SoftChime.new()
	# pitch_mult * BASE_FREQ = CROSSOVER_FREQ (784) → mult = 784/261.63 ≈ 2.996
	var mult: float = SoftChime.CROSSOVER_FREQ / SoftChime.BASE_FREQ
	var sp: Dictionary = chime.resolve(mult)
	# At crossover, use_high is true (>=).
	assert_near(sp["pitch_scale"], SoftChime.CROSSOVER_FREQ / SoftChime.HIGH_FREQ, 0.001,
		"crossover routes to high stream with expected pitch_scale")


func test_resolve_above_crossover_uses_high_stream() -> void:
	print("test_resolve_above_crossover_uses_high_stream")
	var chime := SoftChime.new()
	# pitch_mult = 4.0 → C6 (1046.5Hz), at HIGH_FREQ native → pitch_scale = 1.0
	var sp: Dictionary = chime.resolve(4.0)
	assert_near(sp["pitch_scale"], 1.0, 0.001, "pitch_scale = 1.0 at C6 (high native)")


func test_resolve_returns_unit_pitch_at_base_freq() -> void:
	print("test_resolve_returns_unit_pitch_at_base_freq")
	# Base freq (C4) maps to low stream with scale = BASE/LOW.
	var chime := SoftChime.new()
	var sp: Dictionary = chime.resolve(1.0)
	var expected_scale: float = SoftChime.BASE_FREQ / SoftChime.LOW_FREQ
	assert_near(sp["pitch_scale"], expected_scale, 0.001, "BASE/LOW pitch scale")


func test_resolve_pitch_scale_is_proportional() -> void:
	print("test_resolve_pitch_scale_is_proportional")
	# Doubling pitch_mult on the same side of the crossover should double pitch_scale.
	var chime := SoftChime.new()
	var sp_low: Dictionary = chime.resolve(0.5)
	var sp_high: Dictionary = chime.resolve(1.0)
	assert_near(sp_high["pitch_scale"] / sp_low["pitch_scale"], 2.0, 0.001,
		"pitch_scale doubles when pitch_mult doubles within same sample region")


func test_streams_are_nonempty() -> void:
	print("test_streams_are_nonempty")
	var chime := SoftChime.new()
	var low: AudioStreamWAV = chime.resolve(0.5).stream
	var high: AudioStreamWAV = chime.resolve(4.0).stream
	assert_true(low.data.size() > 0, "low stream has data")
	assert_true(high.data.size() > 0, "high stream has data")
	# Both samples should be ~DECAY_SECONDS long at 44100 Hz, 16-bit (2 bytes/sample).
	var expected_bytes: int = int(SoftChime.DECAY_SECONDS * 44100) * 2
	assert_equal(low.data.size(), expected_bytes, "low stream length matches DECAY_SECONDS")
	assert_equal(high.data.size(), expected_bytes, "high stream length matches DECAY_SECONDS")


func test_audio_manager_instrument_for_soft_chime() -> void:
	print("test_audio_manager_instrument_for_soft_chime")
	# AudioManager registers a SoftChime singleton and exposes it via the
	# Instrument.Type enum dispatch. This guards the peg-chime wiring.
	var instr: Instrument = AudioManager._instrument_for(Instrument.Type.SOFT_CHIME)
	assert_true(instr != null, "SOFT_CHIME enum resolves to a non-null instrument")
	assert_true(instr is SoftChime, "instrument is a SoftChime")
