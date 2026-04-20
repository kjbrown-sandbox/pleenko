class_name Bell extends Instrument

## Procedural bell — clean, bright tone with fast decay. Designed as a shimmer
## layer over the harp: fewer harmonics, slight inharmonicity for bell character,
## and a shorter ring so voices don't pile up into mush.
const LOW_FREQ := 523.25           # C5 — native frequency of low sample
const HIGH_FREQ := 1046.50         # C6 — native frequency of high sample
const CROSSOVER_FREQ := 784.0      # ~G5 — below uses low, at/above uses high
const BASE_FREQ := 261.63          # C4 — semantic anchor for pitch_mult = 1.0
const DECAY_SECONDS := 2.0

var _low_stream: AudioStreamWAV
var _high_stream: AudioStreamWAV


func _init() -> void:
	_low_stream = _generate(LOW_FREQ, DECAY_SECONDS)
	_high_stream = _generate(HIGH_FREQ, DECAY_SECONDS)


func resolve(pitch_mult: float) -> Dictionary:
	var target_freq: float = BASE_FREQ * pitch_mult
	var use_high: bool = target_freq >= CROSSOVER_FREQ
	var native_freq: float = HIGH_FREQ if use_high else LOW_FREQ
	return {
		"stream": _high_stream if use_high else _low_stream,
		"pitch_scale": target_freq / native_freq,
	}


## Additive synthesis: strong fundamental, soft octave, faint third partial
## with slight inharmonicity for metallic bell character. Fast exponential
## decay with a tail fade to avoid click on sample end.
static func _generate(freq: float, duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	# Bell partials: strong fundamental, soft octave, hint of 3rd.
	# Inharmonicity is higher than harp — gives the metallic shimmer.
	var harmonics: Array[float] = [1.0, 0.25, 0.06]
	var decays: Array[float] = [1.2, 2.5, 5.0]
	const INHARMONICITY: float = 0.002

	const TAIL_FADE: float = 0.2
	var tail_start: float = duration - TAIL_FADE

	for i in num_samples:
		var t: float = float(i) / mix_rate
		var value: float = 0.0
		for h in harmonics.size():
			var n: float = float(h + 1)
			var harmonic_freq: float = freq * n * (1.0 + INHARMONICITY * n * n)
			var env: float = exp(-t * decays[h])
			value += sin(TAU * harmonic_freq * t) * harmonics[h] * env
		# Soft transient — gentler than harp pluck, just enough to mark the attack.
		if t < 0.005:
			value += randf_range(-1.0, 1.0) * (1.0 - t / 0.005) * 0.05
		value *= 0.4
		if t > tail_start:
			value *= (duration - t) / TAIL_FADE
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
