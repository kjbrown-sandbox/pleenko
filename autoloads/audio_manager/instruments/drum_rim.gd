class_name DrumRim extends Instrument

## Rim shot — tight tonal click: narrow sine at `freq` plus a very brief
## noise transient at t=0.
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
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var env: float = exp(-t * 35.0)
		var tonal: float = sin(TAU * freq * t) * env * 0.5
		var click: float = 0.0
		if t < 0.005:
			click = randf_range(-1.0, 1.0) * (1.0 - t / 0.005) * 0.4
		var value: float = (tonal + click) * 0.55
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
