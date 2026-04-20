# Juicy Bucket Value Upgrade

## Feature Description

When a BUCKET_VALUE upgrade is purchased, animate a center-outward ripple instead of instantly rebuilding the board. Each distance group gets: split pulse (down, tick counter, up), mark_singing + force_play_bucket for an arpeggio. Normal coin singing is suppressed during the animation.

## Post-Implementation Review

### Round 1 Concerns

**The Janitor (Code Cleanliness)**
- BLOCKING: Duplicated bucket value formula between `build_board()` and the ripple. Extract shared method.
- ADVISORY: `pulse()` should call `pulse_down()` + `pulse_up()` instead of duplicating logic.
- ADVISORY: Ripple method is 80 lines in an already large file.

**The Godot Guru (Engine Best Practices)**
- BLOCKING: `pulse_down` duration and ripple interval could drift independently — fragile timing coupling.
- ADVISORY: ~30 tweens for 15 buckets is fine. Tween lifecycle is correct.

**The Architect (Dependencies & Connections)**
- BLOCKING: If `build_board()` fires mid-ripple (e.g., `add_two_rows` from a level reward), tween callbacks hit freed bucket nodes. Kill ripple at top of `build_board()`.
- ADVISORY: `force_play_bucket` bypass of dedup is intentional and safe. Value setter ordering is fragile but works because it's synchronous in the same frame.

**The Newcomer (Readability)**
- ADVISORY: Add comment on `/ 2.0` divisor. `_upgrade_animating` name could be more descriptive.

**The Consistency Lover (Standardization)**
- BLOCKING: `PRESS_DEPTH` const misplaced — should be grouped with other consts at top of file.
- ADVISORY: Rename to `_is_upgrade_animating`. Ripple timing should be a VisualTheme variable. Add doc comment on `_play_bucket_value_upgrade_ripple`.

### Resolutions

1. **Duplicated formula** — FIXED. Extracted `_bucket_value_for_distance(distance)` used by both `build_board()` and the ripple.
2. **Stale bucket references** — FIXED. Added ripple kill + flag reset at top of `build_board()`.
3. **PRESS_DEPTH placement** — FIXED. Moved to top with other consts.
4. **Timing drift** — Accepted risk. Both values derive from `t.bucket_pulse_duration * 0.25`, so they're inherently tied. Not a practical concern.
5. **Doc comment** — FIXED. Added `##` comment on `_play_bucket_value_upgrade_ripple`.
6. **Advisory items** — Noted but not addressed: `pulse()` refactoring to call halves, VisualTheme ripple timing, `_is_` prefix rename.
