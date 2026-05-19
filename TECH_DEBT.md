# Tech Debt Backlog

Findings from a whole-codebase 5-lens audit (Janitor / Godot Guru / Architect /
Consistency / Test Lead), 2026-05-17. **Deferred until after the demo ships.**

Items where multiple lenses independently flagged the same thing are marked
**[convergence]** — highest confidence. Each item cites `file:line` where it's a
concrete defect. Nothing here has been changed yet.

Recommended order is at the bottom.

---

## Tier 0 — Actual bugs hiding in the debt (small, high-impact)

### T0.1 — Deflector intro replays for existing players (missing save migration)
- `autoloads/save_manager/save_manager.gd` — `SAVE_VERSION = 6`, last migration v5→v6.
- The deflector merge added `onboarding.deflector_intro_seen` / `deflector_placed`
  / `prestige_deflector_seeded` and `boards.board_state.*.deflectors` with **no
  v6→v7 migration**. `OnboardingProgress.deserialize` defaults
  `deflector_intro_seen` to `false`, so any pre-deflector save that already
  implies an unlocked deflector (orange-prestiged or level-table unlock) replays
  the first-time intro on load — the exact regression the v5→v6 autodropper
  migration (`save_manager.gd:310-318`) was written to prevent.
- **Fix:** bump `SAVE_VERSION` to 7; add a migration seeding
  `deflector_intro_seen = true` for saves whose state implies the deflector is
  already owned (mirror the v5→v6 autodropper pattern).

### T0.2 — Offline earnings silently desync from live earnings
- `scripts/offline/offline_calculator.gd:206-225` (`_get_bucket_layout`) +
  Pascal probs `:190-203` reimplement the bucket value/currency/lattice formula
  that lives in `entities/plinko_board/plinko_board.gd:1604-1610` /
  `_bucket_value_for_distance` (`plinko_board.gd:1669-1673`).
- The offline copy **omits the `bucket_value_percent_bonus`** the live path
  applies (`plinko_board.gd:1674`) → players earn a different rate offline vs.
  online *today* (live bug, not hypothetical).
- **Fix:** extract one pure `scripts/bucket_math.gd` (value + currency +
  probability; primitives + `TierRegistry` only) consumed by both
  `PlinkoBoard` and `OfflineCalculator`.

### T0.3 — `TierRegistry.get_base_drop_delay()` ignores its argument
- `autoloads/tier_registry/tier_registry.gd:136-138` takes `board_type`,
  computes `idx`, then unconditionally `return BASE_DROP_DELAY + 1` — every
  board gets the constant 3.0 (`plinko_board.gd:214`).
- Advertises a per-tier seam that silently doesn't function; a trap the moment
  VIOLET/BLUE/GREEN boards ship.
- **Fix:** implement from `TierData`, or delete the param/`idx` and rename to an
  honest constant accessor.

---

## Tier 1 — Structural debt growing fastest

### T1.1 — `plinko_board.gd` is a 2105-line god object **[convergence: Janitor, Architect, Godot Guru]**
- `entities/plinko_board/plinko_board.gd` — ~10 responsibilities, 95+ funcs, 11
  autoload deps. The convergence point every gameplay feature edits (deflector
  added 104 lines; multi-drop, queue-rate-bonus, gameplay-target all recent
  accretions). Largest-churn file; how the shipped hack code (T3.1) stayed hidden.
- **Fix (incremental, one extraction per PR):** `BoardGeometry` (pure
  `position_x_for`/`peg_index`/`cell_to_world`/`next_lattice_cell`/
  `predicted_bucket_index` — also the most testable), `DeflectorController`
  (~lines 1272-1418), `PegRenderer` (peg multimesh + flashes/pulses + halo/ring
  VFX), `CoinPool` (coin multimesh allocate/release/sync/grow). Target core
  < ~800 lines. Scattered `ChallengeProgressManager`/`PrestigeManager` modifier
  reads (`:144,211,212,220,221,224,660,1674,2076,2080`) → one
  `_recompute_modifiers()`.

### T1.2 — Duplicated intro animators + triplicated particle code **[convergence: Janitor, Consistency]**
- `entities/main/autodropper_intro_animator.gd` (177) and
  `entities/main/deflector_intro_animator.gd` (154) are ~90% identical and
  **already diverge inconsistently**: different re-entry guards
  (`_is_animating` vs `_is_animating or _completed`), different "target not
  ready" contracts (autodropper burns the one-shot, deflector retries),
  different lambda return-type annotation.
