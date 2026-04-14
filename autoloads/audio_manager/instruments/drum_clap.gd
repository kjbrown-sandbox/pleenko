class_name DrumClap extends Instrument

## Clap — three layered noise bursts ~13ms apart, followed by a short noise
## sustain tail for body.
var _stream: AudioStreamWAV


func _init(duration: float) -> void:
	_stream = _generate(duration)


func resolve(_pitch_mult: float) -> Dictionary:
	return { "stream": _stream, "pitch_scale": 1.0 }


static func _generate(duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var burst_offsets: Array[float] = [0.0, 0.013, 0.026]
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var value: float = 0.0
		for offset in burst_offsets:
			var dt: float = t - offset
			if dt >= 0.0:
				var env: float = exp(-dt * 40.0)
				value += randf_range(-1.0, 1.0) * env * 0.35
		# Trailing noise tail for body
		var tail_env: float = exp(-t * 20.0) * 0.2
		value += randf_range(-1.0, 1.0) * tail_env
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
