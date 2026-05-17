# Pointer Peg / Deflector Upgrade — Brainstorm Brief

## Feature concept

A new upgrade that lets the player attach a pinball-style paddle to a single peg. Any coin that hits that peg is forced to go in the chosen direction (left or right) instead of the normal 50/50 random pick. The player can choose the direction when placing, change it later, and remove the deflector.

## Working name

**Deflector** (preferred) — clear, mechanical, reads naturally as "deflect left/right". Alternative: **Nudger** if a lighter/idle tone is wanted. Other options considered: Pointer Peg, Flipper, Peg Guide, Bumper Guard.

## Open design questions (need decisions before implementation)

1. **Slot count.** How many deflectors can the player place at once? Likely scales with upgrade level (e.g., level 1 = 1 deflector, level N = N deflectors). Or a single binary unlock with a fixed count.
2. **Cost model.** Flat upgrade cost that unlocks N slots? Or per-placement cost in currency? Idle-game convention leans toward "unlock N slots" so placement itself is free and the player is rearranging strategy, not spending.
3. **Placement restrictions.** Any peg, or only certain rows? Edge pegs are a concern — a deflector pointing off-board needs handling (either disallow that direction at edge pegs, or treat off-board as "fall straight down").
4. **Per-board or global?** Following the existing per-board upgrade pattern (see `UpgradeManager` in CLAUDE.md), this should almost certainly be per-board.
5. **Visual treatment.** Suggested: a small colored paddle/arrow sticking off the side of the peg, clearly indicating direction. Must use palette colors from `ThemeProvider.theme` — never raw `Color` values (project convention).

## UI approaches considered

### Approach A: Click-to-cycle (simplest)
Click a peg → assigns Left. Click again → flips to Right. Click again → removes.
- Pros: Zero extra UI, no popups, no modes.
- Cons: No affordance. Players won't discover it without a tutorial hint. Accidental clicks during normal coin-dropping play are very likely.

### Approach B: Click peg → L/R/Remove popup
Tapping a peg opens a tiny floating 3-button strip near it.
- Pros: Explicit, discoverable.
- Cons: Adds floating UI; needs careful positioning so it doesn't go offscreen near the edges; risk of accidental opens during play.

### Approach C: Configure mode toggle (RECOMMENDED)
A dedicated mode button in the upgrade row (pencil/wrench icon). While active:
- Board dims slightly to signal "configure mode."
- Existing deflectors highlight their direction arrows.
- Clicking a peg either cycles direction (Approach A inside the mode) or opens the L/R/Remove popup (Approach B inside the mode).
- Exiting the mode returns to normal play.

Pros: Separates configuration gestures from normal play gestures — important because the player is also tapping the board area to drop coins during normal play. Fits idle-game conventions where deliberate config beats accidental nudges.

Cons: One extra mode to enter/exit. Slightly more work to implement.

### Approach D: Press-and-drag to set direction
Press and hold on a peg, drag left or right, release to confirm.
- Pros: Tactile, intuitive.
- Cons: Harder to implement given multimesh peg rendering. Mobile feel is good; desktop feel is awkward.

**Recommendation:** Approach C (Configure mode) + Approach B (L/R/Remove popup) inside the mode. Best balance of discoverability, safety from misclicks, and clarity.

## Technical wrinkle to flag

Pegs are currently **multimesh-rendered** for performance (see `PlinkoBoard` in CLAUDE.md — "peg + bucket multimesh rendering"). Individual pegs are not separate nodes, so making a peg clickable requires either:

- **Raycasting against peg positions:** Cast a ray from the camera through the mouse position, then find the nearest peg in the board's peg position list. Works without breaking the multimesh model.
- **Promoting deflector pegs to individual `MeshInstance3D` nodes:** Only the placed deflectors become real nodes (count is bounded by upgrade slots, so perf impact is small). Easier to attach the paddle visual as a child node.

Hybrid: keep all pegs in the multimesh for rendering, raycast against peg positions for click detection, and overlay a separate `MeshInstance3D` paddle node at each placed deflector's world position for the visual.

