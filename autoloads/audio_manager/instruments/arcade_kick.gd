class_name ArcadeKick extends Instrument

## Procedural arcade kick: low-frequency sine with a downward pitch sweep and
## a fast exponential decay. Evokes a classic "boom" without needing a sample.
## Percussive — pitch_mult is ignored.
const DURATION := 0.18

var _stream: AudioStreamWAV


func _init() -> void:
	_stream = _generate(DURATION)


func resolve(_pitch_mult: float) -> Dictionary:
	return { "stream": _stream, "pitch_scale": 1.0 }


static func _generate(duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var phase: float = 0.0
	for i in num_samples:
		var t: float = float(i) / mix_rate
		# Pitch sweep from 180 Hz down to 50 Hz over the sample length.
		var freq: float = lerpf(180.0, 50.0, minf(1.0, t / duration))
		phase += TAU * freq / float(mix_rate)
		var env: float = exp(-t * 18.0)
		# Tiny click at the very start for snap.
		if t < 0.003:
			env += (1.0 - t / 0.003) * 0.4
		var value: float = sin(phase) * env * 0.55
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