- Burst+swoop particle pattern is a 3rd copy in
  `entities/level_section/level_section.gd:268-332` (same magic ranges,
  divergent `arrived[0]`/`state[0]` naming for identical race logic).
- `scripts/vfx_utils.gd` already exists as the extraction home (hosts
  `spawn_shockwave`, correctly reused).
- **Fix:** `VfxUtils.spawn_burst_swoop(overlay, sources, targets, color,
  on_all_arrived)` covering the full two-phase lifecycle + re-entry guard;
  extract a shared `IntroAnimator` base / parameterized `UpgradeIntroAnimator`
  (source `UpgradeType`, `target_position: Callable`, `on_complete: Callable`).
  Do this **before** the next "first-time upgrade X" intro is cloned.

### T1.3 — Coin Tween churn vs. the "tens of thousands of coins" constraint **[Godot Guru]**
- `entities/coin/coin.gd:106-111,183-195` — `start()` + each bounce call
  `create_tween()` 2-3×, all appended to `_active_tweens` (`coin.gd:23`) which
  is **never cleared until the coin frees** (`kill_tweens()` only called by
  `prestige_animator.gd:144`). ~40 live SceneTreeTweens per ~20-row coin.
- `_grow_coin_multimesh` (`plinko_board.gd:557-582`) does an O(n) per-element
  scripted buffer copy **mid-drop** → the spike `project_first_drop_lag.md`
  chases.
- `_bounce_or_despawn` re-reads `ThemeProvider.theme` (autoload prop) per bounce
  per coin; only `_fall_speed_multiplier` is cached.
- Ties directly to the existing deferred memory notes
  `project_tween_elimination_plan.md` + `project_first_drop_lag.md` — this audit
  is the concrete justification to prioritize them.
- **Fix:** chain x/y into one reused tween (or `advance()` manually); drop/clear
  `_active_tweens` for non-prestige coins; pre-size the coin MultiMesh or grow
  via a single `MultiMesh.buffer` set; cache theme physics constants at
  `start()` alongside `_fall_speed_multiplier`.

---

## Tier 2 — Missing safety nets (tests)

### T2.1 — ChallengeTracker (445 lines) has zero tests **[Test Lead — highest blast radius]**
- `autoloads/challenge_manager/challenge_tracker.gd` — the live eval engine for
  every objective + constraint + the two-phase Survive WAITING→SURVIVING. Not
  one test references it. `_is_objective_met`, `_try_advance_bucket_group`,
  `_process_survive`, `get_progress_text`, static `_bucket_key` are headless-
  testable with the stub-`BoardManager` pattern already in
  `test_soft_lock_rescue.gd`. Regression = challenges silently
  impossible/auto-complete; objectives are an actively growing list.

### T2.2 — No save→load round-trip or `_migrate()` test **[Test Lead — reinforces T0.1]**
- No test serializes a populated game and reads it back; the strict
  deserialization order (Prestige→ChallengeProgress→Onboarding→Level→Currency→
  Upgrade→Board) is documented as load-bearing but enforced by nothing.
- `_migrate()` (`save_manager.gd:282`, 5 sequential version steps) is a pure
  `(Dictionary,int)→Dictionary` — trivially testable, **best risk-reduction per
  line in the codebase**; a botched migration bricks every existing save.
- **Fix:** in-memory round-trip per manager + a fixture-per-version `_migrate`
  test.

### T2.3 — Other untested core economy **[Test Lead]**
- LevelManager primary threshold/claim path (`_on_currency_changed` multi-level
  `while` + `claim_rewards` queue) — only the `ensure_state_for_level` failsafe
  is tested, not the primary path.
- Challenge constraints (`constraints/*`) + starting conditions
  (`starting_conditions/*`) — 10 tiny self-contained classes, zero coverage;
  risk = unwinnable/unlosable challenges.
- CurrencyManager cap-raise economy (`currency_manager.gd:54-107`) — the
  cross-tier "raise gold caps with orange" loop, untested.

---

## Tier 3 — Consistency / hygiene (cheap, do opportunistically)

### T3.1 — Shipped debug/hack code **[convergence: Janitor, Consistency]**
- `plinko_board.gd:62-63,400-405` — `hack_space`/`hack_burst` runs an
  `Input.is_action_pressed` + inner loop check at the top of `_process` on
  every board every frame (hot path).