## Behavior changes to existing systems

- **`Coin.gd` / per-row pathing.** Coin currently picks left/right randomly per row when querying the next waypoint. Needs to consult a board-level "deflector at this peg?" lookup before the random pick. If a deflector exists, use its direction instead.
- **`PlinkoBoard.gd`.** Needs to own the deflector state (per-peg direction map), expose a query API for coins, expose a placement/remove API for the configure UI, and handle save/load of placements.
- **`UpgradeManager.gd`.** New upgrade definition for the deflector slot count, following the existing `BaseUpgradeData` resource pattern.
- **`SaveManager.gd`.** Bump `SAVE_VERSION`, add migration to default to "no deflectors placed" for existing saves. Serialize per-board deflector placements (peg index + direction).
- **Edge pegs.** Decide whether direction selection is restricted at edges, or whether off-board deflection falls straight down.

## Testing notes (project requires tests on bug fixes and feature changes)

- Deflector overrides random left/right pick at the targeted peg (deterministic per direction).
- Removing a deflector restores random pick.
- Edge peg behavior (whichever rule is chosen).
- Save/load round-trip of placements.
- Slot count enforcement: can't place more than upgrade level allows.
- Save migration for existing saves (no deflectors → still works).

## Project conventions to honor

- Signals up, calls down.
- Use palette colors from `ThemeProvider.theme`, never raw `Color`.
- Per-board upgrade state lives in `UpgradeManager`.
- Use `BaseUpgradeData` resource pattern for the upgrade definition.
- Scene-level state and APIs live in `PlinkoBoard`.
- Write tests for the changes before committing.

---

# Multi-Agent Planning Deliberation

Six personalities (Janitor, Godot Guru, Architect, Newcomer, Consistency Lover,
Test Lead) evaluated the proposed design in parallel.

## User decisions (locked before debate / via clarifying questions)

- Slot model: upgrade **level = number of placeable deflectors**; placement free.
- Edge pegs: non-issue — triangular Galton lattice always offers a valid L & R.
- Interaction: **direct hover/click** (no configure mode). Click a placed
  deflector to remove; change direction = remove + re-place.
- Unlock: **Deflector is the orange board's slot-4 special**; **Advanced
  Autodropper moves to the red board's slot-4**.
- Offline: **ignore** — `OfflineCalculator` keeps the uniform binomial model;
  deflectors are active-play-only (surfaced in the upgrade hover text).
- Discoverability: **full first-time intro animation**, mirroring
  `AutodropperIntroAnimator`.
- Challenge mode: editor + intro suppressed; purchase blocked by `upgrade_gate`.

## Round 1 — concerns (summary per personality)

- **Janitor (blocking):** the proposed `peg_index_at` float→peg arithmetic
  duplicates `flash_nearest_peg`'s mapping (drift trap); don't fatten the
  1780-line `plinko_board.gd` — editor must be its own scene; pick ONE 3D-pick
  path.
- **Godot Guru (blocking):** float→peg inversion is wrong at `_bounce_or_despawn`
  callback time (spawn +0.2 offset + bounce noise; not snapped to a peg row);
  hot-path must fast-path the empty case; `_unhandled_input` raycast endorsed
  over per-peg Area3D; paddles must reconcile across `build_board()`; reuse the
  board's `_cached_camera`.
- **Architect (blocking):** enum addition is load-bearing on the `.tres`;
  prestige reset must clear deflectors via the boards-blob path; slot surfacing
  on level-up unspecified; offline economy divergence; input-lock chokepoint
  doesn't reach a board-child `_input`; challenge-mode policy unresolved.
- **Newcomer (blocking):** no `±1` left/right convention exists; triangular index
  formula is a magic formula; buying a "does-nothing" upgrade contradicts every
  instant-effect upgrade (needs onboarding); click-flow state machine
  underspecified.
