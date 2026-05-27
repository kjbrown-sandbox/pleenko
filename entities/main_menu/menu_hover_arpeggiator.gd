class_name MenuHoverArpeggiator
extends RefCounted

## Pure state machine for the main-menu hover audio arpeggio. Position 0
## is the bass note of the current chord at the chord-bed octave; positions
## advance up through the chord's notes. Rapid successive hovers traverse
## the arpeggio, bouncing at floor / peak. After DECAY_MS without a hover
## the position resets to the floor (direction up).
##
## No scene-tree dependency by design — MainMenu owns the instance and
## drives it from hover signals; tests can advance() with synthetic clocks.

const NOTES_PER_CHORD := 4
const OCTAVE_FLOOR := 1   # 0 = same octave as the chord bed; +1 = one above; etc.
const OCTAVE_SPAN := 1    # number of consecutive octaves the arpeggio spans
const MAX_INDEX := NOTES_PER_CHORD * OCTAVE_SPAN - 1
const DEFAULT_DECAY_MS := 1500

var _index: int = 0
var _direction: int = 1
var _last_hover_ms: int = -DEFAULT_DECAY_MS - 1
var decay_ms: int = DEFAULT_DECAY_MS


## Returns (note_idx_in_chord, octave_offset) for this hover. note_idx is
## 0..3 and indexes into a 4-note chord pitch array; octave_offset is
## -1 / 0 / +1 (octave below bed, bed octave, octave above).
func advance(now_ms: int) -> Vector2i:
	if now_ms - _last_hover_ms > decay_ms:
		_index = 0
		_direction = 1
	else:
		_index += _direction
		if _index > MAX_INDEX:
			_index = MAX_INDEX - 1
			_direction = -1
		elif _index < 0:
			_index = 1
			_direction = 1
	_last_hover_ms = now_ms
	var note_idx: int = _index % NOTES_PER_CHORD
	var octave_offset: int = (_index / NOTES_PER_CHORD) + OCTAVE_FLOOR
	return Vector2i(note_idx, octave_offset)


## Pure pitch math: chord pitches are float multipliers at the chord-bed
## octave; shift by `octave_offset` octaves (×2 per step up, ÷2 per step
## down). Static so tests don't need to instantiate.
static func pitch_mult_for(note_idx: int, octave_offset: int, chord_pitches: PackedFloat32Array) -> float:
	if chord_pitches.is_empty():
		return 1.0
	var clamped_note: int = clampi(note_idx, 0, chord_pitches.size() - 1)
	return chord_pitches[clamped_note] * pow(2.0, octave_offset)
