class_name DrumHat extends Instrument

## Hi-hat — high-frequency noise burst with fast decay, plus a subtle tonal
## shimmer at `freq`.
var _stream: AudioStreamWAV


func _init(freq: float, duration: float) -> void:
	_stream = _generate(freq, duration)


func resolve(_pitch_mult: float) -> Dictionary:
	return { "stream": _stream, "pitch_scale": 1.0 }


static func _generate(freq: float, duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var decay_rate: float = 4.0 / duration
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var env: float = exp(-t * decay_rate)
		var noise: float = randf_range(-1.0, 1.0) * env * 0.6
		var shimmer: float = sin(TAU * freq * t) * env * 0.1
		var value: float = (noise + shimmer) * 0.5
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
