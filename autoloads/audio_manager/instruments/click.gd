class_name Click extends Instrument

## Peg click — a brief white-noise burst with a fast exponential decay.
## Percussive — pitch_mult is ignored.
const DURATION := 0.05

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
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var env: float = exp(-t * 60.0)
		var value: float = randf_range(-1.0, 1.0) * env * 0.3
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
