class_name Instrument extends RefCounted

## Base class for audio instruments. Subclasses own a synthesis strategy and
## expose `resolve(pitch_mult) -> { stream, pitch_scale }`. AudioManager owns
## pooling, voice caps, fades, and chord-gated lifecycle.
## Percussive drum-style instruments typically ignore pitch_mult and return
## pitch_scale = 1.0; tone-less but pitch-variable instruments (e.g. PegTick,
## where callers want per-hit "material size" jitter) pass pitch_mult through
## as pitch_scale instead.

## Single flat enum for theme-level instrument slot selection.
## SILENT = no instrument (that role plays nothing for this theme).
enum Type {
	SILENT,
	HARP,
	TRIANGLE,
	ARCADE_KICK,
	DRUM_KICK_DEEP,
	DRUM_KICK_THIN,
	DRUM_SNARE,
	DRUM_CLAP,
	DRUM_RIM,
	DRUM_HAT,
	DRUM_KICK_BASS,
	BELL,
	HARP_LONG,
	SOFT_CHIME,
	MUSIC_BOX,
	PEG_TICK,
}


func resolve(_pitch_mult: float) -> Dictionary:
	return { "stream": null, "pitch_scale": 1.0 }
