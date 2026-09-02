# Earrings — Feature Spec

**Status:** decisions locked with the user 2026-09-01. Planning pass pending.
**Worktree:** `.claude/worktrees/earrings/` on branch `feature/earrings`.
**Base:** cut from `chore/test-safety-net` (f8b78f2), NOT `main` — that commit carries the
stricter `test/run_all.sh`. `main` is an ancestor of it, so landing still fast-forwards.

---

## Goal

Once a board is large enough, further "add rows" purchases stop growing the main triangle and
instead grow two triangular sub-boards ("earrings") hanging beneath the two edge buckets.
When the earrings grow large enough that their inner edges MEET at dead center, that meeting
point becomes a **transporter** bucket that sends coins to the space board.

The shape is the classic subdivided triangle: main board on top, two earrings below it, and
an empty inverted triangle between them.

```
              /\              <- main board, frozen at 8 rows / 9 buckets
             /  \
            /____\            <- its bucket row; edge buckets at -4s and +4s
           /\    /\
          /  \  /  \          <- the two earrings, growing down and inward
         /____\/____\
               ^
          TRANSPORTER at x = 0
```

## Locked decisions (from the user — do not relitigate)

1. **Trigger:** the main board caps at **9 buckets (8 rows)**. Every `ADD_ROW` purchase after
   that grows the earrings instead of the main triangle.
2. **Growth: 2 rows per purchase.** Both earrings always grow symmetrically and identically.
   `num_rows` starts at 2 (3 buckets) and each purchase adds 2 rows, so the full table is:

   | ADD_ROW level | cost | main rows | buckets | earring rows | note |
   |---|---|---|---|---|---|
   | 0 | — | 2 | 3 | 0 | start |
   | 1 | 6 | 4 | 5 | 0 | |
   | 2 | 60 | 6 | 7 | 0 | **base cap — `max_level = 2`** |
   | 3 | 600 | 8 | 9 | 0 | needs a cap raise; **main board caps here** |
   | 4 | ↑ | 8 | 9 | 2 | inner edge at -3s / +3s |
   | 5 | ↑ | 8 | 9 | 4 | inner edge at -2s / +2s |
   | 6 | ↑ | 8 | 9 | 6 | inner edge at -1s / +1s |
   | 7 | ↑ | 8 | 9 | 8 | **0 — they meet.** Hard cap; ADD_ROW disabled |

3. **`add_row.tres` `max_level` changes 6 → 2.** The base game tops out at 7 buckets; going
   further requires cap raises, which cost higher-tier currency. `buy_cap_raise` does
   `current_cap += 1` (`upgrade_manager.gd:200`), so reaching the level-7 hard cap takes
   **5 cap raises** from the base cap of 2.
4. **The GREEN board can never grow earrings — this is accepted and deliberate.**
   `TierRegistry.cap_raise_currency` returns `-1` for the last tier
   (`tier_registry.gd:92-94`), so green cannot raise ADD_ROW past the base cap of 2 and stops
   at 7 buckets. The user's call, verbatim: *"It's okay that green can't get it. Green will
   be tweaked later."* Do NOT invent a workaround. **Consequence to state plainly in the
   handoff:** with green unable to reach a transporter, the space board's two green buckets
   cannot be activated in normal play, so the win condition is currently unreachable except
   via the space board's dev hotkeys. That is expected at this stage.
5. **Existing saves change and that is accepted.** A save at ADD_ROW level 6 currently loads
   as a 14-row board; afterwards it loads as 8 main rows + 6 earring rows. Add a test
   asserting the new load behavior so it is deliberate rather than a surprise.
6. **Camera: full fit, plus a zoom toggle.** `get_bounds()` grows to include the earrings and
   the camera frames the whole structure. Additionally revive an earring/main zoom toggle in
   the spirit of the prototype's `KEY_E` `toggle_earring_zoom()`.
