# Space Board — Feature Spec

**Status:** decisions locked with the user 2026-09-01. Planning pass pending.
**Worktree:** `.claude/worktrees/space-board/` on branch `feature/space-board`.
**Base:** cut from `chore/test-safety-net` (f8b78f2), NOT `main` — that commit carries the
stricter `test/run_all.sh` (gates on SCRIPT ERROR and on suites that assert nothing).
`main` is an ancestor of it, so `tools/land_worktree.sh` still fast-forwards.

---

## Goal

Build the space board for real. It was previously a trailer-only decorative prop. It becomes
the endgame: a large fixed-size board above the six color boards. Coins arrive from the six
color boards' transporter buckets (see the earrings feature). Landing a coin in the bucket
matching its own color activates that bucket. All 11 activated = the player wins.

## Locked decisions (from the user — do not relitigate)

1. **Start from the prototype.** Port `entities/space_board/space_board.gd` (+ `.tscn`) from
   branch `prototype/earrings` (tip `9f6f9d5`) as the skeleton.
   - KEEP: 10-row / 55-peg `MultiMesh`, the 11 real `Bucket` instances in the rainbow order,
     world transform (uniform scale 3.333 at `x=50, y=33`), and the slow-mo → freeze →
     coin-expand → shockwave → shake cinematic in `start_trailer_cinematic()`.
   - STRIP: `SpawnTimer` decorative coin spawning, `MAX_DECORATIVE_COINS`, the trailer staging
     inside `start_trailer_cinematic()`, and every `TrailerCamera` dependency. Do NOT port
     `entities/main/trailer_camera.gd`.
   - ADD: per-bucket activation state + save, the empty-circle underlay, real coin intake,
     win detection, the win overlay, dev hotkeys.
2. **Bucket layout is fixed and always this:**
   `green, blue, violet, red, orange, GOLD, orange, red, violet, blue, green`
   — 11 buckets, 10 rows. Gold is dead center and is the only color with a single bucket;
   the other five are mirrored. This already matches the prototype exactly.
3. **Navigation: a new up-target.** The player reaches it by navigating UP from the board row,
   mirroring how challenges sit below. Down / up-again returns.
4. **Coin arrival is a visible journey.** A coin launches upward out of a transporter bucket,
   arcs to the space board's apex peg, then falls the 10-row lattice picking left/right
   normally, and lands in one of the 11 buckets.
5. **Activation VFX** (this is the money shot — it will be filmed):
   coin lands in the bucket matching its own color →
   camera zooms up on the coin + slight slow-motion →
   the coin sinks until it overlaps the empty circle beneath the bucket →
   the circle fills →
   a bright **coin-colored** shockwave fires + camera zooms back out →
   the coin remains in the circle permanently, and the bucket goes from faded to full color.
6. **No currency, no rewards.** The space board never credits currency and never emits
   anything the economy listens to.
7. **Win state:** when all 11 are activated, show a dismissible full-screen "You win!"
   overlay. Dismissing returns to normal play with the board fully lit. No progression
   consequences; must be re-triggerable for filming.
8. **Odds stay honest.** Do not bias the lattice. Instead add editor-only dev hotkeys.

## Decisions I made (flag during review if you disagree)

- **Not a new `ModeManager` mode.** `ModeManager` is `MAIN | CHALLENGES` and is threaded
  through save, audio, challenge gating and nav. Adding a third mode is invasive and risks
  regressions far from this feature. Implement space viewing as a **camera destination** with
  a `_viewing_space` flag in `Main`, reusing the existing `BoardManager.begin_cinematic_camera()`
  / `end_cinematic_camera()` borrow (`board_manager.gd:371,378`) and `Main.apply_input_lock`.
  The planning pass should sanity-check this.
- **Space board owns its own coin animation.** The prototype already hand-rolls `_bounce_coin`
  on plain `MeshInstance3D`s. Keep that. It means this feature does **not** touch `coin.gd`,
  `plinko_board.gd`'s coin path, or the `CoinSurface` abstraction the earrings task owns —
  which is what keeps the two branches from colliding.
