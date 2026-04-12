# Per-Theme Audio Identity — Brainstorm

## Context

The current audio system (`agent-logs/zen-audio-plan.md`) is a single zen
palette: handpan/chime sparkles, cello pizz pentatonic buckets, ambient
drone, Pachelbel chord progression across 6 boards. It lives in
`autoloads/audio_manager/audio_manager.gd` with placeholder sine-wave
generators.

The user wants each visual theme to potentially feel different sonically —
keeping the current zen feel for `nier_parchment` but experimenting with
other genres (especially lofi) on other themes. This file captures the
design exploration for later reference.

## Key decisions so far

- **Preferred direction:** Path B (parameterized engine with per-theme
  settings), not Path A (full audio preset Resources per theme).
- **Keep nier as zen.** Current feel stays intact on `nier_parchment`. Any
  genre experimentation happens on *other* themes.
- **Interested in lofi.** Primary candidate for a second genre.
- **Chord progression swap is a cheap win.** Even without changing
  instruments, just swapping the progression (major Pachelbel → minor
  i-v-iv-VI → blues I-IV-V → modal) gives themes different emotional
  colors for trivial effort.

## Genre palette considered

Ranked roughly by "fits the game's minimalist aesthetic" then
"distinctiveness from zen":

| Genre | Signature elements | Candidate theme pairing |
|-------|-------------------|------------------------|
| **Zen / ambient** (current) | Handpan, pentatonic, long reverb, drone pad, sparse attacks | `nier_parchment` |
| **Lofi hip-hop** | Soft snare, vinyl crackle, 7th chords, tape wobble, boom-bap beat | `warm_dark_halo` |
| **Synthwave** | Analog pad, gated reverb snare, arpeggio, 80s warmth | `glow_dark` |
| **Chiptune / 8-bit** | Square/triangle waves, bleeps, NES arpeggios | contrast theme |
| **Classical / orchestral** | Real strings, piano, hall reverb, triadic harmony | `nier_burnt_parchment` |
| **Jazz / bebop** | Upright bass, brushed drums, walking lines, Rhodes piano | `cool_slate` |
| **Folk / acoustic** | Nylon guitar, flute, hand drums, open chords | `warm_minimal` |
| **Medieval / fantasy** | Harp, lute, modal harmony, choir | parchment variant |
| **Tropical** | Marimba, kalimba, ocean, bright attack | any warm palette |
| **Glitch / cyber** | Granular textures, digital artifacts, stutter, non-tonal percussion | dark tech theme |

Any of these can coexist with the pentatonic + Pachelbel foundation because
the harmonic skeleton is always consonant — only the timbre and texture change.

## Defining characteristics of lofi (the primary experiment target)

1. **Boom-bap rhythm section.** Soft kick on beats 1 & 3, snare on 2 & 4,
   swung hi-hats. Deliberately loose timing.
2. **Vinyl crackle bed.** Continuous low-level hiss + occasional pops. Never
   silent — there's always texture.
3. **Tape saturation and wobble.** Slight harmonic distortion + slow pitch
   drift (wow and flutter). Things sound slightly muffled and nostalgic.
4. **Low-pass filtering.** Highs rolled off. Warm, distant, not crisp. This
   is the *opposite* of zen's "crisp + clean" direction.
5. **Jazz harmony.** 7ths, 9ths, suspended chords instead of plain triads.
   Same Pachelbel progression, voiced as Cmaj7, Am7, Em7, Fmaj7, etc.
6. **Sampled "dusty" instruments.** Rhodes piano, muted trumpet, brushed
   drums, upright bass. Often pitched down or chopped.
7. **Short looping 2–4 bar beats.** Repetition is the whole mood.

## Architecture options

### Path A — Full audio presets per theme (ambitious, expressive)

Add an `AudioPreset` Resource with fields:
- `instrument_set`: enum (sine_zen / saturated_lofi / square_chip / rhodes_jazz / ...)
- `chord_progression`: array of 6 chord definitions
- `scale`: pentatonic / blues / Dorian / chromatic / ...
- `texture_layer`: none / vinyl_crackle / rain / drum_loop / ocean
- `reverb_preset`: hall / cathedral / room / dry / vinyl
- `peg_sound_mapping`: which sample/generator fires on peg hit
- `bucket_sound_mapping`: which fires on landing
- `ambient_bed_mapping`: what plays underneath

`VisualTheme` gets an `audio_preset: AudioPreset` field. `AudioManager`
reads the preset on theme change, tears down old pools, and rebuilds with
the new instrumentation.

