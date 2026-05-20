# Juicy Add-Rows Upgrade Animation

## Feature description (user, verbatim)

> When you buy bucket value, it starts in the middle and ripples outwards. I
> want the same thing to happen for add rows, only it starts on the left and
> then ripples to the right. Additionally, the new buckets should spawn at the
> same level as the previous buckets and then "fall" to their new level and
> bounce slightly (the bounce is like bucket value). The buckets shouldn't all
> spawn at the same time but rather use the quick pace that bucket value does
> to "activate" the other buckets. Additionally, there should be a soft camera
> zoom that "follows" the glissando from left to right, so that it feels like
> we're watching a piano player run their finger across the keys.

## Round 1 — six-lens evaluation (consolidated into the design phase)

The CLAUDE.md "six personalities" review was folded into the Plan-agent design
prompt rather than run as six independent debaters, because the harness Plan
workflow constrains us to a single Plan agent. Each lens evaluated the proposed
implementation; **no lens raised a blocking concern.**

- **Janitor** — Strong reuse: `_upgrade_animating`, `_upgrade_ripple_tween`,
  `mark_singing`, `force_play_bucket`, the pulse two-segment shape. New surface
  is one method + one pure helper + 5 theme exports + 2 signals. Risk: the
  fall/bounce duplicates `pulse()`'s two-segment math — mitigated by extracting
  `Bucket.fall_to_rest()` so the math lives once, beside `pulse_up`.
- **Godot Guru** — Tween-driven (no `_process` polling). `create_tween().bind_node(self)`
  matches the ripple. Concern: two tweens touching `position:y` (fall + stray
  pulse) — mitigated by routing the fall through Bucket so it kills its own
  `_press_tween` first (matching `pulse_down` `:181-182`).
- **Architect** — Camera ownership stays in BoardManager (CLAUDE.md "signals
  up, calls down" rule). PlinkoBoard emits two signals: `row_upgrade_starting`
  (BoardManager suppresses the default fit-tween) and `row_upgrade_sweep_started`
  (BoardManager drives the zoom/track/settle). A Main-level animator was
  considered and rejected — this animation needs no time-scale control, no
  coin ejection, no scene transition; a signal seam is strictly smaller than
  another Animator child.
- **Newcomer** — The new method mirrors `_play_bucket_value_upgrade_ripple` so
  readers who understand the ripple understand this. Naming (`row_upgrade_*`)
  parallels the existing `bucket_value` ripple naming. The `2*vertical_spacing`
  offset math is the one subtle bit — guarded by an `assert` and a derivation
  comment.
- **Consistency Lover** — Inline lambdas inside the tween match the ripple's
  local style; theme exports in `@export_group("VFX")` beside
  `bucket_active_scale_peak`; horizontal pan mirrors
  `ChallengeGroupingManager._tween_camera_to_group`; settle uses the exact
  ease/trans of `_tween_camera_to_active_board`; tests added to
  `test_plinko_board.gd` next to `test_get_bounds_geometry`.
- **Test Lead** — Extracted pure scheduler `_compute_row_upgrade_schedule`
  takes primitives only (mirrors `_bucket_value_for_distance`/`get_bounds`),
  unit-testable headless. Tween/audio/camera orchestration stays
  integration-only, consistent with the ripple itself being untested as a
  whole.

## Round 2 — user-decided product/feel questions

Conflicts that genuinely required the user to pick (not blocking concerns):

| Topic | Decision |
|---|---|
| Glissando pace | Iterated: initially per-bucket at `AudioManager.BUCKET_WAIT / 2.0` (0.25s) reusing the ripple's expression; later decoupled into its own theme field `row_upgrade_glissando_interval` (default 0.125s) after user feedback that the cascade should overlap more buckets and be independent of the per-bucket fall duration. |
| Glissando pitch | Ascending left→right: `degree = column index`. Diatonic harp-style run that re-octaves every ~8 buckets (chord array length) — intended, do not modify shared audio. |
| Camera | Zoom in → track X with the wavefront → zoom out to fit the bigger board. Driven by BoardManager (it owns the camera); PlinkoBoard only emits signals up. |
| New pegs | No fade/drop. Hidden on rebuild, revealed instantly column-by-column once the bucket to that peg's left has started dropping. |
| Drops during sweep | Purely visual, not paused. Gated only by the existing `_upgrade_animating` flag (mirrors the bucket-value ripple). Accept the brief, rare visual mismatch of a coin passing the rising row. |

## Final plan

See `/Users/kjbrown/.claude/plans/so-i-want-some-fancy-wolf.md` for the
canonical plan. Critical files:
- `entities/plinko_board/plinko_board.gd` — 2 new signals, `_compute_row_upgrade_schedule`,
  `_play_row_upgrade_glissando`, peg hide/reveal, rework `add_two_rows`.
- `entities/bucket/bucket.gd` — `fall_to_rest()` + `lift_for_fall()` beside `pulse_up`.
- `entities/board_manager/board_manager.gd` — connect 2 signals, suppress flag
  in `_on_board_rebuilt`, zoom-in/track/settle camera tween.
- `style_lab/visual_theme.gd` — 5 new `@export` fields in the VFX group.
- `test/test_plinko_board.gd` — 4 pure-logic tests of the scheduler.

## Post-Implementation Review

(To be appended after the user confirms the implementation looks good.)