7. **The main board's two edge buckets become pure gateways.** They stop paying currency
   entirely. A coin reaching bucket index `0` or `num_buckets - 1` falls straight through into
   the earring below and pays out down there instead.
8. **The transporter is a single shared bucket** at board-local `x = 0`, owned by
   `PlinkoBoard` (not by either `EarringBoard`). Both earrings route coins landing at that
   lattice position into it. It pays **no** currency — its entire reward is sending the coin
   to space. It should read as visually distinct from a normal bucket.
9. **Earring bucket payout:** the **same currency as the parent board** (there is no new
   premium currency — that prototype idea is dropped), and **every earring bucket has
   value 1** for now. Deliberately unbalanced; this is a first pass.
10. **The `ADD_ROW` upgrade is disabled once the earrings meet.** Hard cap, not a soft one.
11. **The space-board connection can be left unwired.** Emit the seam signal and stop; the
   space board is being built in parallel on another branch.

## Decisions I made (flag during review if you disagree)

- **All six boards can grow earrings.** Each board's transporter sends a coin of that board's
  own currency color. That is how all six colors reach the space board.
- **Earrings are a per-board growth mode, and challenges author it.** See "Growth mode"
  below — this replaces the earlier "assert earrings are impossible in challenges" approach.
- **Earrings are excluded from** deflectors, bomb/forbidden hazards, the wandering gameplay
  target, and voided columns. Keep the surface small.
- **No save changes.** Earring size is a pure function of the persisted `ADD_ROW` upgrade
  level — derive it, do not store it. The parallel space-board branch owns the
  `SAVE_VERSION` 6 → 7 bump; this branch must not touch `save_manager.gd`.
- **No `VisualTheme` changes.** Keep earring tunables as local `const`s in the earring script.
  This avoids a guaranteed conflict with the space-board branch, which appends a theme group.

## Growth mode — normal play vs challenges (locked with the user)

**The six main boards ALWAYS grow earrings.** There is no per-tier configuration and no
`TierData` change. Normal play is exactly the table above: main caps at 8 rows / 9 buckets,
then earrings.

**Challenge boards are different, and it is authored per challenge.** Add one field to
`ChallengeData` (`autoloads/challenge_manager/challenge_data.gd`), alongside `objectives`,
`constraints`, `starting_conditions`, `hazards`, `rewards` and `failure_hint`:

```gdscript
@export var grows_earrings: bool = false
```

Semantics:
- `false` (the default, and what every existing `.tres` gets with no edit): the board is
  **uncapped** — `ADD_ROW` / `add_two_rows` grow the main triangle indefinitely, exactly as
  today — and it **never** sprouts earrings. This is the "real, real big board" case.
- `true`: the board behaves like a normal-play board (caps at 8 rows, then earrings).

**CRITICAL — this is why the cap must be conditional.** `StartingBoards` grows challenge
boards by looping `add_two_rows(false)` (`challenge_manager.gd:143-151`) to reach an authored
size. If `main_rows_for_level` capped at 8 rows unconditionally, **no challenge could author a
board bigger than 9 buckets** — a silent regression against existing challenge data. The cap
and the earrings diversion apply only when earrings are enabled for that board.

Implementation shape:
- `PlinkoBoard` gets an `earrings_enabled: bool` property, set in `setup()`: `true` in normal
  play; in challenge mode, from the active `ChallengeData.grows_earrings`.
- The `EarringGeometry` statics take it as a parameter rather than reading any autoload, e.g.
  `main_rows_for_level(add_row_level: int, earrings_enabled: bool) -> int` and
  `earring_rows_for_level(add_row_level: int, earrings_enabled: bool) -> int`. When
  `earrings_enabled` is false, `main_rows_for_level` is the uncapped `2 + level * 2` and
  `earring_rows_for_level` is always `0`.
- The level-7 **hard cap on `ADD_ROW` applies only when `earrings_enabled`** is true.
  Uncapped boards keep today's `max_level` + cap-raise behavior with no ceiling.
