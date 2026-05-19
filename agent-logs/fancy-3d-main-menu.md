# Fancy 3D Main Menu — Feature Deliberation Log

## Feature description

Replace the sad two-button main menu with a polished landing screen (inspired by
Mini Metro / "A Game About Feeding a Black Hole"):

- A decorative 3D Plinko board behind the UI, rendered with a **perspective**
  camera (gameplay is orthographic — deliberate menu-only exception) positioned
  near the board's top, angled looking down so pegs read as 3D pins and ~20 rows
  recede/shrink toward the bottom of the screen. Coins continuously fall and
  bounce down.
- Right-aligned button column: Play / gap / {Settings, Join the Discord, Press
  Kit, Report a Bug} / gap / Quit.
- Themed title "Now With More" / "Plunk".
- Settings reuses the in-game `OptionsDialog`; Reset Game moves into Settings.
  External links stubbed with placeholder URLs; Quit exits.

User decisions captured up front: lightweight visual-only board (not the real
coupled `PlinkoBoard`); Reset Game → into Settings; Settings real + links
stubbed; title text "Now With More Plunk".

## Round 1 — Concerns (six personalities, parallel)

**The Janitor (cleanliness)** — BLOCKING: peg-lattice math would become a 4th
copy (canonical in `plinko_board.gd`, already re-inlined ~3× in `style_lab.gd`)
→ extract a shared static module. BLOCKING: OptionsDialog reuse via a bare
boolean leaves dead in-game autoload coupling in the shared file. BLOCKING:
don't copy style_lab's inline halo-shader GLSL; use MultiMesh pegs. BLOCKING:
moved Reset Game must reuse the existing palette-styled `ConfirmLayer`.

**The Godot Guru (engine)** — BLOCKING: no concurrency cap on decorative coins
(unbounded node/tween leak). BLOCKING: no cleanup on scene exit (SceneManager
frees MainMenu mid-fade while tweens run). BLOCKING: must not create a second
WorldEnvironment (ThemeProvider autoload owns the active one). BLOCKING: steep
camera degenerates `look_at` default up — author rotation in the `.tscn`.
Advisory: single MultiMeshInstance3D for ~210 pegs; Timer node not _process;
ship without peg flash.

**The Architect (dependencies)** — BLOCKING: OptionsDialog has no `.tscn` and
builds its UI in `_ready()` (before `show_dialog`) → context must be set before
`add_child`; extract `_build_footer()`; `enum Context { IN_GAME, MAIN_MENU }`.
BLOCKING: SceneManager fade vs live board → bounded/guarded coins. BLOCKING:
keep menu save-state-free by contract; the `MAIN_MENU_PATH` reload path must be
unreachable in menu context. Advisory: no new signals from the board (calls
down only); update CLAUDE.md docs at merge.

**The Newcomer (readability)** — BLOCKING: `sqrt(3)/2`, ~20 rows, camera
transform/FOV must be named consts with intent comments. BLOCKING: don't copy
style_lab's bucket/landing logic or `currency` threading (menu has no economy);
don't copy `_build_board_slice` name or editor-tool blocks. BLOCKING: comment
the three "why"s (triangular lattice = real game; perspective vs orthographic
is deliberate; decorative-only). BLOCKING: recursive bounce needs explicit
`row` param + top-of-function base case. BLOCKING: preserve the documented
contrast-fix styling block when Reset moves.

**The Consistency Lover (standardization)** — BLOCKING: themed title+buttons
(no raw Color/Font); board meshes via `t.make_*`; Reset card keeps palette
stylebox; direct `_on_*_pressed` method refs + `const` URLs; typed math locals;
no hardcoded row count; non-`@tool`, strip editor dead code. Advisory: named
bounce method over lambdas; Timer node; keep menu as `.tscn`; `class_name
MenuBoard`.

**The Test Lead (testability)** — BLOCKING: lattice/advance/despawn pure on a
bare `MenuBoard.new()` reusing `PlinkoBoard` names; no decision logic in tween
lambdas; Callable seams (`_shell_open_fn`, `_quit_fn`, `_full_reset_fn`) per
the `PeekAnimator` precedent; new `test_menu_board.gd` +
`test_main_menu_wiring.gd` + extend `test_full_reset.gd`. Parity test vs the
real board.

## Round 2 — Conflict resolution

Two genuine conflicts; both resolved by synthesis (no user escalation).

**Conflict A — Reset-confirm ownership.** Janitor/Newcomer/Consistency: reuse
the existing palette-styled `ConfirmLayer`, no duplicate confirm widget.
Architect: build confirm into OptionsDialog and delete `ConfirmLayer` to
consolidate the flow.

