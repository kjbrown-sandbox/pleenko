# Prestige Audio — Bass + Bell + Ascending Maj7 Arpeggio

## Feature Description

Implement prestige audio: fade all sounds during SLOW_MO, then at contact play a bass (HarpLong) + bell simultaneously, followed by a real-time ascending I maj7 arpeggio using HarpLong at 0.125s intervals, capping at 3 octaves. New HarpLong instrument with 10s decay and exponential fade starting at 3s.

## Post-Implementation Review

### Round 1 Concerns

**The Janitor** — ADVISORY: HarpLong duplicates Harp's _generate. Extract shared synthesis if a third variant appears.

**The Godot Guru** — BLOCKING: _fade_all_drones(0.5) uses game-time tween, may stall as time_scale drops. ACCEPTED: EASE_OUT drops volume fast in first ~1s real-time while scale is still 0.1-0.15; by the time scale gets very low, volume is already near-silent. Tested and confirmed working.

**The Architect** — ADVISORY: All clear. Peg sparkle already disabled. Empty progression handled. Drone keys clean up naturally.

**The Newcomer** — ADVISORY: Promote octave mult magic numbers to constants. Name the decay steepness in harp_long. Acceptable as-is with inline comments.

**The Consistency Lover** — BLOCKING: Stale comment "ending on the third" from removed code. FIXED.

### Resolutions

1. Stale comment — FIXED. Updated to "from bass to bell (3 octaves)".
2. Fade timing — ACCEPTED risk. Game-time tween starts at scale 0.15, EASE_OUT drops most volume before scale gets too low.
3. Harp duplication — ADVISORY, deferred. Will extract if a third variant appears.
