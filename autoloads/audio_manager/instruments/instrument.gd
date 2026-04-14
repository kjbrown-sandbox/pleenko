class_name Instrument extends RefCounted

## Base class for audio instruments. Each subclass owns a synthesis strategy
## (sample-based or procedural) and a pre-rendered stream (or set of streams).
##
## AudioManager asks the instrument for a stream + pitch_scale to play at a
## given pitch multiplier (1.0 = C4). Voice pooling, voice caps, fades, and
## chord-gated lifecycle stay owned by AudioManager — the instrument just
## supplies the sound source.
##
## Percussive instruments ignore pitch_mult and return pitch_scale = 1.0.
func resolve(_pitch_mult: float) -> Dictionary:
	return { "stream": null, "pitch_scale": 1.0 }
