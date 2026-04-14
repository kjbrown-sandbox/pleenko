class_name Harp extends Instrument

## Procedural harp — multi-sampled at two pitches so notes never pitch-shift
## more than about an octave from their native sample. The high sample uses a
## darker harmonic profile so it doesn't brighten further when shifted up.
const LOW_FREQ := 130.81           # C3 — native frequency of low sample
const HIGH_FREQ := 523.25          # C5 — native frequency of high sample
const CROSSOVER_FREQ := 261.63     # C4 — below uses low, at/above uses high
const BASE_FREQ := 261.63          # C4 — semantic anchor for pitch_mult = 1.0
const DECAY_SECONDS := 4.0

var _low_stream: AudioStreamWAV   # warm, C3-native
var _high_stream: AudioStreamWAV  # dark, C5-native


func _init() -> void:
	_low_stream = _generate(LOW_FREQ, DECAY_SECONDS, false)
	_high_stream = _generate(HIGH_FREQ, DECAY_SECONDS, true)


## Picks the closer-pitched harp sample for the target pitch multiplier (where
## 1.0 = C4), and returns the pitch_scale needed on that sample to hit it.
## Keeps pitch-shifting to under one octave in either direction.
func resolve(pitch_mult: float) -> Dictionary:
	var target_freq: float = BASE_FREQ * pitch_mult
	var use_high: bool = target_freq >= CROSSOVER_FREQ
	var native_freq: float = HIGH_FREQ if use_high else LOW_FREQ
	return {
		"stream": _high_stream if use_high else _low_stream,
		"pitch_scale": target_freq / native_freq,
	}


## Additive synthesis of the harmonic series with per-harmonic exponential
## decay. The fundamental sustains slowly (seconds); upper harmonics decay
## fast, which gives the initial attack brightness that mellows into a
## pure-ish sustained tone. A very brief noise burst in the first ~15ms sells
## the "plucked" character. When `darker` is true, upper harmonics are further
## attenuated and decay even faster — used for the high-register sample so it
## doesn't sound tinny when pitch-shifted up another octave.
static func _generate(freq: float, duration: float, darker: bool, mix_rate: int = 44100) -> AudioStreamWAV:
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
	# Fundamental decay constants tuned against the 4-second DECAY_SECONDS
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
