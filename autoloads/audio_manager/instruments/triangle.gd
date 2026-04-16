class_name Triangle extends Instrument

## Procedural triangle wave, multi-sampled so high notes don't get compressed
## into staccato blips (speed-shift on a single sample shrinks both pitch
## and duration in lockstep). LOW covers the standard melody range, HIGH
## kicks in at/above C5 so the note stays close to its natural 0.25s length.
const LOW_FREQ := 261.63        # C4 — native frequency of low sample
const HIGH_FREQ := 523.25       # C5 — native frequency of high sample
const CROSSOVER_FREQ := 523.25  # C5 — at/above uses high
const BASE_FREQ := 261.63       # C4 — semantic anchor for pitch_mult = 1.0
const DURATION := 0.25          # audible ring length for each note

var _low_stream: AudioStreamWAV
var _high_stream: AudioStreamWAV


func _init() -> void:
	_low_stream = _generate(LOW_FREQ, DURATION)
	_high_stream = _generate(HIGH_FREQ, DURATION)


func resolve(pitch_mult: float) -> Dictionary:
	var target_freq: float = BASE_FREQ * pitch_mult
	var use_high: bool = target_freq >= CROSSOVER_FREQ
	var native_freq: float = HIGH_FREQ if use_high else LOW_FREQ
	return {
		"stream": _high_stream if use_high else _low_stream,
		"pitch_scale": target_freq / native_freq,
	}


static func _generate(freq: float, duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var attack: float = 0.004
	var release_start: float = duration * 0.55
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var env: float = 1.0
		if t < attack:
			env = t / attack
		elif t > release_start:
			env = maxf(0.0, 1.0 - (t - release_start) / (duration - release_start))
		# Triangle wave: phase ramps 0..1; fold into a symmetric -1..+1 peak.
		var phase: float = fmod(freq * t, 1.0)
		var tri: float = 4.0 * absf(phase - 0.5) - 1.0
		var value: float = tri * env * 0.3
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
