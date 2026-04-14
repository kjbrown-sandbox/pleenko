class_name Square extends Instrument

## Procedural arcade square wave. Short envelope (sharp attack, brief sustain,
## quick release) yields a staccato "bleep" rather than a sustained pad. One
## stream is pre-rendered at BASE_FREQ and pitch_scale shifts it per note.
const BASE_FREQ := 261.63   # C4
const DURATION := 1.0       # audible ring length for each note

var _stream: AudioStreamWAV


func _init() -> void:
	_stream = _generate(BASE_FREQ, DURATION)


func resolve(pitch_mult: float) -> Dictionary:
	return { "stream": _stream, "pitch_scale": pitch_mult }


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
		var sq: float = 1.0 if sin(TAU * freq * t) >= 0.0 else -1.0
		var value: float = sq * env * 0.22
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