- No sanity ceiling on uncapped boards: challenges author exact sizes, so there is no runaway
  player-driven growth to guard against.

**This supersedes the earlier "earrings must be structurally impossible in challenges"
blocker.** An explicit, authored growth mode is a better mechanism than a `push_error` assert,
and it removes the need for one. The `force_apply` bypass concern is also moot for this
purpose: a challenge board with `grows_earrings = false` cannot divert to earrings no matter
what level `StartingUpgrades` forces.

## The `CoinSurface` refactor — do this properly

The prototype duck-typed the board interface and un-typed `Coin.board` to make it work. The
handoff doc (`agent-logs/prototype-earrings-handoff.md`, §"What to do differently") calls this
out as the #1 thing to fix. Do it:

- Add `scripts/coin_surface.gd`: `class_name CoinSurface extends Node3D`, declaring the full
  contract `Coin` actually consumes, with `push_error` default bodies.
- Change `PlinkoBoard` to `extends CoinSurface`. Because `CoinSurface extends Node3D` and
  `plinko_board.tscn`'s root is a `Node3D`, this is scene-compatible — verify by opening the
  scene, but it should not require a `.tscn` edit.
- `EarringBoard extends CoinSurface` too.
- Type `Coin.board` as `CoinSurface` (it is currently `: PlinkoBoard`; the prototype had to
  strip the type). This restores type safety instead of losing it.

**The exact surface `Coin` consumes** (from `coin.gd:173-210`, `:246`, `:251`):
`is_terminal_cell(row, col) -> bool`, `flash_nearest_peg(...)`,
`resolve_bounce_direction(row, col, roll) -> int`, `notify_deflector_resolved(row, col, dir)`,
`next_lattice_cell(row, col, dir) -> Vector2i`, `is_lattice_cell_voided(row, col) -> bool`,
`cell_to_world(row, col) -> Vector3`, `predicted_bucket_index(row, col) -> int`,
`get_bucket(index) -> Bucket`, plus the fields `num_rows: int` and `space_between_pegs: float`.

`EarringBoard` supplies: plain 50/50 `resolve_bounce_direction`, `is_lattice_cell_voided`
always `false`, and no-op `flash_nearest_peg` / `notify_deflector_resolved`.

## Seam with the space board — implement EXACTLY this

Add to `plinko_board.gd`:
```gdscript
signal coin_transported(board_type: Enums.BoardType, currency_type: Enums.CurrencyType, world_pos: Vector3)
```
`world_pos` is a **global** position. Emit it when a coin lands in the transporter bucket,
**before** `coin.queue_free()`, then despawn the coin as normal. **Nothing
listens to it on this branch — that is correct and expected.** The space-board branch adds a
listener guarded by `has_signal("coin_transported")`, so it works before and after the merge.
Do not add a `SpaceBoard` reference, autoload, or stub of any kind.

## Technical findings (already scouted — trust these)

- **`prototype/earrings` (tip `9f6f9d5`) is reference only, not code to copy.** Its
  `entities/earring_board/earring_board.gd` (166 lines) is a working sketch; the handoff doc
  is explicit that the implementation is a mess. Read both, then write clean.
- `scripts/lattice.gd` is the shared pure geometry module and **must** be reused (it is the
  single source of truth that keeps `PlinkoBoard`, `Coin` and `MenuBoard` from drifting):
  - `vertical_spacing(space) -> space * sqrt(3)/2`
  - `x_for(row, col, space) -> -row * space / 2.0 + col * space`
  - `cell_to_world(row, col, space, vert_spacing, row_y_offset) -> Vector3`
  - `next_cell(row, col, direction) -> Vector2i` (RIGHT → `col+1`, LEFT → `col`)
