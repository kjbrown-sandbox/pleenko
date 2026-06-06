# `prototype/earrings` — Handoff & Recreation Spec

**Status:** The `prototype/earrings` branch is an abandoned trailer/experiment branch. It
will **not** be merged. This document is the curated set of things worth carrying
forward, written so a future agent can recreate them cleanly **on a fresh branch off
`main`** — no cherry-picking from `prototype/earrings` required.

It has two parts:

- **Part 1 — Port to `main` now.** Small, clean changes (themes, one timing constant,
  one challenge-grouping tweak, dev hotkeys). All target files already exist on `main`.
- **Part 2 — Earrings feature draft.** A design sketch to rebuild *later, properly*.
  **Do NOT add earrings to `main` now.**

> Context note for whoever picks this up: on `main`, `nier_lofi` is the default normal
> theme and `glow_dark` is the challenge theme (see
> `autoloads/theme_provider/theme_provider.gd` `normal_theme` / `challenge_theme`
> exports). All theme presets named below already exist on `main`; the branch only
> tweaked their values — it created **no new presets**.

---

## Part 1 — Port to `main`

### 1.1 Theme changes (all EXCEPT premium gold)

Apply these exact value changes. They were co-tuned to make the backdrop triangles read
against their backgrounds, so evaluate the set together by eye after applying.

| File | Change |
|---|---|
| `autoloads/theme_provider/theme_provider.tscn` | Set `normal_theme` to reference `style_lab/presets/cosmic_burst.tres` (uid `uid://och1vgwtffcu`). This makes **cosmic_burst the default normal-mode theme** instead of the script default `nier_lofi`. *This is the single biggest live-look change — confirm it's wanted.* |
| `style_lab/presets/cosmic_burst.tres` | Add `vignette_radius = 0.7` (was the schema default 0.75 — slightly tighter/darker frame). |
| `style_lab/presets/glow_dark.tres` (challenge theme) | `bg_triangle_light`: `Color(0.08, 0.08, 0.08, 1)` → `Color(0.18, 0.18, 0.18, 1)` (near-invisible → faintly visible backdrop triangles in challenges). |
| `style_lab/presets/lavender_lofi_dark.tres` | `bg_triangle_light`: `Color(0.2, 0.16, 0.245, 1)` → `Color(0.32, 0.27, 0.38, 1)`. |
| `style_lab/presets/nier_lofi.tres` | `bg_haze_subtle`: `Color(0.8325, 0.795, 0.7325, 1)` → `Color(0.7, 0.64, 0.56, 1)` (darker so the gameplay triangles read). |
| `entities/parallax_backdrop/parallax_backdrop.tscn` | Add `min_peak_alpha = 0.2` and `max_peak_alpha = 0.5` (gameplay backdrop triangles spawn fainter and more varied; pairs with the nier_lofi haze change). |

**EXCLUDE (do NOT port):** the `premium_gold_main` / `premium_gold_faded` colors added to
`cosmic_burst.tres` on the branch. Those exist only for the earrings currency (Part 2) and
are dead weight without that feature.

### 1.2 Multi-drop stagger timing

`entities/plinko_board/plinko_board.gd`:

```gdscript
const MULTI_DROP_STAGGER := 0.05   # was 0.15
```

Delay between bonus coins in a multi-drop burst. 3× tighter — coins land closer together,
clustering the landing chord. Pure game-feel value, zero coupling. Verify it still feels
good by ear (it was tuned during trailer work).

### 1.3 Orange challenge grouping — all row-ends converge on the boss

`entities/challenge_grouping/challenge_group_orange.tscn` (the surgical `f634b13` change —
**not** the trailer button-position shuffle). Add `"orange_boss"` to the two row-end nodes
that previously dead-ended, so all three orange rows converge on the boss node:

- one node's `next_challenges`: `["orange_8"]` → `["orange_8", "orange_boss"]`
- another node's `next_challenges`: `["orange_12"]` → `["orange_12", "orange_boss"]`

