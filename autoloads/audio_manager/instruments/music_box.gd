class_name MusicBox extends Instrument

## Procedural music-box tine — like SoftChime in character (sine-dominant, no
## metallic ping, no plucky transient) but with a SHARP drop-off so each note
## clears before the next one lands. Designed for the menu chime where the
## 0.5s beat grid was getting muddied by SoftChime's 1.6s lingering tail.
##
## Differences from SoftChime: simpler spectrum (just fundamental + 2nd
## partial — no sub-octave body, no octave-above shimmer), much faster
## per-partial decay (4.0 / 7.0 vs 2.0 / 2.2 / 4.5), and shorter sample
## (0.7s vs 1.6s). At t=0.5s the fundamental is already at ~14% — quiet
## enough to leave the next beat unobstructed.
const LOW_FREQ := 523.25           # C5 — native frequency of low sample
const HIGH_FREQ := 1046.50         # C6 — native frequency of high sample
const CROSSOVER_FREQ := 784.0      # ~G5 — below uses low, at/above uses high
const BASE_FREQ := 261.63          # C4 — semantic anchor for pitch_mult = 1.0
const DECAY_SECONDS := 0.7

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


## Three-partial additive synthesis — fundamental + 2nd partial for body +
## a faint 3rd for top-end crispness (clearer attack without sounding
## metallic). All partials decay faster than the previous version so each
## note has a definite end before the next beat. No inharmonicity (kills
## the metallic shimmer), no noise transient (kills the percussive tick).
## Sharper attack ramp (2ms) — the previous 5ms was softening the onset
## just enough to muddy the start of each note.
static func _generate(freq: float, duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	var partials: Array[float] = [1.0, 2.0, 3.0]
	var amplitudes: Array[float] = [1.0, 0.30, 0.08]
	# Decay = 6.0 → e^-3 ≈ 0.05 at t=0.5s (well under previous 13%). Upper
	# partials roll off ~2x faster so brightness collapses into a clean tail.
	var decays: Array[float] = [6.0, 11.0, 16.0]

	const ATTACK_SECONDS: float = 0.002
	const TAIL_FADE: float = 0.08
	var tail_start: float = duration - TAIL_FADE

	for i in num_samples:
		var t: float = float(i) / mix_rate
		var value: float = 0.0
		for h in partials.size():
			var harmonic_freq: float = freq * partials[h]
			var env: float = exp(-t * decays[h])
			value += sin(TAU * harmonic_freq * t) * amplitudes[h] * env
		if t < ATTACK_SECONDS:
			value *= t / ATTACK_SECONDS
		value *= 0.5
		if t > tail_start:
			value *= (duration - t) / TAIL_FADE
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
