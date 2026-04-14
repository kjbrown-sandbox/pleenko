class_name DrumKick extends Instrument

## Acoustic-style kick — pitch-swept sine (from freq*2.5 down to freq over the
## first 15% of duration), sustained body, exponential decay, click transient
## at t=0. Distinct from ArcadeKick (which has its own sweep envelope).
##
## Configurable per-instance so the call site can build multiple variants —
## e.g., DrumKick.new(60.0, 0.22) for a deep foundation and
## DrumKick.new(100.0, 0.09) for a thin ticky kick.
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
	# Pitch-swept sine from freq*2.5 down to freq over first 15% of duration,
	# then sustained + exponential decay. Short click noise burst at t=0 for attack.
	var sweep_len: float = duration * 0.15
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var freq_at_t: float
		if t < sweep_len:
			freq_at_t = lerpf(freq * 2.5, freq, t / sweep_len)
		else:
			freq_at_t = freq
		var env: float = exp(-t * 8.0)
		var body: float = sin(TAU * freq_at_t * t) * env
		var click: float = 0.0
		if t < 0.003:
			click = randf_range(-1.0, 1.0) * (1.0 - t / 0.003) * 0.3
		var value: float = (body + click) * 0.7
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