- Geometry that makes this work, with `s = space_between_pegs`: `build_board()` sets
  `bucket_x_offset = -s * (num_buckets - 1) / 2`, so a 9-bucket board has its edge buckets at
  `-4s` and `+4s`. An earring apexed at `-4s` with `R` rows has its bottom row spanning
  `-4s ± R*s/2`, which reaches `x = 0` exactly at `R = 8`. The left earring's innermost bottom
  cell is `col = R`; the right earring's is `col = 0`. **Derive these from `Lattice`; do not
  hardcode `-4s` or `8`.**
- **The single-currency refactor already landed.** `_is_advanced_at_distance()`
  (`plinko_board.gd:2220`) is a stub returning `false`; every bucket pays
  `TierRegistry.primary_currency(board_type)`. `ORANGE_ROW_GATE` / `RED_ROW_GATE` no longer
  exist (CLAUDE.md lines 428-430 are stale). Your "same currency as the parent board"
  requirement is therefore the default path — do NOT resurrect the advanced-bucket logic.
- Extension seams: `build_board()` tail (`plinko_board.gd:2068`, just before the voided-peg
  re-apply — this is where the prototype rebuilt earrings), `on_coin_landed` (`:972`, intercept
  before `finalize_coin_landing`), and `get_bounds()` (`:2175`, camera fit — earrings must be
  included so the camera frames them).
- `add_two_rows(animated := true)` (`:2185`) is the growth entry point. Callers:
  `upgrade_section.gd:182` (animated), `challenge_manager.gd:151` (`false`), `main.gd:365`
  (KEY_7 preview). The row-upgrade glissando is main-board choreography — decide deliberately
  whether earring growth gets its own animation or none, rather than letting it fire by accident.
- **`ADD_ROW` hard cap:** `max_level` comes from `BaseUpgradeData` and can be RAISED by the
  cap-raise system. A soft `max_level` is therefore not enough — the cap must hold even after
  cap raises. Find every place ADD_ROW purchasability is computed and gate it there.
- **Before changing any `coin_landed` behavior, enumerate every consumer** (`ChallengeTracker`,
  `BoardManager`, analytics, and anything else — grep for it). Then decide whether earring
  landings emit `coin_landed` at all. Default recommendation: they do NOT (bucket indices would
  collide with main-board indices and challenge objectives index by bucket); credit currency
  and play audio directly instead. Justify whichever way you go in the commit message.

## File ownership (conflict control — the space-board branch runs in parallel)

**This task owns and may freely edit:**
`entities/earring_board/**`, `scripts/coin_surface.gd`, `entities/coin/coin.gd`,
`entities/plinko_board/plinko_board.gd`, `entities/plinko_board/upgrade_section.gd`,
`autoloads/upgrade_manager/upgrade_manager.gd`, `autoloads/upgrade_manager/data/add_row.tres`,
`scripts/earring_geometry.gd`.

**Do NOT touch** (the space-board branch owns these):
`autoloads/save_manager/save_manager.gd`, `style_lab/visual_theme.gd`, `scripts/vfx_utils.gd`,
`entities/prestige_vfx/shockwave.gdshader`, `entities/space_board/**`, `entities/main/main.tscn`.
Avoid `entities/main/main.gd` entirely if you can; if you truly cannot, keep the edit to a
few lines and say so in the handoff.

## Out of scope

- Any space board work, or any reference to it beyond emitting `coin_transported`.
- Balancing earring bucket values (all 1 by instruction).
- A new currency. `PREMIUM_GOLD` from the prototype is explicitly dropped.
- Earrings in challenge mode.

## Test expectations (per CLAUDE.md — tests are a commit-time concern)

Do NOT write tests during iteration. When ready to ship, add `test/test_earrings.gd` + `.tscn`
extending `test_base.gd`, covering the pure geometry and gating logic:
- earring apex x equals the edge bucket x, derived from `Lattice`, for several board sizes
- an `R`-row earring's innermost bottom-cell world x, and that it equals exactly `0` at `R = 8`
  on a 9-bucket board (and is strictly inside for `R < 8`)