**Effort:** 300–500 lines restructuring, plus samples per preset. But each
theme gets a full sonic identity — not "zen but with different chords,"
actually *different music*.

**When to use:** when a specific theme demands its own universe that the
parametric engine can't express (e.g., `glow_dark` feels wrong without real
chiptune square waves, not just "sine with a lofi filter").

### Path B — Shared engine, per-theme parameters (pragmatic, our pick)

Keep the same musical system (pentatonic drones, sparkle chimes, ambient
pad, reverb). Expose knobs per theme in `VisualTheme`:

```gdscript
# Harmonic
@export var audio_chord_progression: ProgressionKind = PACHELBEL
    # PACHELBEL / MINOR_CYCLE / BLUES / DORIAN / LYDIAN
@export var audio_root_offset: int = 0              # semitones from C
@export var audio_chord_extensions: ChordKind = TRIAD
    # TRIAD / SEVENTH / NINTH / SUSPENDED

# Timbre
@export var audio_waveform: WaveformKind = SINE
    # SINE / SAWTOOTH / SQUARE / TRIANGLE / SATURATED_SINE
@export var audio_tape_wobble: float = 0.0          # 0.0 = off, 1.0 = heavy wow/flutter

# Texture
@export var audio_background_texture: TextureKind = NONE
    # NONE / VINYL_CRACKLE / TAPE_HISS / RAIN / OCEAN

# Space
@export var audio_reverb_size: float = 0.85
@export var audio_reverb_dry: float = 0.6
@export var audio_reverb_damping: float = 0.5

# Rhythm (optional — can skip for v1)
@export var audio_drum_enabled: bool = false
@export var audio_drum_tempo: float = 80.0          # BPM
```

Same engine, different flavor per theme. Hearing the same Pachelbel chord
progression voiced as a pure sine (zen) vs saturated square wave with
crackle bed (lofi) vs chiptune arp is a very different experience.

**Effort:** ~100 lines. No new samples — existing placeholder generators
parameterize. Instant variation across themes.

**Limits:** can't do genuine genre differences that require fundamentally
different musical structures (e.g., real drums, walking basslines, swung
rhythm). Lofi-lite achievable; full lofi requires drum loops Path A can
accommodate.

### Path C — Chord-only swap (trivial)

Just different `BOARD_KEYS` dict per theme. Same instruments, same
timbres, different emotional coloring via harmony.

Progression library to choose from:
- **Pachelbel (major):** I-V-vi-iii-IV-I → C-G-Am-Em-F-C → uplifting journey
- **Minor cycle:** i-VII-VI-v → Am-G-F-Em → melancholic
- **Blues:** I-IV-V → C-F-G → bluesy swing
- **Dorian:** i-IV-i-v → Dm-G-Dm-Am → jazzy, mysterious
- **Lydian:** I-II-I-vii → Cmaj-Dmaj-Cmaj-Bm → dreamy, cinematic
- **Andalusian:** i-VII-VI-V → Am-G-F-E → Spanish, dramatic
- **Japanese pentatonic:** minor pentatonic rooted on A → traditional feel

**Effort:** 20 lines. Smallest possible differentiation that still feels
different.

## Recommended rollout

Given the user's stated preferences:

1. **Keep `nier_parchment` on the current zen engine unchanged.** Don't
   risk regressing the thing that works.
2. **Implement Path B** so every theme can parameterize the engine.
3. **Pick 2 target themes** for the first experiment — likely a lofi-flavor
   theme (`warm_dark_halo` or similar) and optionally one more distinct
   character.
4. **Swap chord progressions first** (Path C subset) on those themes. Free
   differentiation before any audio engine changes.
5. **Then layer Path B parameters:** add vinyl_crackle texture on the lofi
   theme, change waveform to saturated_sine, add tape_wobble. Should feel
   meaningfully different from zen without replacing any samples.
6. **Evaluate whether Path A is needed** for any specific theme. If
   Path B covers the emotional range we want, stop there.

## Open questions for next session

1. Which themes get which genres?
2. Is lofi meant to replace nier's zen, or be an alternative theme the
   player can choose?
3. Does the lofi experiment include a drum loop (Path A territory) or
   stay within the parametric engine (Path B)?
4. Are any themes "audio-free" (inherit default) vs all getting a unique
   treatment?
5. Should theme switching crossfade audio (like board switching does) or
   just cut?