(Net effect: the boss reads as the obvious terminal node from every row.) **Skip** the
reshuffled button `transform`s in the `challenge_group_*.tscn` files — those were composed
for trailer shots and are not wanted.

### 1.4 Dev hotkeys (editor-only)

All hotkeys live in `entities/main/main.gd` `_input`, each gated behind `not demo_mode`.
`demo_mode` is force-set to `true` in non-editor builds (`if not OS.has_feature("editor"):
demo_mode = true`), so **these can never fire in an exported build** — they are editor-only
dev tools. To use them in the editor, `demo_mode` must be `false` (the branch flipped the
`@export` default to `false` for this; on `main` decide whether to keep the default `true`
and toggle per-session, or default `false` knowing exports are still guarded).

**Already on `main` (leave as-is):**
- `KEY_P` → `_debug_test_prestige()`
- `KEY_O` → `_debug_setup_prestigeable_state()`

**Standalone — safe to port (no trailer/earring deps):**
- `KEY_6` → give gold: sets `CurrencyManager.caps[GOLD_COIN]` and adds `10_000_000_000_000_000`
  (10 quadrillion). *Fix the stale comment when porting — it says "1T" but the value is 10
  quadrillion.*
- `KEY_7` → `_preview_add_rows(active_board)`: runs the add-rows glissando on the active
  board then auto-reverts after a hold, so you can preview the upgrade VFX without leveling.
  Depends only on `PlinkoBoard.add_two_rows()` (already on `main`). Port the
  `_preview_add_rows` helper too.

**NOT portable standalone — depend on features we are discarding (document only, do not
port unless their feature is rebuilt):**
- `KEY_1`–`KEY_5`, `KEY_8` → trailer-camera shots / space-board cinematic (need
  `TrailerCamera` + `SpaceBoard`, both discarded).
- `KEY_E` → `toggle_earring_zoom()` (needs the earrings feature, Part 2).
- `KEY_V` → `vaporize_column_at_offset()` (a trailer-only laser cosmetic in
  `plinko_board.gd`; distinct from the real bomb/forbidden voiding already on `main`).

---

## Part 2 — Earrings feature design draft (FUTURE — do not build on `main` yet)

A sketch of what the earrings prototype did, plus notes on how to rebuild it *cleanly*. The
prototype implementation is a mess; treat this as a design starting point, not code to copy.

### Concept

Once the player's main board stops growing, further "Add rows" purchases instead grow two
small decorative-but-functional **sub-boards ("earrings")** that hang beneath the two edge
buckets. Coins that land in an edge bucket fall *through* into the earring below and bounce
down a second mini-lattice, paying out a new premium currency. The visual is a board
"wearing earrings."

### Prototype mechanics (as built on the branch — for reference)

- **Trigger:** earrings appear once the `ADD_ROW` upgrade reaches level
  `EARRING_TRIGGER_LEVEL` (4) **and** the board has ≥ 7 buckets.
- **Main-board cap:** the main board is capped at `MAIN_BOARD_MAX_ROWS` (10 rows = 11
  buckets, the `edge-o-o-g-g-g-g-g-o-o-edge` layout). `ADD_ROW` purchases past the cap call
  `build_board()` which grows the earrings instead of the main triangle. Earring size:
  `earring_rows = 2 + (level - EARRING_TRIGGER_LEVEL) * 2`.
- **New currency:** `PREMIUM_GOLD` (appended to `Enums.CurrencyType`). Earring buckets are
  all `PREMIUM_GOLD`; landing in one credits a flat `+1` and bursts particles. Theme colors
  `premium_gold_main` / `premium_gold_faded` were added to the `VisualTheme` schema.
- **Bucket-layout override:** while earrings are active, the bucket types are forced to a
  fixed pattern (`edge=PREMIUM_GOLD`, indices `[1,2]` and `[n-3,n-2]`=advanced, middle=
  primary) regardless of width, overriding the normal distance-from-center logic.
