class_name Piano extends Instrument

## Procedural piano tuned for the main-menu chime: crisp attack, fast decay,
## doesn't linger. NOT a sustained grand-piano sound (that's what makes a
## sample-based piano feel "weird" on a sparse menu beat — the tail collides
## with the next note). Single voice (no unison shimmer), light inharmonicity,
## sharp ~5ms attack, ~1.5s usable sustain.
##
## Native samples at C3 and C5 (same crossover as Harp) so notes never pitch-
## shift more than an octave from native. 2.5s sample is enough to ring out
## the held block chord across its 1.5s of silent beats without bleeding into
## the next chord.
const LOW_FREQ := 130.81           # C3 — native frequency of low sample
const HIGH_FREQ := 523.25          # C5 — native frequency of high sample
const CROSSOVER_FREQ := 261.63     # C4 — below uses low, at/above uses high
const BASE_FREQ := 261.63          # C4 — semantic anchor for pitch_mult = 1.0
const DECAY_SECONDS := 1.5   # voice/drone timer — how long the note is "active"
const SAMPLE_SECONDS := 2.5  # actual sample length

var _low_stream: AudioStreamWAV
var _high_stream: AudioStreamWAV


func _init() -> void:
	_low_stream = _generate(LOW_FREQ, SAMPLE_SECONDS)
	_high_stream = _generate(HIGH_FREQ, SAMPLE_SECONDS)


func resolve(pitch_mult: float) -> Dictionary:
	var target_freq: float = BASE_FREQ * pitch_mult
	var use_high: bool = target_freq >= CROSSOVER_FREQ
	var native_freq: float = HIGH_FREQ if use_high else LOW_FREQ
	return {
		"stream": _high_stream if use_high else _low_stream,
		"pitch_scale": target_freq / native_freq,
	}


## Additive synthesis. Bright spectrum (2nd partial slightly stronger than the
## fundamental — piano "iron" bite) collapses fast, leaving a short fundamental
## tail. Fundamental decay = 1.5 → amplitude ≈ 0.22 at t=1s, ≈ 0.05 at t=2s.
## Upper partials decay 2-10x faster so the attack is bright and the tail is
## clean. Light inharmonicity for organic character, no unison detune
## (shimmer reads as "weird" outside a real-piano context).
static func _generate(freq: float, duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	var harmonics: Array[float] = [0.9, 1.0, 0.55, 0.30, 0.15, 0.07]
	var decays: Array[float] =    [1.5, 2.0, 3.5,  5.5,  8.0,  12.0]

	const INHARMONICITY: float = 0.0004

	# Hammer-strike attack: short rise. No noise burst — the user wants "crisp,"
	# not "thumpy." Bright partials at t=0 give plenty of attack on their own.
	const ATTACK_SECONDS: float = 0.005

	const TAIL_FADE: float = 0.4
	var tail_start: float = duration - TAIL_FADE

	for i in num_samples:
		var t: float = float(i) / mix_rate
		var value: float = 0.0
		for h in harmonics.size():
			var n: float = float(h + 1)
			var partial_freq: float = freq * n * (1.0 + INHARMONICITY * n * n)
			var env: float = exp(-t * decays[h])
			value += sin(TAU * partial_freq * t) * harmonics[h] * env

		if t < ATTACK_SECONDS:
			value *= t / ATTACK_SECONDS
		value *= 0.45
		if t > tail_start:
			value *= (duration - t) / TAIL_FADE
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
