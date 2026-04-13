class_name AudioStyle extends Resource

## Optional audio preset attached to a VisualTheme. When present and applicable
## (see active_during_challenge_only), AudioManager routes through an alternate
## path — different timbre, tempo, backing layer, chord palette, motifs —
## instead of the default harp behavior. A null audio_style on a VisualTheme
## means "use the main harp code path unchanged."

@export var display_name: String = ""

## If true, only activates while ChallengeManager.is_active_challenge. If false,
## active whenever the theme is active. Arcade = true (challenges only).
@export var active_during_challenge_only: bool = true

## Beat-grid subdivisions per external tick. 1 = quarter-note-per-tick,
## 2 = eighths, 4 = sixteenths. With a 1s challenge tick, 2 gives 120 BPM feel.
@export var beats_per_tick: int = 2

## Constant backing — plays every tick whether or not pegs/coins are active.
## Kick hits on each tick; bass plays the current chord's root on each tick.
@export var has_backing_kick: bool = true
@export var has_backing_bass: bool = true

## Tonal timbre for buckets, sparkles, bass. "square" = arcade procedural
## square wave; "harp" = reuse the main theme's harp samples.
@export_enum("square", "harp") var timbre: String = "square"

## Per-chord motifs + progression. Each entry:
##   { "root": int (semitones from C), "chord": Array[int], "motif": Array[int] }
## Motif entries are scale-degree indices into the chord voicing; -1 = rest.
@export var progression: Array = []

## Seconds per chord before advancing to the next entry in the progression.
@export var chord_duration: float = 4.0

## Short arpeggio played on each bucket hit (one note per beat, scale-degree
## indices into the current chord). Empty array disables the accent.
@export var bucket_accent_motif: Array = [0, 2, 4]