- **Coin handoff:** when a coin lands in an edge bucket (index `0` or `num_buckets-1`),
  `PlinkoBoard` reroutes it: swaps the landing/prestige listeners, reassigns `coin.board` to
  the `EarringBoard`, and calls `coin.start()` to teleport it onto the earring's top peg.
- **`EarringBoard`** (`entities/earring_board/`) is a `Node3D` (deliberately **not** a
  `PlinkoBoard` subclass) that **duck-types** the interface `Coin` reads: `cell_to_world`,
  `next_lattice_cell`, `is_terminal_cell`, `is_lattice_cell_voided` (always false),
  `predicted_bucket_index`, `resolve_bounce_direction` (plain 50/50), `flash_nearest_peg` /
  `notify_deflector_resolved` (no-ops), `get_bucket`, plus `num_rows` / `space_between_pegs`
  fields. `EARRING_GAP_BELOW_BUCKET` (0.4) is the vertical gap below the edge bucket.
- **Supporting hacks:** `coin.gd` un-typed `var board` (was `: PlinkoBoard`) so an
  `EarringBoard` could be assigned; `coin_values.gd` gates out `PREMIUM_GOLD` so no orphan
  "0/cap" HUD bar appears (it has no tier).

### What to do differently in a clean rebuild

The prototype's seams are the things to fix:

1. **Formalize the coin surface.** `Coin` should target an explicit interface/base class
   shared by `PlinkoBoard` and `EarringBoard` (e.g. a `CoinSurface` abstraction), instead of
   duck-typing and an untyped `coin.board`. This removes the type-safety loss and makes the
   contract discoverable.
2. **Design the `PREMIUM_GOLD` economy first.** The prototype paid a flat `+1` with no tier,
   no caps, no upgrades, no sink. Decide what premium gold is *for* and how it fits the
   existing gold/orange/red refinement economy before writing code. If it doesn't earn its
   place in the economy, it shouldn't be a currency.
3. **Make the growth-diversion intentional.** The `MAIN_BOARD_MAX_ROWS` cap was a magic
   constant repurposed to redirect growth into earrings. A real version should model
   "main board done → invest in earrings" as a deliberate, configurable progression step.
4. **Don't override the bucket layout implicitly.** The fixed `edge-o-o-…-o-o-edge` override
   inside `build_board()` is surprising. Make the earring-era layout an explicit, data-driven
   board configuration.
5. **Keep earrings out of challenges.** In the prototype they were naturally suppressed
   because challenges grant no `ADD_ROW` levels; preserve that (challenges author exact board
   sizes and should never sprout earrings).

### Open design questions

- What is premium gold spent on? Its own upgrades? A fourth board/tier? A prestige sink?
- Is the payout flat, or should earrings have their own bucket values / multipliers?
- Visual language: how do earrings read at the normal play zoom vs. when focused?
- Balance: how many `ADD_ROW` levels should earrings absorb, and at what cost curve?

---

## Quick checklist for the porting agent

- [ ] New branch off `main` (e.g. `feature/theme-and-dev-tweaks`).
- [ ] Apply the six theme changes in §1.1 (exclude premium-gold colors).
- [ ] `MULTI_DROP_STAGGER` → `0.05` (§1.2).
- [ ] Orange grouping: add `orange_boss` to the two row-end nodes (§1.3); do not touch button positions.
- [ ] Port `KEY_6` (fix the stale comment) and `KEY_7` + `_preview_add_rows`; leave `KEY_P`/`KEY_O`; decide `demo_mode` default (§1.4).
- [ ] Do NOT port earrings, the space board, the trailer camera, the per-challenge color overrides, the deflector-slot baseline, or the trailer challenge redesigns.
- [ ] Tests on commit per project convention (the multi-drop/grouping/hotkey changes are data/value-level; add coverage where there's testable logic).