- `main.gd:13,240-276` — `demo_mode` exported `true`; `_debug_*` prestige
  helpers reach into private board internals (`board._will_trigger_prestige`,
  `_tween_camera_to_active_board`) and re-implement coin spawn wiring that will
  silently rot.
- **Fix:** delete `hack_*`; move `_debug_*` behind `OS.is_debug_build()` / a
  debug-only node; decide & document `demo_mode`'s real default.

### T3.2 — Mixed indentation (whitespace-sensitive language) **[Consistency — mechanical, zero-risk]**
- `autoloads/currency_manager/currency_manager.gd` and
  `entities/drop_section/drop_button.gd` use **3-space** indent; the other ~88
  `.gd` files use tabs. Corrupts every diff/edit. Reindent to tabs.

### T3.3 — No error-severity convention **[Consistency]**
- Zero `push_error`/`push_warning`/`assert` in the entire source tree;
  data-loss-class failures (`save_manager.gd` parse/open failures) logged via
  `print()` at the same severity as `"Game saved."`. No release-build gating
  for `[DEBUG]` prints. Adopt `push_error`/`push_warning`; gate debug prints.

### T3.4 — Rule outliers
- 27 untyped locals (9 in `plinko_board.gd`) vs ~99%-followed "type locals" rule.
- 17 inline-lambda `.connect()` vs 135 named-ref — no learnable rule for which.
- ~39 ad-hoc `print("[Subsystem] …")` calls, no logging abstraction;
  `background_particles.gd:30,38` spam every theme setup.
- 3D burst-particle free-list logic copy-pasted across `_spawn_drop_burst_3d` /
  `_spawn_ripple_particles` / `_spawn_edge_splash` (`plinko_board.gd:742-855`)
  — folds into the T1.1 `CoinPool`/`PegRenderer` extraction. **Now a 4th
  independent copy:** `entities/coin_burst_field/coin_burst_field.gd` (pooled
  MultiMesh + free-index stack + `_sync`/expiry + per-second rate limit)
  re-implements the same pattern. This was a *deliberate* call in the
  coin-landing-burst plan (self-contained node; don't refactor working
  `drop_burst` unprompted), but it raises the duplication-per-future-particle-
  effect multiplier. Consolidation target: one `PooledParticleField`
  class/scene (MultiMesh + slot pool + analytic `_sync` + rate cap) that
  `drop_burst`, `CoinBurstField`, ripple/edge-splash, and `menu_board._explode_coin`
  / `prestige_vfx` all parameterize. Janitor flagged this in both the planning
  and post-impl reviews (`agent-logs/coin-landing-burst.md`).
- `Engine.time_scale` divide-by-zero guard epsilon is inconsistent:
  `0.0001` in `coin_burst_field.gd` (`_process`) vs `0.001` in
  `prestige_animator.gd` / `audio_manager.gd`. Harmless (any small positive
  value works) but should be one shared named constant when the slow-mo
  correction is factored out.

### T3.5 — CLAUDE.md "living documentation" has drifted **[Architect — process debt, enabled T0.1]**
- `PerformanceSettings` & `AnalyticsManager` autoloads and the entire deflector
  subsystem are absent from CLAUDE.md System Responsibilities; it still says
  `SAVE_VERSION = 6`. The per-merge "update living documentation" workflow step
  was skipped for the deflector / FPS / reset merges — this is the root enabler
  of T0.1.
- **Fix:** re-sync System Responsibilities; treat the doc-update workflow step
  as non-optional going forward.

---

## Recommended order (post-demo)

1. **Tier 0** (T0.1–T0.3) — small, contained, high-impact; T0.1 ships a
   regression today.
2. **T2.2** (migration + round-trip tests) — cheap, directly de-risks T0.1.
3. **T1.2** (shared intro/particle infra) — highest duplication-per-future-
   feature multiplier; fix before the next intro is cloned.
4. **T1.1** incrementally — start with the pure `BoardGeometry` extraction,
   which also unblocks T2.1-style headless testing.
5. **T3.5** CLAUDE.md re-sync + remaining Tier 3 hygiene alongside whatever
   files you're already touching.

Deferred ties to existing memory: `project_tween_elimination_plan.md`,
`project_first_drop_lag.md` (both → T1.3).