- the growth table: `ADD_ROW` level → main rows (capped at 8) and earring rows (0,2,4,6,8)
- the transporter exists only when the earrings meet, and pays no currency
- edge buckets pay nothing once earrings exist, and pay normally before that
- `ADD_ROW` is not purchasable once the earrings meet, **including after a cap raise**
- `CoinSurface` conformance: both `PlinkoBoard` and `EarringBoard` implement every method
  `Coin` calls

**Worktree gotcha:** a fresh worktree has no Godot global class cache, so a new
`class_name` (`CoinSurface`, `EarringBoard`) will not resolve in headless test runs until you
rebuild it:
`/Applications/Godot.app/Contents/MacOS/Godot --editor --quit --audio-driver Dummy --path <worktree>`
Run that once before `bash test/run_all.sh`.

---

# Planning Pass — Round 1 Findings

Three personalities reviewed this spec: **Godot Guru**, **Architect**, **Test Lead**.
Everything below is resolved and binding. BLOCKING items must be handled during
implementation, not deferred.

## BLOCKING — extract the geometry to a pure static module FIRST

There are already **two** places that compute board size and they agree only by luck:
`plinko_board.gd:2778` (`num_rows = 2 + add_row_level * 2`, the save/reload path) and
`plinko_board.gd:2191` (`num_rows += 2`, the runtime path). Adding a cap creates two places
to cap — the classic drift bug, and only one of them is exercised by a save/load test.

Create `scripts/earring_geometry.gd` (`class_name EarringGeometry`, pure static, shaped like
`Lattice` / `OfflineCalculator`) as the single source of truth. NOT methods on the 2807-line
`plinko_board.gd`: statics cost nothing per test case (a `PlinkoBoard.new()` costs a `Node3D`
+ `free()`, `test_deflector_trajectory.gd:23-29`), `EarringBoard` needs the same math without
reaching into `PlinkoBoard`, and statics cannot accidentally touch `peg_field` (null-in-tests)
or autoloads.

Required signatures — all `static`, all scalar in / scalar out:
- `main_rows_for_level(add_row_level: int) -> int` — replaces BOTH `:2778` and `:2191`
- `earring_rows_for_level(add_row_level: int) -> int`
- `max_add_row_level() -> int` — the hard cap; the single number every gate reads
- `edge_bucket_x(num_buckets: int, space: float) -> float` — derived from the same
  `-s*(num_buckets-1)/2` as `plinko_board.gd:2104-2106`, never a literal `-4s`
- `innermost_bottom_x(apex_x: float, earring_rows: int, space: float) -> float` — via `Lattice.x_for`
- `earrings_meet(earring_rows: int, num_buckets: int) -> bool`
- `is_gateway_bucket(index: int, num_buckets: int, earring_rows: int) -> bool`
- `has_transporter(add_row_level: int, num_buckets: int) -> bool`
- `is_transporter_cell(row: int, col: int, earring_rows: int, side: int) -> bool`

**Float trap:** `earrings_meet` must be `is_zero_approx(innermost_bottom_x(...))` — never
`== 0.0`, and never `rows == 8` (which hardcodes what the geometry should derive). Tests
assert with `assert_near(..., 1e-5)`.

## BLOCKING — the ADD_ROW cap has three bypasses

`UpgradeManager.can_buy` (`upgrade_manager.gd:114-127`) is the real gate — `buy` (`:130`) and
`upgrade_row.gd:161` both route through it. But:
1. **`force_apply` (`:146`)** has no cap check at all, and is used by `StartingUpgrades`
   (`challenge_manager.gd:139-141`) and by prestige rewards.
2. **`can_buy_cap_raise` (`:180`)** checks `base_cap`, never the level cap. Past the hard cap
   the "+" stays enabled and the player spends higher-tier currency raising a dead cap —
   a **wasted-spend soft-lock**.
