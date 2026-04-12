# Zen Audio Design Plan

## Context

The nier parchment theme is landing visually, but we want a stronger emotional
identity than "minimalist parchment with juicy peg effects." The pivot: lean
hard on audio to make the main game feel **crisp, clean, melodic, soothing,
and entrancing** — closer to Panoramical, Monument Valley, Alto's Odyssey,
and *Music for Airports*–style generative ambient.

The plinko core is naturally suited: coins drop at a player-controlled pace,
pegs are hit in a predictable sequence, buckets are the resolution point. That
structure is already a musical phrase — we just need to voice it.

## Design Decisions

### Buckets play the scale

Each bucket is mapped to a note. Because buckets are discrete and symmetrical
around a center, this maps cleanly to pitch-by-distance-from-center.

**Pentatonic from the center outward:**

| Bucket position (0 = center)           | Note  |
|----------------------------------------|-------|
| Center (0)                             | C (do)  |
| ±1                                     | D (re)  |
| ±2                                     | E (mi)  |
| ±3                                     | G (sol) |
| ±4                                     | A (la)  |
| ±5                                     | C' (do octave) |
| ±6                                     | D' (re octave) |
| ...                                    | ...   |

Pentatonic has no dissonant intervals, so any combination of bucket hits
sounds consonant — there's no "wrong" landing. Supports symmetric boards up
to 11+ buckets before repeating.

Bucket notes use the **mid/low register** of the chosen instrument, medium
volume, long reverb tail. These are punctuation — the emotional beat of a
drop resolving.

### Pegs create a sparkle layer

Every peg hit triggers one of two sounds:

- **75% of hits**: very soft non-tonal wooden click or tock (percussive, almost
  subliminal). Maintains the feeling of the coin bouncing without being noisy.
- **25% of hits**: soft high-register note from the same scale as the buckets.
  Plays a random pentatonic note (same key as the currently active board).

This creates a wind-chime effect — random-but-always-in-key shimmer
underneath the descent, with bucket landings as the resolving punctuation.

Peg notes are **always quieter than bucket notes** (~20% vs ~60% volume) so
pegs are decoration and buckets are statement.

### Ambient bed

One slow-evolving drone or pad in C (or whichever root the current board
uses), at very low volume (~10%). Fades in when the player drops a coin,
fades out after several seconds of inactivity. *Music for Airports* style —
unobtrusive, spacious, makes every bucket/peg note feel like it "belongs."

### Chord progression across 6 boards (Pachelbel's Canon)

Each board is a chord in the I–V–vi–iii–IV–I progression from Canon in D
(transposed to C major). This is the same progression behind Let It Be,
Hallelujah, Don't Stop Believin', and half of western pop music — famously
satisfying, feels like a journey with a homecoming at the end.

| Board   | Chord         | Degree | Semitones from C | Feel                        |
|---------|---------------|--------|------------------|-----------------------------|
| Gold    | **C major**   | I      | 0                | Home, stable, grounded      |
| Orange  | **G major**   | V      | +7               | Dominant, forward motion    |
| Red     | **A minor**   | vi     | +9               | Emotional depth, bittersweet|
| Board 4 | **E minor**   | iii    | +4               | Introspective, quiet        |
| Board 5 | **F major**   | IV     | +5               | Uplift, second wind         |
| Board 6 | **C major'**  | I'     | +12 (or 0 + richer pad) | Triumphant return  |

All six chords are diatonic in C major. Every pentatonic note on every board
is still in the C major scale, so if a coin from one board is mid-flight
while you switch, its remaining peg hits and landing are harmonically safe.

The 6th board returning to I gives the endgame a literal "coming home"
moment. Its ambient pad can use a thicker voicing (add the 7th or 9th) so
it feels like the same chord but more evolved — not a repeat but a
resolution.

