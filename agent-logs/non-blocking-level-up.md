# Non-Blocking Level-Up Celebration

## Feature Description

Replace the modal level-up dialog with non-blocking celebration effects: progress bar shakes at 90-100%, explodes with particles on level-up, camera shakes, rewards auto-claim, and new upgrade buttons materialize left-to-right with a blinking "new" state.

## Round 1 — Concerns

### The Janitor (Code Cleanliness)
- **BLOCKING**: Camera shake duplication between board_manager and prestige_vfx — same exponential decay math copied. Suggested extracting a shared CameraShaker helper.
- **BLOCKING**: Dead references after LevelUpDialog removal — need to clean main.tscn and check for orphaned signal connections.
- **Advisory**: board_manager.gd responsibility creep (384 lines + new shake logic).
- **Advisory**: visual_theme.gd growing (425 lines + 8 new exports).

### The Godot Guru (Engine Best Practices)
- **BLOCKING**: ColorRect particles as HBoxContainer children will fight layout. Need separate overlay Control.
- **CAUTION**: `scale.x` on MarginContainer in VBoxContainer — visual only, doesn't affect layout rect. `pivot_offset` must be set after layout pass.
- **CAUTION**: Looping tween on StyleBox border_color — must ensure each FillBar has its own StyleBox instances.
- **Advisory**: Auto-claiming multiple levels could cause re-entrancy if reward handlers trigger currency changes. Need guard flag.

### The Architect (Dependencies & Connections)
- **Low risk**: `level_up_ready` signal semantic shift from "pending, awaiting action" to "just happened." Rename suggested but not blocking.
- **Medium risk**: Rapid-fire `rewards_claimed` — multiple board switches in one frame could kill camera tweens. Suggested `await get_tree().process_frame` between iterations.
- **Medium risk**: Materialize timing — row may not have layout size when `materialize()` is called. Use `call_deferred`.
- **No risk**: No circular dependencies introduced.

### The Newcomer (Readability & Clarity)
- One-line comment needed explaining auto-claim intent in `_drain_pending`.
- `_is_new` lifecycle across three methods needs documentation. Renamed to `_needs_attention`.
- Magic numbers (0.9 threshold, 0.4 lightened) should come from VisualTheme exports.
- "attention" is the right vocabulary word; `_is_new` renamed to `_needs_attention` for consistency.

### The Consistency Lover (Standardization)
- `set_attention()` naming is acceptable (follows `set_*` pattern).
- StyleBox mutation is consistent with existing `apply_fill_colors()` pattern.
- New VisualTheme exports follow existing prefix conventions.
- Type annotations needed on all new methods.
- No blocking concerns.

## Disagreements

None — all agents converged. Key consensus:
1. Extract particle overlay to avoid HBoxContainer layout conflicts
2. Use `call_deferred` for materialize pivot_offset
3. Add re-entrancy guard in LevelManager
4. Rename `_is_new` to `_needs_attention`

## Resolutions

- **Camera shake duplication**: Accepted as-is. The board_manager shake is ~15 lines of `_process` logic. Extracting a shared utility for two callers would be premature. If a third caller appears, extract then.
- **Particle overlay**: Used `top_level = true` on a Control child to escape HBoxContainer layout.
- **Materialize timing**: Used `call_deferred` to set pivot_offset after layout pass.
- **Blink utility**: Made `blink_control()` a reusable method on VisualTheme (like `pulse_control()`), per user request for reuse with icons later.

## Final Plan

See `/Users/kjbrown/.claude/plans/elegant-enchanting-matsumoto.md`

### Files Modified
- `style_lab/visual_theme.gd` — New export group + `blink_control()` utility
- `autoloads/level_manager/level_manager.gd` — Auto-claim via `_drain_pending()`
- `entities/level_progress_bar/level_progress_bar.gd` — Shake + particles
- `entities/board_manager/board_manager.gd` — Camera shake on level-up
- `entities/fill_bar/fill_bar.gd` — `set_attention()` method
- `entities/upgrade_row/upgrade_row.gd` — `materialize()` + attention lifecycle
- `entities/plinko_board/upgrade_section.gd` — Trigger materialize on runtime unlocks
- `entities/main/main.tscn` — Remove LevelUpDialog node
- `entities/level_up_dialog/` — Deleted entirely
