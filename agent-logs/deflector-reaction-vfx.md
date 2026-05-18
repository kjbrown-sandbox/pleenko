# Feature: Deflector Reaction VFX

## Feature Description

Peg deflectors have no feedback when a coin interacts with them. Add two coupled,
pure-view reactions:

- **HIT** (coin follows the deflector's set direction, ~75% bias case): the placed
  arrow briefly flashes the coin's colour and "swats" (nudges position) in its set
  direction, then eases back to rest — the deflector analogue of a Bucket lighting
  up when a coin lands.
- **MISS** (coin goes against the deflector, ~25% case): a brief same-shape ghost
  arrow appears on the *opposite* side (the path the coin actually took), in the
  red coin colour, fading opacity 1 → 0 into the background — a "didn't work this
  time" cue.

Zero gameplay impact; no change to coin trajectories.

---

## Round 1 — Parallel Personality Analysis

### The Janitor — Code Cleanliness
- **[BLOCKING]** Extract the *whole* arrow placement transform, not half — MISS needs position+rotation; don't copy-paste the `±PI/2` rotation literal.
- **[BLOCKING]** A parallel ghost-arrow pool duplicates the `_placed` pool lifecycle (factory + trim loop + `_exit_tree` + theme loop). Prefer fire-and-forget transient nodes; a pool only earns its keep when nodes are reused.
- **[BLOCKING]** All arrow materials (incl. red ghost) must route through `_arrow_mat()` — no second material path.
- **[BLOCKING]** HIT mutates the persistent pooled material; needs Bucket-grade kill discipline wired into `refresh()`/`_apply_theme()`/`set_active(false)`, not only `_exit_tree`.
- **[ADVISORY]** `deflector_outcome` risks being a 4th source of truth for deflector state; keep it a pure comparator over the model, not a reimplementation of bias.
- **[ADVISORY]** Responsibility creep in `deflector_editor.gd` (~386 lines) — flag editor-vs-`DeflectorVfx`-node split to user.
- **[ADVISORY]** `flash_deflector`/`flash_miss` asymmetric; name as a pair.

### The Godot Guru — Engine Best Practices
- **[BLOCKING]** Don't `create_tween()` per bounce blindly — the file already has an allocation-free `_process`-advanced dict (`_active_flashes`) for persistent peg VFX and per-event spawn+tween+`queue_free` (`_spawn_peg_halo/ring`) for transient accents. Match the right one per case.
- **[BLOCKING]** `_apply_theme()` reassigns `material_override` — kill in-flight tint tweens first or they orphan onto a dead material.
- **[BLOCKING]** Match Bucket's `bind_node()` so a hidden/removed arrow's tween auto-dies.
- **[BLOCKING]** `refresh()` reuses `_placed[i]` by key-array index, not peg — a stale tween will hijack the wrong arrow; kill unconditionally on refresh.
- **[BLOCKING]** Round-robin MISS pool truncates overlapping fades — use free-list grow-on-demand, or no pool.
- **[ADVISORY]** Capture HIT rest position once from the peg, not by reading `arrow.position`.
- **[ADVISORY]** `depth_draw_never` ghost ordering — reuse `Z_LIFT`.
- **No concern:** Coin→board→editor is correct calls-down; keep RNG injectable in the pure helper.

### The Architect — Dependencies & Connections
- **No concern:** direction matches "signals up, calls down" exactly (Coin already calls `flash_nearest_peg` down; board already calls `_deflector_editor.refresh()` down). Place the new call adjacent to `flash_nearest_peg`.
- **No concern:** Coin↔deflector coupling stays at the existing boundary (passes only row/col/direction/coin_type; never sees `_deflectors`).
- **[BLOCKING]** Keep `deflector_outcome` a separate read-only helper; must NOT call `randf()`/`resolve_bounce_direction` (re-roll desyncs trajectory tests). `resolve_bounce_direction` stays bit-identical.
- **[BLOCKING]** Tri-state `±1/0` collides with `Enums.Direction` — use a named enum mirroring `enum ClickAction`.
- **[ADVISORY]** New ghost pool diverges from `_placed` on theme swap — make it short-lived (no pool) or fold into `_apply_theme`.
- **No concern:** ChallengeManager/BoardManager/PrestigeManager unaffected (no new signals/autoload edges; no save/mutation).

### The Newcomer — Readability & Clarity
- **[BLOCKING]** Tri-state int return collides with `±1 = Direction` in the same file — use `DeflectorOutcome` enum (mirror `ClickAction`).
- **[BLOCKING]** `flash_deflector`/`flash_miss` break verb/object naming and overload the lightweight "flash" verb — rename to the parallel pair `play_deflector_hit`/`play_deflector_miss` ("play" = multi-step anim, matches `play_prestige`/`force_play_bucket`).
- **[BLOCKING]** MISS-ghost "red, opposite side" will be misread as the red *tier currency* or a sign-flip bug — mandatory doc-comment stating red = deliberate negative cue and ghost = path-actually-taken.
- **[ADVISORY]** Every new method needs a `##` block; swat distance must be a fraction of `space_between_pegs`, not raw world units.

### The Consistency Lover — Standardization
- **[RULING] Decision (1):** swat/fade timings → **new `@export` fields on `VisualTheme`** (+ `deflector_reaction_enabled` toggle). Every analogous coin-reaction micro-VFX (peg flash/halo/ring, bucket) is theme-driven; the editor's local consts are geometry factors, not a timing precedent; `bucket.gd`'s `SING_DURATION` is a documented external-lock exception, not applicable.
- **[BLOCKING]** Tween idiom must match Bucket exactly (create_tween + chained set_ease/set_trans + stored member + `is_valid()` kill guard + `_exit_tree`).
- **No concern:** `flash_*`/`notify_*`/`deflector_outcome` naming fits; `deflector_outcome` must carry a `##` and return a named result not a magic int.
- **[BLOCKING]** Explicitly type all new params/returns/locals (inference fails off `get_coin_color(...)` chains).
- **[FLAGGED]** `Coin.notify_*` is Coin→board; deferred to Architect (resolved: idiomatic, matches `flash_nearest_peg`).

### The Test Lead — Testing & Testability
- **Confirmed:** `deflector_outcome` is unit-testable headless exactly like existing `test_deflector.gd` cases (bare `PlinkoBoard.new()`).
- **[BLOCKING]** No auto-discovery — new `test_*` must be registered in `_run_tests()`.
- Test cases: NONE (empty), NONE (non-deflected peg while another has one), FOLLOWED & MISSED for **both** LEFT and RIGHT deflectors.
- Add `test_notify_deflector_resolved_null_editor_safe` (bare board has no `_deflector_editor`).
- **Confirmed:** no existing suite at risk (`resolve_bounce_direction` untouched; no Coin-scene tests).
- Methods to add: `test_deflector_outcome`, `test_notify_deflector_resolved_null_editor_safe`.

---

## Round 2 — Resolution

The only true conflict was **Godot Guru (avoid per-event Tween / use the
`_process` dict pattern)** vs **Consistency Lover (match Bucket's `create_tween`
idiom)**. Resolved with code evidence rather than a further debate round:

`flash_nearest_peg` (`plinko_board.gd:1881-1978`) uses **both** idioms, split by
**persistence**: `_active_flashes`/`_active_peg_pulses` dicts advanced in
`_process` for the **persistent** peg multimesh; per-event spawn + `create_tween()`
+ `tween_callback(queue_free)` (`_spawn_peg_halo`, `_spawn_peg_ring`) for
**transient** accent nodes. The two cases map cleanly onto that split:

- **HIT** animates the *persistent* pooled `_placed` arrow → Bucket-style
  `create_tween()` + `bind_node` + kill-prior + deterministic restore
  (Consistency Lover satisfied; Godot Guru #2/#3/#4 satisfied).
- **MISS** is a *transient* accent → `_spawn_peg_halo`-style spawn + tween + 
  `tween_callback(queue_free)`, **no pool** (dissolves Godot Guru round-robin,
  Janitor parallel-pool, Architect theme-divergence in one move).

All other items reached consensus without conflict. No escalation to the user.

---

## Final Plan

See `/Users/kjbrown/.claude/plans/groovy-crunching-clock.md` (approved). Summary:

- `visual_theme.gd`: `deflector_reaction_enabled` + `deflector_hit_swat_factor` +
  `deflector_hit_swat_duration` + `deflector_hit_recover_duration` +
  `deflector_miss_fade_duration` (`@export`, doc-commented, in the `peg_*` block).
- `plinko_board.gd`: `enum DeflectorOutcome { NONE, FOLLOWED, MISSED }`; pure
  `deflector_outcome(row,col,direction)`; `notify_deflector_resolved(...)`
  (null-editor guard, dispatches down, no save/mutation).
- `coin.gd`: one `board.notify_deflector_resolved(...)` call adjacent to
  `flash_nearest_peg`, before `_row/_col` reassignment.
- `deflector_editor.gd`: extract `_arrow_rest_position`; `# ── Reaction VFX ──`
  with `play_deflector_hit` (Bucket tween, `_hit_tweens` dict, kill discipline in
  refresh/_apply_theme/set_active/_exit_tree) and `play_deflector_miss`
  (spawn + alpha fade + `queue_free`, no pool); both gated on
  `deflector_reaction_enabled`.
- `test/test_deflector.gd`: `test_deflector_outcome`,
  `test_notify_deflector_resolved_null_editor_safe`, registered in `_run_tests()`.

## Post-Implementation Review

_(to be appended after the implementation review per CLAUDE.md)_
