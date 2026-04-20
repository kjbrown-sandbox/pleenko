class_name HarpLong extends Instrument

## Long-sustain harp variant for prestige arpeggios. Same synthesis as Harp but
## with a 10-second decay window — the fundamental rings out slowly and upper
## harmonics sustain longer, giving a lush, reverberant tail.
const LOW_FREQ := 130.81           # C3
const HIGH_FREQ := 523.25          # C5
const CROSSOVER_FREQ := 261.63     # C4
const BASE_FREQ := 261.63          # C4 — pitch_mult = 1.0
const DECAY_SECONDS := 10.0

var _low_stream: AudioStreamWAV
var _high_stream: AudioStreamWAV


func _init() -> void:
	_low_stream = _generate(LOW_FREQ, DECAY_SECONDS, false)
	_high_stream = _generate(HIGH_FREQ, DECAY_SECONDS, true)


func resolve(pitch_mult: float) -> Dictionary:
	var target_freq: float = BASE_FREQ * pitch_mult
	var use_high: bool = target_freq >= CROSSOVER_FREQ
	var native_freq: float = HIGH_FREQ if use_high else LOW_FREQ
	return {
		"stream": _high_stream if use_high else _low_stream,
		"pitch_scale": target_freq / native_freq,
	}


static func _generate(freq: float, duration: float, darker: bool, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	# Decay constants scaled for the 10-second window. Fundamental decays very
	# slowly so it sustains most of the sample; upper partials still fade faster
	# but linger longer than the 4-second Harp, giving a richer sustained body.
	var harmonics: Array[float]
	var decays: Array[float]
	if darker:
		harmonics = [1.0, 0.30, 0.08, 0.02, 0.006, 0.002, 0.0005, 0.0001, 0.00005, 0.00002]
		decays    = [0.2, 0.36, 0.6, 1.2, 2.4, 4.0, 6.4, 9.6, 14.0, 20.0]
	else:
		harmonics = [1.0, 0.45, 0.20, 0.08, 0.04, 0.02, 0.01, 0.005, 0.003, 0.002]
		decays    = [0.2, 0.28, 0.48, 0.8, 1.2, 2.0, 2.8, 3.6, 4.8, 6.4]

	const INHARMONICITY: float = 0.0003
	const SUSTAIN_END: float = 3.0  # full volume for first 3s, then fade out
	var fade_duration: float = duration - SUSTAIN_END  # 5s linear fade to zero

	for i in num_samples:
		var t: float = float(i) / mix_rate
		var value: float = 0.0
		for h in harmonics.size():
			var n: float = float(h + 1)
			var harmonic_freq: float = freq * n * (1.0 + INHARMONICITY * n * n)
			var env: float = exp(-t * decays[h])
			value += sin(TAU * harmonic_freq * t) * harmonics[h] * env
		if t < 0.015:
			value += randf_range(-1.0, 1.0) * (1.0 - t / 0.015) * 0.15
		value *= 0.45
		if t > SUSTAIN_END:
			# Exponential fade: drops fast then leaves a faint tail
			var fade_progress: float = (t - SUSTAIN_END) / fade_duration
			value *= exp(-fade_progress * 4.0)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