- **All six boards feed it** — each board's transporter sends a coin of that board's own
  currency color. That is how all six colors reach space.
  **IMPORTANT CAVEAT, decided by the user on the earrings side:** the GREEN board cannot
  currently grow earrings at all. `TierRegistry.cap_raise_currency` returns `-1` for the last
  tier (`tier_registry.gd:92-94`), so green can never raise its `ADD_ROW` cap far enough to
  make its earrings meet, and therefore never gets a transporter. The user's call, verbatim:
  *"It's okay that green can't get it. Green will be tweaked later."*
  **Consequence for this feature:** the two green buckets can never be activated in normal
  play, so **the win condition is currently unreachable except via the dev hotkeys.** That is
  expected and is NOT a bug to work around. Build the win detection correctly anyway; the dev
  hotkeys are what makes it filmable today, and green will be fixed later. Do not add a green
  special case, and do not reduce the space board to fewer than 11 buckets.
- **Persistence:** activated buckets + the won flag are saved. This task owns the
  `SaveManager.SAVE_VERSION` bump **7 → 8** and its migration. The earrings task must not
  touch save code (earring size is derived from the existing `ADD_ROW` upgrade level, which
  is already persisted).
  - **CORRECTED — verified against source.** `SAVE_VERSION` is **already 7**
    (`save_manager.gd:4`); a `if version < 7:` block already exists (`:314-328`, seeds
    `revealed_milestone_tiers`, covered by `test_save_migration.gd:98-121`). Writing a v7
    block would silently collide with it. Add `if version < 8:` — a no-op comment block is
    correct, since `data.get("space", {})` already defaults to zero activated + not won.
  - **`SaveManager` has no handle on the space board.** `setup()` is
    `setup(board_manager: BoardManager, should_autosave: bool)` (`save_manager.gd:14`) and
    `save_game` guards on `is_instance_valid(_board_manager)` (`:32`). A node in `main.tscn`
    is unreachable. Inject it — extend `setup()` to take the space board. Do NOT reach
    through `get_tree().current_scene`, and do NOT have the space board call into
    `SaveManager` (that would create the cycle).
  - **Serialize last.** Put `"space"` last in `save_game`'s dict and last in `load_game`'s
    deserialize chain, after `_board_manager.deserialize` (`:114`). The documented strict
    order exists because of read-dependencies during deserialize; the space board reads
    nothing and emits nothing the economy listens to, so it has no ordering constraint, and
    last keeps it out of the `check_and_rescue_gold_soft_lock` failsafe path (`:130`).
  - **Space state goes in `_persistent_progress_blocks()`** (`save_manager.gd:198`) alongside
    prestige/challenges/onboarding, so it SURVIVES a prestige reset. Rationale: the space
    board is the endgame — reached only after six boards, maxed `ADD_ROW`, and earrings
    meeting. `reset_game` fires on every prestige; wiping 11 buckets of endgame progress
    routinely would make the win unreachable in practice. `full_reset()` passes `{}`, so a
    true fresh start still correctly clears it.

## Seam with the earrings feature — implement EXACTLY this

The user explicitly said this connection point can be left unwired; these two branches are
built in parallel. Both briefs specify the identical seam so the merge is trivial:

- **Earrings task** adds to `plinko_board.gd`:
  `signal coin_transported(board_type: Enums.BoardType, currency_type: Enums.CurrencyType, world_pos: Vector3)`
  — `board_type` is included because `TierRegistry` only maps board → currency
  (`tier_registry.gd:77`); there is no reverse lookup, so without it the space board would
  have to scan all six board types or keep a private table that can drift from the tier chain.
  The emitter already knows it, so it is free.
  and emits it when a coin lands in the transporter bucket. Nothing listens to it there.
