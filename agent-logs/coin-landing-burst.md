# Coin Landing Burst — downward particle explosion

## Feature description

When a coin lands in a bucket it currently just `queue_free()`s and vanishes
(`PlinkoBoard.finalize_coin_landing`). Instead, each coin should burst into
small particles that spray **downward** (carrying the coin's falling
momentum — a falling fountain below the board, not a radial firework), tinted
the coin's own color. The board can land hundreds of coins/sec, so the effect
must have a hard, bounded per-frame cost regardless of coin volume.

User decisions: rate-capped at high volume (bound emissions/sec like the
existing `drop_burst`); falling-spray motion (downward cone + gravity, fades
over ~0.5s below the board).

## Round 1 — Concerns (six personalities, parallel)

**Janitor (Cleanliness).** Inline implementation would copy ~130 lines of the
`drop_burst` pool/sync/rate-limit machinery into the already-2171-line
`plinko_board.gd`; three explosion patterns already exist (drop_burst,
menu_board `_explode_coin`, prestige_vfx). Wants the pooled-particle pattern
extracted into a reusable, self-contained unit.

**Godot Guru (Engine).** Pushed for `GPUParticles3D` as the idiomatic
high-volume tool. Flagged real issues regardless of approach: pool-sizing math
for hundreds/sec, O(active) per-frame `set_instance_*` cost, world→local
coordinate conversion, `Engine.time_scale` (prestige slow-mo) freezing
in-flight particles, node-creation lifecycle, prestige-coin skip.

**Architect (Dependencies).** Suggested a `Coin` signal + PlinkoBoard reaction
for "signals up, calls down". Flagged: prestige coins bypass `queue_free` and
must also skip the burst; must read live `theme` (no caching) so theme swaps /
challenge suppression apply; `finalize_coin_landing` already crowded.

**Newcomer (Readability).** `coin_explosion_*` collides with the existing
`coin_land_particle_*` fields; magic numbers (cone angle, gravity, speed)
need named constants + the kinematic formula needs a docstring; pool-overflow
silent skip needs a comment.

**Consistency Lover (Standardization).** Naming should parallel `drop_burst_*`
and the `*_enabled` toggle convention; color correctly comes from
`get_coin_color(coin_type)` (coin-type-driven, like `coin_halo` /
`coin_impact_squash`) not a Palette source — but document that choice; new
`@export` defaults auto-apply so preset `.tres` need no edits; register a
`coin_burst` key in AudioManager's VFX override list like `drop_burst`.

**Test Lead (Testability).** Extract pure, RNG-injectable static functions
(`seed_particle`, `position_at`, `alpha_at`, pool acquire/release) separate
from `MultiMesh.set_instance_*` side effects so they unit-test headlessly with
a bare instance. ~14 test cases enumerated.

## Round 2 — Resolutions

- **MultiMesh, not GPUParticles3D.** `ParticleProcessMaterial` compiles a
  shader on first use → first-coin-land stutter risk given documented
  first-drop lag history; one emitter can't burst at many bucket X's. The
  Guru's per-frame-cost concern is instead met by a bounded pool + per-second
  emission cap (the proven `drop_burst` mechanism). Time-scale and
  world→local concerns accepted and designed in.
- **Self-contained `CoinBurstField` node** (own scene/script + pure seam
  functions), not inline in `plinko_board.gd`. Satisfies Janitor + Test Lead +
  "scenes are self-contained". Existing `drop_burst` left untouched (no
  unprompted refactor of working code); future consolidation noted as tech
  debt only.
- **Direct call, not a new signal.** `drop_burst` and `bucket.pulse()` are
  already invoked directly in the drop/landing path, not via signals; matching
  that is the consistent choice. PlinkoBoard owns its child CoinBurstField and
  calls down to it. Architect's prestige-skip + live-theme-read accepted.
- **Naming `coin_burst_*`** (parallels `drop_burst_*`); avoids the
  `coin_land_particle_*` collision. Color via `get_coin_color(coin_type)` with
  an inline rationale comment. Cone half-angle a named `const`; kinematic
  formula gets a docstring. Registered in AudioManager VFX overrides.

No disagreement survived to Round 3; no user escalation needed. The two user
decisions (rate-cap, falling-spray) were confirmed via question, not conflict.

## Final plan

See `~/.claude/plans/i-want-a-new-melodic-russell.md` (approved). Summary:
self-contained `CoinBurstField` (entities/coin_burst_field/) owning a pooled
MultiMesh, reusing `drop_burst_multimesh.gdshader`; pure static
`seed_particle` / `position_at` / `alpha_at` + free-index pool; `_process`
sync with time-scale-corrected delta; `spawn(world_pos, color)` called from
`PlinkoBoard.finalize_coin_landing` before `queue_free`, gated on non-prestige
+ live `theme.coin_burst_enabled`. New `coin_burst_*` theme block, AudioManager
`coin_burst` VFX override, headless `test/test_coin_burst.gd`.

## Post-Implementation Review

Six personalities reviewed `git diff main...HEAD` (Janitor, Godot Guru,
Architect, Newcomer, Consistency, Test Lead).

**Zero blocking from Janitor / Godot Guru / Architect / Consistency.** Clean
separation, no duplication of drop_burst, correct prestige skip, correct
live-theme read, conventions followed.

Triaged concerns + resolutions:

- **Rate-limit charged even on a zero-particle (pool-exhausted) burst**
  (Newcomer BLOCKING; Guru/Architect called it intended). Verdict: near-
  unreachable under default config (rate cap ≪ pool) but trivially
  improvable. **Fixed:** timestamp recorded only when ≥1 particle spawned;
  partial burst still counts as one event (`return`→`break`).
- **Rate limit untested** (Test Lead BLOCKING). Valid per project test
  policy. **Fixed:** added `test_rate_limit_blocks_excess_bursts`,
  `…_not_charged_when_pool_empty`, `…_window_prunes_old_entries`,
  `test_enabled_spawn_enqueues_particles`.
- **`_process` expiry/slot-release untested** (Test Lead BLOCKING). **Fixed:**
  null-guarded the MultiMesh writes (only scene-tree side effects) so the
  lifetime bookkeeping is headlessly unit-testable; added
  `test_process_expiry_releases_slot`.
- **Magic numbers / docs** (`-9999`, time-scale epsilon, RNG seeding)
  (Newcomer). **Fixed:** added explaining comments.
- **`_HIDDEN_XFORM` should use `Basis.IDENTITY.scaled(...)`** (Guru ADVISORY).
  **Rejected (agent error):** `.scaled()` is a method call, not a constant
  expression — invalid for a `const`. Reverted and added a comment so it
  isn't "fixed" again. (Triage caught this; the project's "agents sometimes
  flag non-issues" guidance applied.)
- **CLAUDE.md docs not updated** (Architect). Done as a separate docs commit
  per the Branch Workflow.

Result: full suite green (24 suites, `test_coin_burst` 33 passed).
