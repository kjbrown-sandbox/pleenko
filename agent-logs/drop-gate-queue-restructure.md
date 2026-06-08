# Drop Gate + Queue Economy/UI Restructure

## Feature description

Rework the drop-feel and its readouts:

- Every board starts with a 1-slot queue; the queue upgrade becomes `+1` (was
  `0 → 2`). The always-present first slot is "free" (no rate bonus).
- The drop button stops being a fill/progress bar. A new **gate** beneath the
  spawn (two flaps that swing down to vertical and back) visualises drop timing.
- The autodropper count moves into the button face (`Drop gold • 1 auto`); the
  rate moves to the right of the gate, inverted from a delay (`3s`) into a
  decomposed throughput readout (`0.33 + (4 * 0.07) = 0.60 g/s`).

## Locked decisions (with the user)

- **Rate display = exact, 2 decimals.** Base cadence stays 3.0s; the printed
  total equals the real `1/effective_delay`; component terms are rounded for
  legibility (may differ by a hundredth).
- **One shared gate** at the spawn + one rate text. Advanced coins reuse it.
- **Economy:** per-extra-coin bonus = 1/5 of base rate (`QUEUE_RATE_BONUS_PER_COIN
  0.15 → 0.20`), applied to `max(0, count - 1)`.

## Six-lens review (planning)

- **Godot Guru:** Gate is a self-contained `class_name` `Node3D` with `Node3D`
  pivots at the seam for a correct hinge axis; manual `_process` advance divided
  by `Engine.time_scale` (CoinBurstField idiom) instead of a Tween; self-gates
  `_process` off at rest. Pure view, calls-down only. No physics (honours the
  "pegs are visual" invariant — the gate is visual too).
- **Architect:** No new cross-system signals. Gate is a leaf child of
  `PlinkoBoard`; only two new call-down sites, both already on the drop path
  (`_on_drop_timer_done` open, `_launch_coin` close). Removed the now-pointless
  `BoardManager` ↔ `coin_queue.count_changed` subtext subscription (rate lives
  board-side now).
- **Janitor:** Rate decomposition centralised in `FormatUtils.drop_rate_text`
  (one source of truth, no board/section duplication). `set_drop_subtext` and the
  `DropMainLabel`/`DropAdvancedLabel` subtext nodes are now dead — left in place
  (empty, harmless) to avoid layout churn mid-iteration; advisory cleanup later.
  `_drop_immediate_coin` / the `elif` branch in `request_drop` are now
  unreachable (capacity ≥ 1 makes `has_queue()` always true) — left as-is.
- **Consistency:** Gate colour from `ThemeProvider.theme.peg_color` (no raw
  Color); timings/sizes are local consts (MenuBoard precedent). Bullet is a real
  `•` (U+2022). Direct method refs, explicit types.
- **Newcomer:** Gate states are a named enum; the "first slot is free" `count - 1`
  offset and the `base/5` derivation are commented at both the economy and
  display sites.
- **Test Lead:** `FormatUtils.drop_rate_text` / `currency_letter` and
  `_queue_capacity_for_level` are pure → unit-test at ship. Add a test asserting
  the printed total tracks `1/get_effective_drop_delay()` and that `extra == 0`
  collapses to the short form. Update `test_upgrade_tuning.gd` capacity cases
  (level 0 → 1).

## Final plan

See `~/.claude/plans/g-s-is-both-coins-dapper-brooks.md`. Implemented on branch
`feature/drop-gate-queue-restructure`. Tests deferred to ship per CLAUDE.md.

Files: `entities/drop_gate/drop_gate.gd` (new), `entities/plinko_board/plinko_board.gd`,
`entities/board_manager/board_manager.gd`, `entities/drop_section/drop_section.{gd,tscn}`,
`scripts/format_utils.gd`. Untouched (concurrent agent): `refined_baseline_button.gd`,
`audio_manager.gd`.
