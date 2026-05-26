class_name PegTick extends Instrument

## Tone-less percussive blip — short noise burst meant to read as a small
## physical object (glass marble clink) rather than a pitched note. Used by
## the menu for coin/peg contact. Pitch_mult varies per hit to suggest
## different sized marbles, so it doesn't settle into a single repeating
## sample.
##
## Synthesis: high-pass filtered noise (bright, glassy "tss" — NOT the warm
## low-pass thud of a drum) + a very brief high-frequency damped sine for
## the "ting" of glass resonance + very fast exponential decay (~25-40ms
## perceptual length). No drum-body half-sine thump; that read as too
## percussive / wooden.
const DURATION := 0.15

var _stream: AudioStreamWAV


func _init() -> void:
	_stream = _generate(DURATION)


## Honors pitch_mult by setting pitch_scale directly — varying it per hit
## shifts both the filtered-noise band AND the glass-resonance frequency,
## yielding a convincing "different size marble" feel.
func resolve(pitch_mult: float) -> Dictionary:
	return { "stream": _stream, "pitch_scale": pitch_mult }


static func _generate(duration: float, mix_rate: int = 44100) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	var num_samples := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	# High-pass = noise minus its 1-pole low-pass. Higher LP_COEFF tracks more
	# of the noise into the LP, leaving a brighter / hisser HP residue. 0.5
	# centres the cut around several kHz — bright, glassy, not white-noise hiss.
	const LP_COEFF: float = 0.5
	# Very fast decay on the noise — glass impacts are essentially transient.
	const NOISE_DECAY: float = 60.0
	# Damped high sine sits in the "tink/clink" sweet spot for glass (2-4 kHz).
	# Decays much faster than the noise so it reads as a flash of pitch at
	# attack, not a sustained tone.
	const RES_FREQ: float = 2800.0
	const RES_DECAY: float = 80.0
	const RES_GAIN: float = 0.55

	var lp_state: float = 0.0
	for i in num_samples:
		var t: float = float(i) / mix_rate
		var noise: float = randf_range(-1.0, 1.0)
		lp_state += (noise - lp_state) * LP_COEFF
		var hp: float = noise - lp_state
		var noise_env: float = exp(-t * NOISE_DECAY)
		var resonance: float = sin(TAU * RES_FREQ * t) * exp(-t * RES_DECAY) * RES_GAIN
		var value: float = (hp * noise_env * 0.7 + resonance) * 0.85
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	wav.data = data
	return wav