3. **`upgrade_row.gd:135`** derives `at_max` from `current_cap` alone, so the button reads
   non-Max and filled while `can_buy` returns false — a UI/logic mismatch.

**Resolution:** fold the hard cap into `get_max_level()` / `current_cap` so all four call
sites inherit it from one place, and test `get_max_level` directly. Do NOT use
`UpgradeManager.upgrade_gate` — it is single-slot and already used by `ChallengeManager`
(`:83`); an earrings gate would clobber the challenge gate.

## BLOCKING — do NOT reparent the coin at handoff

`CoinPool.update` reads `coin.position` (local) and writes into a MultiMesh parented to the
board (`plinko_board.gd:2088`). Reparenting a coin to an earring renders every coin in the
wrong place unless it is re-acquired into an earring-owned pool. **Keep the coin a child of
`PlinkoBoard`** — that also keeps the `tree_exiting` → `_coin_pool.release` hookup (`:712`,
`:627`) working for free. `EarringBoard.cell_to_world` therefore correctly returns
PlinkoBoard-local coords; compute it as `transform * Lattice.cell_to_world(...)`, NOT
`position + …`, so it survives a non-identity basis or an `Earrings` wrapper node.

At handoff: disconnect **both** `landed` AND `final_bounce_started` (`:713-714`) — otherwise
`_on_final_bounce_started` runs `_will_trigger_prestige_completion` against an earring bucket.
And call `coin.kill_tweens()` before `coin.start()`: `_active_tweens` (`coin.gd:28`) is
append-only and cleared only there.

## BLOCKING — the transporter bucket has two collisions

1. **Never parent it to `buckets_container`.** `build_board()` (`:2074-2077`) frees every child
   of that container, and `predicted_bucket_index` (`:1833`) / `num_buckets = get_child_count()`
   (`:997`) assume col ↔ child-index 1:1. Parent it to a NEW `Transporter` node.
2. **It sits at board-local x = 0 — exactly the main board's center bucket x** on a 9-bucket
   board. `get_nearest_bucket` (`:2044`) matches on x alone within 0.5, and
   `_bucket_position_key` (`_singing_positions`) is x-keyed. Both collide.
   **Therefore earring landings must NOT route through `on_coin_landed` / `get_nearest_bucket`** —
   resolve via `get_bucket(predicted_bucket_index(...))` in the earring's own handler.
   One shared `Bucket` returned by both earrings' `get_bucket` is fine (it is a reference).

## BLOCKING — the growth animation latches the camera forever

If `row_upgrade_starting` (`:2199`) is emitted without a following `row_upgrade_sweep_started`,
`BoardManager._row_upgrade_camera_active` is set (`board_manager.gd:257`) and is only cleared
by the sweep's final `tween_callback` (`:340`). It latches `true` forever and
`_on_board_rebuilt` (`:244`) never fits the camera again.

**Resolution:** branch out of `add_two_rows` **before** `_shift_voided_columns(1)` and before
`num_rows += 2` (both wrong for earring growth) into a separate `_grow_earrings()` that just
rebuilds and lets `board_rebuilt`'s fit-tween re-frame. Also check `main.gd:365`
`_preview_add_rows` (KEY_7) — it reverts by decrementing `num_rows`, which would corrupt
earring state. **Ownership note:** that KEY_7 fix is assigned to THIS branch; keep the edit to
those few lines and flag it in the handoff, since `main.gd` is shared with the space board.

## BLOCKING — retyping `Coin.board` breaks four files outside this spec's ownership

`Coin.board: CoinSurface` turns these into static errors, not warnings:
- `entities/prestige_animator/prestige_animator.gd:57` (`coin.board.eject_coin_from_multimesh`),
  `:77` (`coin.board.board_type`), `:84`
- `entities/main/forbidden_bucket_reveal_animator.gd:60` — `var board: PlinkoBoard = coin.board`
  (narrowing; needs `as PlinkoBoard`)