- **Space board task** adds:
  `SpaceBoard.receive_coin(currency_type: Enums.CurrencyType, from_world_pos: Vector3) -> void`
  and, in `Main`, a `_connect_space_board(board)` helper that connects the signal **defensively**:
  ```gdscript
  # MUST be the string-based API — see the warning below.
  if board.has_signal("coin_transported") \
          and not board.is_connected("coin_transported", _on_coin_transported):
      board.connect("coin_transported", _on_coin_transported)
  ```
  **CRITICAL — do not write `board.coin_transported.connect(...)`.** `board` is statically
  typed `PlinkoBoard` (`board_manager.gd:103` returns `Array[PlinkoBoard]`), and GDScript
  resolves member access on a typed value at **parse** time. Before the earrings branch lands,
  `PlinkoBoard` has no `coin_transported`, so `main.gd` would fail to parse and the entire
  scene would die — `has_signal()` is a runtime check and cannot rescue a parse error. The
  string-based form above is genuinely merge-safe and needs no edit after earrings lands.
  The `has_signal` guard means this compiles and runs correctly BEFORE the earrings branch
  lands and wires up automatically AFTER. Call it from both `Main._setup_normal()` and
  `Main._on_board_unlocked()` (the `PrestigeAnimator.connect_board` precedent, `main.gd:591`).
- Until earrings land, the only way to feed the space board is the dev hotkeys. That is
  expected and is not a bug.

## Technical findings (already scouted — trust these, re-verify only if something looks wrong)

- `Enums.BoardType { GOLD, ORANGE, RED, VIOLET, BLUE, GREEN }` — `scripts/enums.gd:3`. All six
  already exist. Do NOT add a space `BoardType`; the space board is not a `PlinkoBoard` and
  `BoardManager` must not know about it.
- Boards are laid out at `i * board_spacing` along +X with `board_spacing = 20.0`
  (`board_manager.gd:159`, `visual_theme.gd:211`), so the six span x=0..100 and **x=50 is the
  exact horizontal center** — which is why the prototype sits there.
- The prototype instances the board as a permanent child of `main.tscn` (`main.tscn:227`).
  Keep that; it is always in the scene, just off-camera at normal framing.
- **The coin-colored shockwave is a bigger change than it looks — verified against source.**
  `VfxUtils.spawn_shockwave(caller, uv_center, opts)` takes no color parameter
  (`scripts/vfx_utils.gd:17`), AND `entities/prestige_vfx/shockwave.gdshader` has **no color
  uniform at all** — its uniforms are `screen_texture`, `center`, `radius`, `ring_width`,
  `distortion_strength`, and it is pure screen-texture refraction with no tint path. So
  "coin-colored" means ADDING a tint contribution to the shader, not passing a color through.
  Do it additively with a default tint strength of `0.0` so existing callers are pixel-identical.
  The two callers to protect are `entities/prestige_vfx/prestige_vfx.gd:195` and
  `entities/level_section/level_section.gd:1116` (an earlier draft of this spec wrongly named
  the forbidden-bucket animator — it never calls it). Extract
  `static func _ring_params(opts: Dictionary) -> Dictionary` with no `SceneTree` dependency so
  a test can assert the default opts still yield the legacy parameter set at tint strength 0.
- **`CapRaiseRevealAnimator` (`entities/main/cap_raise_reveal_animator.gd`) is the template**,
  not `PrestigeAnimator`. It is the documented "borrows the camera and gives it back"
  precedent: `begin_cinematic_camera()` + `_camera_held`, direct `Engine.time_scale` set,
  `PROCESS_MODE_ALWAYS`, real-delta recovery via `delta / maxf(Engine.time_scale, 0.001)`,
  and an **idempotent `_teardown()`** guarded by `_torn_down` that runs on normal finish, on
  `prestige_phase_changed != NONE`, on `board_switched`, and on `_exit_tree`. Mirror all of
  that. `PrestigeAnimator` never zooms back out because it scene-swaps — wrong model here.
