class_name Instrument extends RefCounted

## Base class for audio instruments. Subclasses own a synthesis strategy and
## expose `resolve(pitch_mult) -> { stream, pitch_scale }`. AudioManager owns
## pooling, voice caps, fades, and chord-gated lifecycle.
## Percussive instruments ignore pitch_mult and return pitch_scale = 1.0.

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
}


func resolve(_pitch_mult: float) -> Dictionary:
	return { "stream": null, "pitch_scale": 1.0 }