*Resolution (refined reconciliation):* Keep and reuse the existing
`ConfirmLayer` in `main_menu.tscn` (preserves the documented contrast fix; no
duplicate UI). Add `enum Context { IN_GAME, MAIN_MENU }` to `options_dialog.gd`,
set **before `add_child`**; extract `_build_footer()` so the `MAIN_MENU` footer
constructs only "Reset Game" + "Close" and **does not construct** `_return_button`
nor reference `_on_return_pressed`/`MAIN_MENU_PATH` (structural unreachability,
not a hidden node). The Reset button emits `reset_requested` **up** to MainMenu
(signals up, calls down); MainMenu hides the dialog, shows the reused
`ConfirmLayer`, Cancel re-shows the dialog, Confirm calls the unchanged
`SaveManager.full_reset()` (no scene reload). One-line ripple on the in-game
caller `main.gd._setup_options_dialog` (set `IN_GAME` before `add_child`).
Signal-up chosen over a direct call (too destructive in a dual-context dialog)
and over a callable seam (inconsistent with the codebase's universal `signal`
use for UI→parent; the testable seam belongs on MainMenu's hop to SaveManager).

**Conflict B — Lattice drift prevention.** Janitor: extract `scripts/lattice.gd`
and forward PlinkoBoard's methods. Test Lead: duplicate in MenuBoard + a parity
test. Architect: flagged ripple risk on the well-tested core board.

*Resolution (synthesis):* Extract-and-forward wins (structural single-source-of-
truth matches the codebase's documented invariant; duplicate-and-test is the
weaker form of the same guarantee, and `style_lab.gd` already proves duplication
drifts). The Test Lead's parity assertion is **kept** as the forwarder tripwire
(`PlinkoBoard.* == Lattice.*`), giving structural prevention + an inverse-drift
alarm. Ripple is bounded: 3 pure methods, sole external caller is `Coin` via
unchanged public signatures; the existing `test_deflector.gd` characterization
tests (`test_position_x_for_matches_build_formula`,
`test_cell_to_world_origin_matches_launch_target`,
`test_next_lattice_cell_left_right`) re-run unchanged and de-risk the refactor —
no pre-refactor characterization tests needed. Key constraint:
`Lattice.cell_to_world` takes `vert_spacing` and `row_y_offset` as parameters
(never recomputes); `COIN_ROW_Y_OFFSET` stays a `PlinkoBoard` constant
(`test_deflector.gd` references it). `style_lab.gd` left as deliberately-deferred
debt with `# TODO(Lattice)` markers (editor-only `@tool`, out of scope).

## Final plan

See `/Users/kjbrown/.claude/plans/i-ve-got-some-ideas-toasty-dongarra.md`
(approved). All Round 1 blocking concerns are incorporated; both Round 2
conflicts resolved by synthesis above.

## Iteration 2 — refinement round (six-personality, Round 1, consensus)

Four art requests on the working menu: (A) camera mid-angle, (B) halve max
bounce, (C) peg jiggle → springy directional wobble, (D) animated filled
near-bg triangle backdrop ("more is happening"). A & B are trivial constant
tweaks (no review). C & D were reviewed.

**Round 1 concerns (condensed):**

- *Janitor* — BLOCKING: triangle field must be its own sibling scene, not
  folded into the 435-line `_process`-free `menu_board.gd`. BLOCKING: delete
  scale-pop consts on wobble (stale names mislead) + the `_jiggle_peg` call sits
  *before* `direction` is computed → reorder. Decisive NO to generalizing
  `background_particles` (its `bg_particles_enabled` gate + orthographic
  `_camera.size` are load-bearing gameplay coupling); copy the ~25-line pattern.
- *Godot Guru* — BLOCKING: triangles at negative Z, keep stock
  `drop_burst_multimesh.gdshader` render_mode (`depth_draw_never` so they don't
  z-fight, `depth_test` on so pegs occlude); never `no_depth_test`. BLOCKING:
  perspective cam has no `.size` — reuse of `_get_spawn_rect` is a bug; constant
  world rect. BLOCKING wobble: compose `Basis(Vector3.UP, lean) * _peg_basis`
  (never decompose the PI/2 base), restore literal `base_xform` (no drift),
  axis = world Y for a +Z pin leaning in ±X.
- *Architect* — child `$Triangles` node, no new signals (calls-down-only
  preserved), no `theme_changed` subscription (menu theme static), no new
  `VisualTheme` fields, `direction` stays a local threaded only
  `_advance_coin_bounce → _wobble_peg` (not into the `.bind` chain).
- *Newcomer* — BLOCKING: avoid `bg_particles_*` vocabulary (false signal of the
  theme-flag system); `*_DEG` angle naming; "HOLD" not "lifetime"; count==cap
  one const; rewrite stale `_jiggle_peg` doc-comment; class "why" block.
- *Consistency* — corrected fact: `background_particles` IS a `.tscn`+`.gd`
  pair → mirror it (own scene). Explicit local typing. Reuse `_pick_color`
  verbatim (theme-sourced colour). Keep `_wobble_peg` structure 1:1 with the
  old dedupe/`_track_tween`/restore machinery.
- *Test Lead* — keep the fade curve a pure `elapsed→alpha` function (testable
  on a bare `.new()`); extract `_wobble_lean_sign(direction)` pure; add a
  signature tripwire so the rework can't silently break the 3 bare-instance
  menu tests. ~13 assertions total — proportionate to decorative chrome.

**Conflicts resolved by synthesis (no escalation):**

1. *Triangle mesh:* ArrayMesh-1-tri + reuse the already-warm shared
   `drop_burst_multimesh.gdshader` (Godot Guru) over a new triangle-mask shader
   (Janitor) — avoids shader-variant compile stutter (first-drop-lag memory),
   no new file; the "no ArrayMesh precedent" concern is mitigated by it being
   one static commented mesh built once.
2. *Colour-shift source:* reuse the existing `VisualTheme.bg_particles_color_shift`
   field for the darken/lighten magnitude — keeps colour theme-sourced
   (Consistency) without adding new theme schema or using the
   `bg_particles_enabled` flag (Architect/Janitor).
3. *`class_name`:* add `class_name MenuTriangleField` (Test Lead needs
   `.new()` for pure fade tests) despite `background_particles` having none —
   testability + broad entity convention win.

## Post-Implementation Review

_(to be appended after implementation is confirmed and the six-personality
post-implementation review runs)_