- `entities/main/cap_raise_reveal_animator.gd:86` — same
- `entities/main/main.gd:346` — widening, fine

**Resolution:** add `board_type` and `eject_coin_from_multimesh` to the `CoinSurface` contract,
and use `as PlinkoBoard` at the two narrowing sites. Ownership of those two animator files is
hereby granted to this branch for that one-line change each.

## BLOCKING — edge buckets that stop paying still trigger cinematics

`_predicted_bucket_gain` (`:1057-1064`) and `_coin_completes_board` still count the gateway
bucket's value, so `_on_final_bounce_started` (`:1036-1053`) can fire `prestige_coin_landed`,
`cap_raise_coin_landed` and `next_board_unlock_requested` for a coin that credits **0** — a
full cinematic for currency that never arrives. Gate the gateway indices to 0 there too.

## RESOLVED — challenge earrings are now an authored growth mode

This was originally a BLOCKING item ("earrings must be structurally impossible in
challenges", enforced by a `push_error` assert). The user's `ChallengeData.grows_earrings`
decision supersedes it — see "Growth mode" above. `ChallengeManager.is_upgrade_allowed`
(`:189`) permitting ADD_ROW mid-challenge and `StartingBoards` looping `add_two_rows(false)`
(`:143-151`) are both now harmless: a board with `grows_earrings = false` is uncapped and
never diverts, whatever level is forced. **Still verify** that existing authored challenge
data (which tops out at `rows = 6` today) is unaffected by the conditional cap.

## ADVISORY — resolved decisions

- **`coin_landed`: do not emit for earring or transporter landings. Confirmed safe.** It has
  exactly ONE runtime listener — `ChallengeTracker` (`challenge_tracker.gd:117-119`,
  disconnected `:500`), which fans out to hazard runtimes. `BoardManager` does NOT listen
  (`board_manager.gd:167-171`) and neither does `AnalyticsManager` (`analytics_manager.gd:102`
  listens to `upgrade_purchased` only). **`CLAUDE.md:408` is stale on this** — fix it at the
  step-7 doc update. Nothing under-reports: level-ups, cap-raise availability and offline
  accrual all ride `CurrencyManager.currency_changed`. Audio must be called explicitly
  (`plinko_board.gd:1010-1014`).
- **But do not hardcode the autoloads.** "Credit currency and play audio directly" makes the
  landing path untestable headlessly. Route it through the existing `finalize_coin_landing`
  shape or an injected `credit_fn: Callable` (PeekAnimator / DeflectorModel precedent) so a
  test can assert the credited amount without autoload state.
- **Use `@abstract func` on `CoinSurface`, not `push_error` bodies.** Godot 4.5+ supports it;
  it gives compile-time "PlinkoBoard doesn't implement X" instead of a runtime `push_error`
  nobody sees. Keep `PlinkoBoard` / `EarringBoard` concrete (an `@abstract` class cannot be
  `.new()`'d). Confirmed safe: `plinko_board.tscn:8` is `[node name="PlinkoBoard" type="Node3D"]`,
  and since `CoinSurface extends Node3D` the stored root type stays valid — **no `.tscn` edit
  needed**. No `class_name` cycle risk, but do NOT `preload()` `earring_board.tscn` from
  `plinko_board.gd` if `earring_board.gd` preloads anything reaching back — `class_name` typing
  is cycle-safe, `preload` is not.
- **One `PegField` per earring**, not growing the board's single field. Growing it is worse:
  `PegField.build()` (`peg_field.gd:54`) drops all in-flight flashes, so every earring purchase
  would blank the main board's peg VFX; `flash_nearest_peg` (`:2578`) does an unscoped
  `nearest_to`, so a main-board coin could light an earring peg; and `peg_index()` (`:1367`) is
  the deflector/void/glissando key, which must stay main-board-only. Cost is +2 draw calls, and
  `_process` is `set_process(false)`-gated when idle (`:28,36`), so idle earrings cost zero.
  Mirror the documented invariant: `peg_field` is null in a bare `EarringBoard.new()` — guard
  every call site.
- **`_pick_new_gameplay_target` (`:1238-1240`)** allows indices `0` / `n-1`, which would put the
  golden target on an unpayable gateway bucket. Exclude gateways.
- **`offline_calculator.gd:206-223`** builds its layout from `num_rows` and gives the EDGES the
  highest value (`1 + 4*mult`). It will over-credit gateways and ignore earrings entirely.
  Capping `num_rows` at 8 also silently caps offline earnings. Accept and test it, or fix it —
  but do not leave it unnoticed.
- **`get_bounds()`**: width is unchanged (the earring bottom spans ±4s, inside the existing
  `half_width = 4s + 0.5`), but height nearly doubles. Per the user's decision this is a FULL
  fit plus a zoom toggle. `test_plinko_board.gd:154` calls `get_bounds()` on a bare board, so
  the earring path must be null-safe.

## Regression watch-list — re-run and verify, do not just "make them pass"

- `test_deflector_trajectory.gd` — depends on `deflector_model.gd:93` bit-identity. Require
  **identical** bucket numbers (0, 6, 1, 5), not merely a green suite.
- `test_plinko_board.gd:154` `test_get_bounds_geometry` — **will break** when `get_bounds()`
  includes earrings. Update it deliberately.
- `test_plinko_board.gd:607` `test_shift_voided_columns_handles_add_rows` — `add_two_rows`
  calls `_shift_voided_columns(1)` unconditionally. Once rows cap, bucket indices stop
  shifting, so that call must become conditional or every existing void walks off the board.
- `test_cap_raise_reveal.gd:325-385` uses ADD_ROW as its sample upgrade; a hard cap in
  `can_buy` changes its fixtures.

## Additional required test cases

- **growth-table boundaries**, not just the table: level at cap → 0 earring rows; cap+1 → 2;
  cap+4 → 8; cap+5 → still 8 (no overflow)
- **load-path parity**: `apply_saved_state({"ADD_ROW": L})` yields the same
  `(num_rows, earring_rows)` as L successive `add_two_rows(false)` calls, for L = 0..cap+6.
  This is the test that makes the "no save changes" claim real.
- **cap-raise refusal**: both `can_buy` AND `can_buy_cap_raise` refuse ADD_ROW at the hard cap
- **a coin entering an earring and landing**: drive the `EarringBoard` lattice with the
  `_simulate` loop from `test_deflector_trajectory.gd:33-44`; assert it terminates at a real
  bucket index for all-left, all-right and mixed rolls
- **transporter pays nothing**: `CurrencyManager` balance unchanged across a transporter
  landing, AND `coin_transported` fired exactly once with the parent board's currency
- **challenge mode**: a challenge board with `grows_earrings = false` has `earring_rows == 0`
  regardless of the persisted ADD_ROW level, AND is uncapped — assert it can reach well past
  9 buckets via repeated `add_two_rows(false)`, since that is what `StartingBoards` does
- **`grows_earrings = true`** on a challenge reproduces normal-play behavior (caps at 8 rows,
  then earrings)
- **existing challenge `.tres` files** are unaffected: `grows_earrings` defaults to `false`
  with no file edits, and every authored challenge board still builds to its authored size
- **the accepted save change**: a level-6 save loads as 8 main rows + 6 earring rows

## Worktree class-cache gotcha — two extra bites

The `--editor --quit --audio-driver Dummy` rebuild is correct and necessary, plus:
(a) it must run **after** `scripts/coin_surface.gd` and its `.uid` exist, and must be re-run
whenever a new `class_name` is added — not once at setup;
(b) `run_all.sh:50` fails any suite printing zero assertions, so an unresolved `class_name`
surfaces as the confusing "ran no assertions" rather than a clear parse error. When you see
that, check stderr for `Could not find type`.