- `Bucket` (`entities/bucket/bucket.gd`) has **no** `mark_active`/`mark_inactive` (CLAUDE.md is
  stale). The real API is `mark_singing()` / `mark_stop_singing()`, `mark_hit()` / `mark_unhit()`,
  `mark_forbidden()`, `snap_invisible()` / `fade_in(d)`, `pulse*()`, `lift_for_fall` /
  `fall_to_rest`. Resting buckets are always the FADED color; `_resolve_default_color()`
  returns faded, and only singing pops to `get_bucket_color()` (full).
  **For an activated space bucket you need a new persistent full-color state** — do not
  reuse `mark_singing` (it self-times out after `SING_DURATION = 4.0`).
- `bucket.tscn` has exactly two children: `MeshInstance3D` + `BucketValue` (Label3D).
  `mark_forbidden()` adding a runtime `SkullIcon` Sprite3D child is the exact precedent for
  adding the empty-circle underlay. Note `_apply_color()` only touches `_base_material` and
  `_label`, so a new child needs its own color/alpha hook.
- The prototype hides the `BucketValue` label so the board reads as a clean palette. Keep that.
- `VisualTheme` (`style_lab/visual_theme.gd`): add tunables as a new `@export_group("Space Board VFX")`
  block **appended at the very end** of the file. Colors must come from the `Palette` enum
  (`visual_theme.gd:26`, **append-only** — indices are serialized as raw ints) resolved via
  `theme.resolve(...)`. New `@export`s with defaults need no `.tres` edits.

## Dev hotkeys (editor-only)

Follow the existing pattern in `entities/main/main.gd` `_input` (`main.gd:277-314`): every
hotkey gated behind `not demo_mode`, and `demo_mode` force-set to `true` in non-editor builds,
so these can never fire in an export. Add:
- send one space coin of a chosen color (cycle or number keys)
- activate the next unactivated bucket
- activate all → trigger the win overlay

Pick keys that do not collide with the existing `KEY_P`, `KEY_O`, `KEY_6`, `KEY_7`.

## File ownership (conflict control — the earrings branch runs in parallel)

**This task owns and may freely edit:**
`entities/space_board/**`, the win-overlay scene/script, `autoloads/save_manager/save_manager.gd`,
`scripts/vfx_utils.gd`, `entities/prestige_vfx/shockwave.gdshader`, `entities/main/main.tscn`.

**Shared — edit surgically, expect a small conflict:**
`entities/main/main.gd` (nav + space wiring + hotkeys), `style_lab/visual_theme.gd` (append at EOF).

**Do NOT touch** (the earrings branch owns these):
`entities/coin/coin.gd`, `entities/plinko_board/plinko_board.gd`, `entities/upgrade_section/**`,
`entities/earring_board/**`.

## Out of scope