- **Consistency Lover (blocking):** signal wiring must be named `_on_*` refs not
  lambdas; `_exit_tree` guarded disconnects; pin exact theme color fields
  (paddle→`peg_color`, ghost→`overlay_color`, arrows→`normal_text_color`);
  `.tres` must match the exact `add_row.tres` field format; keep explicit `int`
  typing (don't copy `coin.gd:152`'s untyped var).
- **Test Lead (blocking):** make the deflector's *trajectory* effect testable
  (not just direction); restore must be a pure method that doesn't reach
  `build_board()`; decide enum-vs-counter; cover prestige clearing + old-save
  migration.

## Round 2 — resolution of the two real conflicts

**Conflict A — peg lookup.** RESOLVED by consensus: the Coin carries its integer
`(row, col)` lattice cell and advances it deterministically each bounce.
PlinkoBoard owns the single canonical lattice math (`position_x_for`,
`peg_index`, `cell_to_world`, `next_lattice_cell`, `is_terminal_cell`,
`predicted_bucket_index`, `resolve_bounce_direction`) — `build_board()` itself
calls `position_x_for`, so build and gameplay can't drift. No float→peg inverse
is written at all. `flash_nearest_peg` stays unchanged (intentionally a
mid-bounce nearest-search — different question), with a clarifying comment.
Test Lead's trajectory requirement satisfied: all methods are pure and a seeded
descent is unit-tested (`test_deflector_trajectory.gd`).

**Conflict B — enum membership.** RESOLVED: `PEG_DEFLECTOR` IS an
`Enums.UpgradeType` member. Test Lead withdrew the standalone-counter
recommendation; a counter would duplicate six subsystems (state, cost, UI row,
save, unlock, challenge hooks) with no precedent. Mitigation: mandatory `.tres`
+ `upgrade_manager.tscn` registration (what makes `_init_state` create the
entry), explicit `_buy_upgrade` arm, and targeted regression tests on the
`Enums.UpgradeType.values()` consumers (`test_upgrade_manager_deflector.gd`,
extended `test_ensure_unlocks.gd`). No `SAVE_VERSION` bump — graceful
`.get(key, default)` and `not in`-guarded deserialize loops.

## Consensus advisories folded into the implementation

Named `Enums.Direction { LEFT=-1, RIGHT=1 }` + `coin.gd` refactored onto it;
single `deflector_change_requested(peg_index, dir)` signal (dir 0 = remove);
named `_on_*` connections + `_exit_tree` guarded disconnects; pinned theme
colors; pooled paddle `MeshInstance3D`s; `_deflectors.is_empty()` hot-path
fast-path; input-lock routed through `Main.apply_input_lock` + per-board
`set_deflector_input_active` on `board_switched`; explicit click-flow state
machine; deflectors restored as the final, pure step of `apply_saved_state`.

## Post-plan revisions (user feedback after first implementation)

1. **Deflector is a UNIVERSAL upgrade** (all per-board "unique" upgrades are).
   It renders in the `CoinValues` HUD "Universal upgrades" section (left),
   not the per-board `UpgradeSection` (`_is_universal_upgrade` now includes it).
2. **Hover tooltip = cost only** — the explanatory description was reverted.
3. **Global slot pool**: buying deflectors lets you place on ANY peg of ANY
   board. Cap stored under the canonical board (`PlinkoBoard.DEFLECTOR_BOARD =
   ORANGE`); enforced against the total placed across all boards via
   `BoardManager.get_total_deflectors` injected as `PlinkoBoard.deflector_total_query`.
4. **Interaction simplified** — no click-then-pick popup. Hovering an empty peg
   shows a small translucent arrow on the side of the peg the cursor is on;
   clicking places that side. Hovering a placed deflector shows an **X** above
   it (click removes). `ClickAction.OPEN_ARROWS` → `PLACE`.

## Outcome

Implemented on `feature/deflector-upgrade`. Full headless test suite green
(16 suites, incl. new `test_deflector`, `test_deflector_trajectory`,
`test_upgrade_manager_deflector`, extended `test_ensure_unlocks`); project
imports with zero parse errors.
