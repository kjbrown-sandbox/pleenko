class_name SoftChime extends Instrument

## Procedural soft chime — muffled, sine-dominant bell tone for ambient peg
## chimes. Designed to read as background texture: distinct enough to feel
## individual, but without the metallic ping of the brighter Bell. Differences
## from Bell: no inharmonicity (kills the metallic shimmer), no noise transient
## (kills the percussive tick), and a short attack ramp (~15ms) that softens
## the onset so individual hits don't poke through the mix.
const LOW_FREQ := 523.25           # C5 — native frequency of low sample
const HIGH_FREQ := 1046.50         # C6 — native frequency of high sample
const CROSSOVER_FREQ := 784.0      # ~G5 — below uses low, at/above uses high
const BASE_FREQ := 261.63          # C4 — semantic anchor for pitch_mult = 1.0
const DECAY_SECONDS := 1.6

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


## Additive synthesis: strong fundamental, gentle sub-octave for body, faint
## octave above for a hint of shimmer. Pure harmonics (no inharmonicity).
## Short attack ramp smooths the onset; long tail fade prevents click.
static func _generate(freq: float, duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	# Sub-octave gives body without muddying pitch; octave above adds a
	# whisper of air. Fundamental dominates so the note still reads as pitched.
	# Frequencies are ratios of the fundamental.
	var partials: Array[float] = [0.5, 1.0, 2.0]
	var amplitudes: Array[float] = [0.18, 1.0, 0.12]
	var decays: Array[float] = [2.0, 2.2, 4.5]

	const ATTACK_SECONDS: float = 0.015
	const TAIL_FADE: float = 0.25
	var tail_start: float = duration - TAIL_FADE

	for i in num_samples:
		var t: float = float(i) / mix_rate
		var value: float = 0.0
		for h in partials.size():
			var harmonic_freq: float = freq * partials[h]
			var env: float = exp(-t * decays[h])
			value += sin(TAU * harmonic_freq * t) * amplitudes[h] * env
		# Short attack ramp — softens onset so hits feel like background texture.
		if t < ATTACK_SECONDS:
			value *= t / ATTACK_SECONDS
		value *= 0.42
		if t > tail_start:
			value *= (duration - t) / TAIL_FADE
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