- Actually wiring transporters (earrings task; the defensive `has_signal` connect is all that's needed).
- Any currency, upgrade, tier, level or challenge integration.
- Balancing the odds.
- Porting `TrailerCamera` or any other trailer hotkey (`KEY_1`–`KEY_5`, `KEY_V`).

## Test expectations (per CLAUDE.md — tests are a commit-time concern)

Do NOT write tests during iteration. When the work is ready to ship, add a
`test/test_space_board.gd` + `.tscn` pair extending `test_base.gd` covering the pure logic:
- the fixed 11-bucket color layout is exactly the specified rainbow, and is symmetric
- `currency_type == bucket color` activation matching: correct color activates, wrong color
  is a no-op, already-activated is a no-op
- win detection fires only when all 11 are activated, and fires exactly once
- save round-trip of activation state, and the v6 → v7 migration leaves an existing save with
  zero activated buckets and not-won
Run `bash test/run_all.sh` before declaring done — it fails a suite on any `SCRIPT ERROR`
even when assertions pass, and on any suite that asserts nothing.

---

# Planning Pass — Round 1 Findings

Three personalities reviewed this spec: **Godot Guru**, **Architect**, **Test Lead**.
Everything below is resolved and binding on the implementation. BLOCKING items must be
handled before or during implementation, not deferred.

## BLOCKING — camera ownership (Guru + Architect agree)

The camera borrow is the single riskiest part of this feature. Four separate problems:

1. **`begin/end_cinematic_camera` is a bool, not a counter** (`board_manager.gd:371-380`).
   `end_cinematic_camera()` clears the flag AND calls `_tween_camera_to_active_board()`.
   Viewing-space and the activation cinematic both want the borrow, so a nested `end()` yanks
   the camera back to the color board while the player is still parked in space.
   **Resolution:** `Main` takes ONE borrow for the entire space-viewing session; the
   activation VFX writes `_camera` directly because the borrow is already held. Do not nest.
2. **`switch_board()` is unguarded** (`board_manager.gd:119-137`) — it calls
   `_tween_camera_to_active_board()` unconditionally, unlike `_on_board_rebuilt` which does
   check `_cinematic_camera_active` (`:247`). Left/right arrows (`main.gd:670-682`) and the
   level-reward auto-switch (`:225`) would steal the camera out of space.
   **Resolution:** suppress lateral nav entirely while `_viewing_space` (this also fixes the
   nav-blink cue pointing at boards the player can't currently reach).
3. **Other camera owners fire while parked.** Autodroppers keep running on the color boards,
   so `CapRaiseRevealAnimator` (`:88-101`), `ForbiddenBucketRevealAnimator:70`,
   `PrestigeAnimator` (`:63-64,123`) and the `PrestigeVFX` shake (`prestige_vfx.gd:230`) can
   all grab the camera mid-space-view. Worst case: `PrestigeAnimator` snapshots
   `_original_camera_pos` (`:63`) — capturing a SPACE framing and restoring it on abort
   (`:223`), corrupting the color-board camera. **Resolution:** each needs a `_viewing_space`
   bail, symmetric with the existing prestige bail at `cap_raise_reveal_animator.gd:88`.
4. **Prestige while parked in space** returns nobody to the board. Covered by the teardown
   contract below.

## BLOCKING — `Bucket` activated state has a hole

Adding `_is_activated` and returning full colour from `_resolve_default_color()`
(`bucket.gd:315`) is the right approach — `setup:69`, `mark_unhit:82`, `unmark_bomb:288`,
`stop_gameplay_target:312` and `start_gameplay_target_fade:300` all funnel through it, and
`_apply_color:326` preserves alpha. **But `_stop_singing` bypasses it:** `bucket.gd:152`
hardcodes `ThemeProvider.theme.get_bucket_color_faded(currency_type)` and tweens
`_base_material.albedo_color` directly. An activated bucket that ever sings would tween back
to faded and stay there. Change `:152` to use `_resolve_default_color()`.

Do NOT reuse `mark_singing()` for activation — it self-times out after `SING_DURATION = 4.0`
and drives `Bucket._process` (`bucket.gd:37,124`), which should stay off.

## BLOCKING — the shockwave shader

- Use `opts.get("color", ...)` — `spawn_shockwave` already takes an `opts` Dictionary
  (`vfx_utils.gd:17`), so no new parameter and zero call-site churn.
- **Shader trap:** current output is pure distortion (`COLOR = texture(screen_texture, uv)`).
  A `uniform vec4 ring_color = vec4(1.0)` mixed at its default WOULD change appearance for
  both existing callers. Gate the tint on a separate `uniform float color_strength = 0.0`,
  and apply it INSIDE the `ring_dist < ring_width` branch scaled by `intensity` — otherwise
  the whole screen tints.
- **Timing trap:** `_spawn_single_ring` does `tween.set_speed_scale(1.0 / maxf(Engine.time_scale, 0.001))`,
  sampling `Engine.time_scale` ONCE at spawn. Our shockwave fires during slow-mo but
  `time_scale` is restored while the ring is still flying → wrong playback rate. Either fire
  the shockwave after restoring `time_scale`, or pass an explicit `duration`.
- `canvas.layer = 90` — the win overlay must sit above that.

## BLOCKING — port bug in the prototype's `_bounce_coin`

The prototype calls `create_tween()` on `self` (the SpaceBoard) and then
`tween_property(coin, ...)`. If teardown frees the coin, the tween outlives its target and
throws. `test/run_all.sh` now fails a suite on ANY `SCRIPT ERROR` even when every assertion
passes, so this is a hard failure, not cosmetic. Use `coin.create_tween()` so the tween dies
with its target. Audit the whole ported file for this pattern.

## BLOCKING — teardown contract

One idempotent `_teardown()` guarded by `_torn_down`, mirroring
`cap_raise_reveal_animator.gd:390-415`. It must fire on ALL of:
normal finish; `PrestigeManager.prestige_phase_changed != NONE`; `board_switched`;
`_exit_tree`; scene reload via `SceneManager`; the win-overlay dismiss; the player leaving
space mid-cinematic; and a second coin arriving mid-animation.

It must restore: `Engine.time_scale = 1.0`, the camera borrow, `camera.h_offset/v_offset`
(shake), the input lock, any in-flight coin `MeshInstance3D`s, and the bucket/underlay colour
state — **commit to activated, never leave a half-filled circle.**

**Concurrent arrivals need a QUEUE, not a drop.** Six boards can transport simultaneously.
`CapRaiseRevealAnimator` simply drops a second trigger; here you probably cannot, because a
dropped arrival is a lost activation. Queue them and play sequentially, with an `_is_animating`
re-entry guard.

## BLOCKING — testability seams (Test Lead)

Structure these at implementation time or the feature cannot be tested later. Activation
state must live in an `Array[bool]` on the board — **never on the 11 `Bucket` child nodes**,
which only exist after `_ready()` and so are absent on a bare instance.

- `const BUCKET_COLORS: Array[Enums.CurrencyType]` (11 entries) as a script-level const on
  `SpaceBoard`, NOT authored in the `.tscn`, so a bare `SpaceBoard.new()` can read it
- `static func matches(bucket_index: int, currency: Enums.CurrencyType) -> bool`
- `func try_activate(bucket_index, currency) -> bool` — the whole state machine; `true` only
  for match AND not-already-activated. Cinematic and save both hang off its return value
- `static func is_won(activated: Array[bool]) -> bool`, plus a `_won` latch so it fires once
- `static func fall_path(rng: RandomNumberGenerator, rows: int) -> int` — RNG-injectable
  (`coin_burst_field.gd:166` precedent). This is the ONLY way to test locked decision 8
  ("odds stay honest"): assert unbiased 50/50 and a result always within 0..10
- `static func arc_position_at(from: Vector3, apex: Vector3, t: float) -> Vector3` — analytic
  (`coin_burst_field.gd:175` precedent). Do NOT implement the arrival arc as a raw `Tween`;
  that makes it untestable
- `static func _ring_params(opts: Dictionary) -> Dictionary` in `VfxUtils`, no `SceneTree`
  dependency, so a test can assert default opts still yield the legacy parameter set at
  tint strength 0
- `func serialize() -> Dictionary` / `deserialize(d)` over a plain `Array[bool]`
- Cinematic Callable seams (PeekAnimator precedent): `apply_input_lock_fn`, `wait_fn`,
  `begin_camera_fn` / `end_camera_fn`
- Follow `CoinBurstField`'s null-guard discipline exactly: null-guard the peg MultiMesh, the
  `_buckets` array, the underlay nodes, `_camera`, and every `get_tree()`/`add_child()` call.
  Bookkeeping (`_activated`, coin lifetimes, `_process` expiry) must run UNGUARDED so it is
  unit-testable.
- Dev hotkeys must call the public methods, never duplicate logic inline in `_input`.

## Additional required test cases (beyond those already listed)

- interrupted cinematic (`test_cap_raise_reveal.gd:360` analogue): `_teardown()` mid-sequence
  restores `Engine.time_scale == 1.0`, releases the camera, unlocks input, and STILL leaves
  the bucket activated and saved — anti-soft-lock
- two coins arriving during an active cinematic: queued, not stacked, `Engine.time_scale`
  never compounds
- a coin for an already-activated bucket: activation is a no-op AND the coin node is freed
- the win overlay is re-triggerable after dismissal (locked decision 7 requires it for filming)
- `_connect_space_board` is idempotent, and the `has_signal == false` path is a silent no-op
  (test with a stub `Node` both with and without the signal)
- full `SaveManager` round-trip, not just the block in isolation (`test_save_round_trip.gd`)

## ADVISORY — resolved decisions

- **The underlay circle belongs to `SpaceBoard`, not `Bucket`.** Authoring it in `bucket.tscn`
  would multiply a space-only node across every plinko/challenge/menu bucket; a runtime child
  à la `mark_forbidden`'s `SkullIcon` puts a space concept inside `Bucket`. Have `SpaceBoard`
  create the 11 underlay nodes under its own `Buckets` container; `Bucket` gains only
  `mark_activated(on)`. Note `pulse()` animates `position:y` (`bucket.gd:170`), so a CHILD of
  Bucket would bob with it and a SIBLING would not — pick deliberately (sibling is likely right).
- **Keep the node `visible`, gate `_process`.** `set_process(false)` by default (the prototype
  already does this in `_reset_trailer_state`); only the cinematic state machine needs
  `_process`. Do NOT set `visible = false` — the arrival arc plays off-camera while the player
  is watching a color board. One peg MultiMesh + 11 buckets is negligible and frustum culling
  handles it.
- **Nav UI needs a tri-state.** `_update_nav_arrows` (`main.gd:624-631`) and the
  `challenges_down` handler (`:308`) branch on `ModeManager.is_main()`, which stays MAIN while
  in space. `_input` maps `challenges_up` to `switch_to_main()` only when `is_challenges()`
  (`:285`), so up-in-MAIN is currently dead — write the space branch as an explicit
  `elif ModeManager.is_main() and not _viewing_space` / `elif _viewing_space` pair.
  `_on_mode_changed`'s MAIN arm calls `_go_back_to_board()` (`:547`) → a camera tween that
  would race the space camera; guard it.
- **Refuse to enter space** while `peek_animator.is_peeking()` or
  `PrestigeManager.current_phase != NONE` (the `is_suppressed` pattern, `peek_animator.gd:69`).
  Up-to-space during an active challenge is already blocked by the `_input` early-return (`:283`).
- **`ParallaxBackdrop` (`:41,68`) and `BackgroundParticles` (`:146-150`) key off camera
  position/size.** A camera at x=50,y=33 will drag the backdrop and re-scatter particles.
  Not blocking — verify by eye and tune if it looks wrong.
- **Currency → board inversion:** prefer adding `TierRegistry.board_for_currency()` over a
  private table in `SpaceBoard` that can drift from the tier chain. (Moot if the seam signal
  carries `board_type` as specified, which is the preferred fix.)
- **Dependency direction:** reading `TierRegistry` is fine (pure lookup, no state, no signals).
  Reading `CurrencyManager` is NOT — the space board must never touch balances.
- **`reset_state()`** (`save_manager.gd:243`) clears autoload runtime state and cannot clear a
  node. Safe today because `reset_game` reloads the scene and the other paths run when
  `main.tscn` is not live — but note it, and mirror `OnboardingProgress`'s `reset()` vs
  `full_reset()` naming asymmetry (`onboarding_progress.gd:96,108`) if you add reset methods.
- **The transporter emits ONLY `coin_transported`, never `coin_landed`** — otherwise the
  space board would receive a duplicate arrival via two paths.