Each board's **pentatonic bucket scale** is its own major or minor
pentatonic rooted at its chord:
- Gold (C): C, D, E, G, A
- Orange (G): G, A, B, D, E
- Red (Am): A, C, D, E, G
- Board 4 (Em): E, G, A, B, D
- Board 5 (F): F, G, A, C, D
- Board 6 (C'): C, D, E, G, A (octave up)

All notes across all boards belong to C major — no accidentals, one sample
set covers everything.

### Board-switching audio behavior

Switching boards is a **crossfade, not a hard cut.** Design principles:

1. **No new sounds from the old board.** The moment the player switches,
   the old board stops generating new peg clicks, peg sparkles, and bucket
   chimes. Coins still in flight on the old board land silently (or are
   hidden — they're already not visible when you switch boards).

2. **Existing sounds decay naturally.** Any notes already playing on the old
   board's reverb tail finish ringing out on their own. No abrupt stop, no
   volume duck. The reverb's natural decay IS the crossfade.

3. **Ambient bed crossfades.** Two ambient players in a double-buffer: old
   pad fades out over ~2 seconds, new pad fades in over ~2 seconds.
   Overlapping tails create a brief harmony between the two chords.

4. **Fast board-toggling easter egg.** If the player flips through all 6
   boards quickly, all 6 ambient pads briefly overlap — producing a
   momentary wash of the full I–V–vi–iii–IV–I chord stack. This isn't a
   goal, just a natural consequence of the crossfade design that happens to
   sound beautiful and rewards exploration.

Implementation: AudioManager tracks the "active board" for sound generation.
`play_bucket` / `play_peg_sparkle` / `play_peg_click` all check against
the active board and no-op if the request came from an inactive one. The
AudioStreamPlayers already mid-playback are fire-and-forget — they finish
on their own timeline regardless of which board is active.

### Reverb

Single biggest quality lever. Long gentle hall reverb on every note — soft
attack, long decay. Without it the notes sound like iPhone keyboard taps;
with it they sound like a temple. Godot provides this via
`AudioEffectReverb` on a bus.

### Density cap

Hard rate-limit per frame, similar to `drop_burst_max_per_second`: cap total
simultaneous sounds globally (target: ~8 sounds/sec max, drop oldest when
exceeded). Otherwise a 10-coin multi-drop on a 12-row board fires 120 notes
at once and the zen feel dies instantly.

### Instrument pairing — two timbres, two roles

Rather than one instrument family for everything, use **two contrasting
timbres** so the sparkle layer and bucket layer occupy clearly separate
sonic spaces:

**Peg sparkle: wind chimes / bell chimes**
- High register, bright, metallic, short sustain with shimmer
- Tinkly and airy — sits on top of the mix without weight
- The randomized 25% trigger rate + high pitch = literal wind chimes
- Sourcing: "wind chime single hit" on Freesound, or tubular bell / mark
  tree samples. One sample pitched across the pentatonic range.

**Bucket landing: cello (pizzicato or sustained) or kalimba**
- Low-to-mid register, warm, rich, full body
- Longer sustain — the note hangs in the air after landing, carried by
  reverb. Gives each landing weight and emotional resonance.
- Sits underneath the chime layer, grounding the harmony
- **Cello (sustained/bowed):** richest tone, most emotional, longest natural
  sustain. Pairs beautifully with wind chimes — classical meets ethereal.
  Harder to pitch-shift cleanly (formants shift).
- **Cello (pizzicato):** plucky, warm, shorter attack. More percussive,
  easier to pitch-shift. Good middle ground.
- **Kalimba:** wooden warmth, plucky, easy to source and pitch. Less
  emotional depth than cello but very clean.

**Recommendation:** start with **cello pizzicato** for buckets + **wind
chime** for peg sparkle. The contrast (warm/low pluck vs bright/high ring)
gives each event its own identity. The two timbres never compete because
they occupy different frequency ranges. If cello pizzicato feels too
"classical," swap to kalimba — the system doesn't care about the sample
identity, only the pitch.

### Quantization (deferred)

For the most hypnotic effect, snap all sound triggers to an 8th or 16th note
grid at a slow BPM (~60). Hit a bucket, sound waits up to ~100ms for the
next beat. Sounds bizarre, feels incredible — Panoramical and *Everything*
do this.

**Not in v1.** Adds significant complexity. Evaluate after the base system
feels good without it.

## Audio Samples — What Do We Actually Need?

### How pitching works in Godot

`AudioStreamPlayer.pitch_scale` changes playback speed — so it changes pitch
AND duration inversely. Pitching up = shorter/brighter, pitching down =
longer/muddier.

- `pitch_scale = 2^(semitones/12)` gives you a specific semitone shift
- `±6 semitones` (half octave) is the "safe" range before pitching starts
  sounding unnatural on most mallet instruments
- `±12 semitones` (full octave) is borderline — noticeable on sustained
  notes, fine on percussive ones

For mallet instruments (kalimba, marimba, handpan), short attacks hide most
pitch-shifting artifacts. We can comfortably pitch a single sample over a full
octave before it sounds bad.

### Minimum viable sample set (v1)

**5 samples total.** Can prototype the whole system.

1. **One cello pizzicato note** (mid-register, ~G3 or C3) — pitched across
   the bucket pentatonic range. Low register so it sits under the chimes.
   Cello pizz pitches well within ±7 semitones because the attack is short.
2. **One wind chime / bell chime hit** (high register, ~G5 or C6) — pitched
   across the peg sparkle pentatonic range. Bright, metallic, shimmery.
3. **One soft wooden click/tock** — non-tonal, percussive. Plays on the 75%
   of peg hits that don't get a note.
4. **One ambient drone pad** — long loop (~30–60 seconds), seamless, in C.
   Plays under everything at low volume.
5. **One coin drop "whoosh"** (optional) — very soft air sound when a coin
   is launched. Sells the moment of release. Can skip for v1.

**Sample the middle of your target range, not the bottom.** Pitching ±5 from
the center covers the pentatonic more evenly than pitching 0→+12 from the
root.

### Quality upgrade path (v2, eventually)

Once v1 feels good, upgrade to multi-sampled instruments for better timbre:

- **10–12 cello pizzicato notes** covering bucket range (C3–C4 chromatic) —
  no pitching needed for buckets, pitch-shifting only for cross-board
  transposition
- **5–8 wind chime hits** at different pitches for organic sparkle variety
- **3–5 click variations** for peg-hit variety (different velocities and
  timbres, randomly selected)

~20–25 samples total for final polish. But v1 with 5 samples is enough to
evaluate the design.

### Sourcing

- **Freesound.org** — CC-licensed, excellent for kalimba, marimba, and
  ambient drones. Plenty of single-note instrument samples.
- **OpenGameArt / Kenney** — free game audio packs, good for clicks and UI sounds.
- **Splice / commercial libraries** — best quality, paid.
- **Soundfonts (.sf2)** — huge free instrument libraries, but need conversion
  to WAV/OGG to use in Godot.
- **Self-recorded** — if you have access to a real kalimba/handpan, one
  hour of recording covers v2 quality.

For v1, Freesound alone should cover everything.

## Implementation Sketch

(Not finalized — outline only. Confirm approach before coding.)

### New Godot nodes

- **`AudioManager` autoload** — owns buses, reverb, and all playback logic.
  Global access; similar to how `CurrencyManager` and `ThemeProvider` work today.
- **AudioStreamPlayer pool** — 16-ish players pre-allocated per bus, cycled
  round-robin to avoid allocating during play. Rate-limited via the density cap.
- **Reverb bus** — `AudioEffectReverb` with long room size and medium wet mix.
  All melodic sounds (buckets, peg sparkle) routed through it. Clicks and
  ambient bed on separate buses.

### API

```gdscript
# Play a note at a specific pentatonic scale degree for the given board.
# No-ops if board_type is not the active board (crossfade gating).
AudioManager.play_bucket(board_type: Enums.BoardType, scale_degree: int)
AudioManager.play_peg_sparkle(board_type: Enums.BoardType)  # randomizes degree
AudioManager.play_peg_click(board_type: Enums.BoardType)    # non-tonal

# Board switching: sets the active board for sound generation and
# crossfades the ambient pad to the new board's chord.
AudioManager.set_active_board(board_type: Enums.BoardType)

# Ambient bed lifecycle
AudioManager.fade_in_ambient()
AudioManager.fade_out_ambient()
```

### Wiring

- `plinko_board.gd::flash_nearest_peg` → `AudioManager.play_peg_sparkle(board_type)` or `play_peg_click(board_type)` (25/75 split)
- `plinko_board.gd::_on_coin_landed` → `AudioManager.play_bucket(board_type, bucket_distance_from_center)`
- `board_manager.gd::switch_board` → `AudioManager.set_active_board(board_type)` (gates new sounds + crossfades ambient)
- `plinko_board.gd::request_drop` → `AudioManager.fade_in_ambient` (first drop after idle)

### Ambient double-buffer

Two AudioStreamPlayers for the ambient pad. On board switch:
1. Old player begins a ~2s volume fade-out tween
2. New player loads the new chord's pitch, begins a ~2s volume fade-in tween
3. During the overlap, both pads play simultaneously — creating a momentary
   harmonic blend between the old and new chords
4. When the old player's fade-out completes, stop it and recycle for next switch

If the player switches boards again before the old fade-out finishes, the
old player keeps fading and a third player would be needed. Simplest: use a
small ring buffer of 3–4 ambient players. In practice, the 2s fade window
means only 2 are ever playing unless the player is button-mashing.

### Theme integration

New `VisualTheme` params (misnomer — sound, not visual — but keeps everything in one resource):
- `audio_enabled: bool`
- `audio_instrument: InstrumentKind` enum (kalimba/handpan/marimba/glockenspiel)
- `audio_peg_click_volume: float`
- `audio_peg_sparkle_volume: float`
- `audio_peg_sparkle_chance: float` (default 0.25)
- `audio_bucket_volume: float`
- `audio_ambient_volume: float`
- `audio_reverb_room_size: float`
- `audio_density_cap_per_second: int`

Themes that don't want audio (e.g., `glow_dark` during challenges, if the
mood doesn't match) can set `audio_enabled = false`.

## Resolved Questions

- **Cross-board keys.** ✅ Pachelbel progression: C → G → Am → Em → F → C'.
  All 6 boards diatonic in C major. See chord table above.
- **Board-switching behavior.** ✅ Crossfade: old board stops generating new
  sounds, existing notes decay via reverb tail, ambient pad double-buffers
  with ~2s overlap. No hard cuts.

## Open Questions

1. **Instrument lock-in.** Kalimba is my rec, but if you already have strong
   feelings about handpan or a different instrument, say so before we source
   samples — the rest of the design is instrument-agnostic.
2. **Ambient bed scope.** Is one seamless loop enough for hours of play, or
   do we need 2–3 alternating loops that cross-fade so it doesn't feel
   repetitive? One is simpler; two is better for long sessions.
3. **Scope of v1.** Does v1 include the ambient bed, or just the
   event-driven sounds (peg + bucket)? Ambient adds another sample and bus
   setup but is maybe 20% of the "zen" feel.
4. **Idle fade-out delay.** How many seconds of no drops before the ambient
   bed fades out? 5s? 15s? Never?
5. **Do pegs in the deprecated `level_up` bucket path also play sounds?**
   Probably yes, but confirm.
6. **Board 6 ambient pad voicing.** Same C major pad as Board 1, or a
   richer voicing (Cmaj7, Cadd9) to differentiate the endgame? Or octave up?

## Verification / Success Criteria

Listening tests, not automated:

1. Drop a single coin. One click descent → one bucket chime. Should feel
   deliberate and satisfying.
2. Drop 5 coins in rapid succession. Density cap should kick in; no
   distortion, no overwhelming wash. Should still feel musical.
3. Let the game sit idle 30 seconds. Ambient bed should fade out gracefully.
4. Switch boards mid-play. Key change should land smoothly — no harsh
   transition.
5. Play for 10 minutes. Does it still feel good, or does the loop/scale
   become grating? This is the big one.

## Out of Scope (explicitly)

- Music synthesis / procedural generation — using pre-recorded samples only.
- Dynamic mixing based on player state (e.g., adaptive music that reacts to
  progress). Interesting but massive scope.
- Sound effects for UI interactions (button clicks, menu opens). Separate
  feature, different bus, different mood.
- Music for challenges mode. This plan is for the main game only —
  challenges can keep their current sound design or get their own pass later.
