# Unique Per-Colour Upgrades — Agreed Spec

Shared reference for five sequential feature branches. Decisions below were settled
with the user BEFORE any implementation. Each feature is its own branch; this file
is the contract they all build against.

## Context discovered in the existing code

- **"Unique" upgrades are universal, not per-board.** `UpgradeSection._is_universal_upgrade()`
  routes the signature upgrades out of the per-board panel into the `CoinValues` HUD.
  One shared level, effect applies to every board (deflector reads
  `UpgradeManager.get_level(DEFLECTOR_BOARD=ORANGE, PEG_DEFLECTOR)`).
  All four new upgrades follow this shape.
- **Single-currency model.** `_is_advanced_at_distance()` always returns `false`;
  every bucket pays `TierRegistry.primary_currency(board_type)`. The three-currency
  table in CLAUDE.md is stale on this point.
- **Centre bucket is always unambiguous.** Bucket count is always odd
  (`num_buckets = num_rows + 1`, rows grow by 2), and `distance == 0` is pinned to
  value 1 by `_bucket_value_for_distance`.
- **`force_drop_coin(type, mult, show_burst)` already exists** — spawns a coin outside
  the queue with a baked-in multiplier. `finalize_coin_landing` already folds
  `coin.multiplier` into the payout and renders floating multiplier text.
- **Wander timing is 8.0s.** `PlinkoBoard.GAMEPLAY_TARGET_DURATION = 8.0`,
  `GAMEPLAY_TARGET_FADE_START = 1.0`. `WanderingBucketSelector.pick` is the shared
  "never repick the current one" helper.

## Branch order (sequential, each chained off the previous)

1. `feature/remove-advanced-autodropper` — cleanup, frees red's slot
2. `feature/dud-chute` (violet) — cheapest, mostly reuses `force_drop_coin`
3. `feature/lucky-peg` (green)
4. `feature/board-tilter` (blue)
5. `feature/auto-buy` (red) — most invasive, lands last

## 0. Remove Advanced Autodropper  ✅ DONE

Removed with the raw/advanced coin economy it depended on. It was already
unreachable: `_show_advanced_drop_bar()` was a hard `return` stub, so the advanced
drop button never appeared, so the advanced autodropper pool had no button to
assign to.

**Retired in place, not unregistered.** `Enums.UpgradeType.ADVANCED_AUTODROPPER` and
`data/advanced_autodropper.tres` MUST stay registered: `UpgradeManager.deserialize`
indexes `_state[board][type]` directly for every enum value, so unregistering would
crash any save that recorded the key. `UpgradeManager.RETIRED_UPGRADES` +
`unlock()` refusing them is what makes it unreachable — and it retroactively clears
saves that already had it unlocked.

Stale `"<BOARD>_ADVANCED"` assignment keys are dropped on load
(`BoardManager.restorable_assignments`, pure + static) and are inert offline.

## 1. Red — Auto-buy

- Lock scope: **per (board, upgrade) pair**. ~36 lockable entries, so one slot is a
  small grant — needs a generous level curve or >1 slot per level.
- Cadence: **instant on affordability** (hooks `CurrencyManager.currency_changed`).
- A capped upgrade **keeps** its lock; the slot does not auto-free.
- Suppressed during challenges, consistent with `UpgradeManager.upgrade_gate`.
- Wiped by prestige alongside upgrade levels; otherwise persisted.
- UI: the `UpgradeRow` bar switches to `RefinedBaselineButton.Mode.WITH_BOTH`; the
  **left cap becomes the auto-buy toggle**, the right cap stays the cap-raise `+`.
- OPEN RISK: instant-on-affordability + per-pair locks means locked upgrades drain
  currency before the player can buy anything manually on that board. Watch in test.

## 2. Violet — Dud chute

Centre-bucket (`distance == 0`) landing has a small chance to re-spawn the coin on
the **previous** board with a ×10 multiplier, compounding on each successive hop.

- Payout uses the **destination board's currency** — a violet coin landing on red
  credits RED ×10. No change needed in `finalize_coin_landing`; it is essentially
  `previous_board.force_drop_coin(coin.coin_type, coin.multiplier * 10.0)`.
- Upgrade level raises the **chance only**; multiplier is fixed at ×10.
- Base chance 2%, identical on every hop (no decay).
- Gold is exempt (no board behind it).
- Multiplicative with the golden-bucket ×2 and bomb multipliers (rides `coin.multiplier`).
- Transported landings emit `coin_landed` normally and may trigger prestige /
  cap-raise cinematics — they are ordinary coins carrying a multiplier.
- **Naming:** must NOT be called "transporter" in code — the earring/SpaceBoard
  transporter bucket already owns that word and sits at the same board-local x=0.
- **Architecture:** PlinkoBoard emits UP, BoardManager routes DOWN to the previous
  board. PlinkoBoard must not look up sibling boards itself.
- VFX: short arc from the centre bucket toward the previous board, coin materialises
  at that board's drop point with a burst. Camera does not follow.

## 3. Green — Lucky peg

A wandering peg that splits any coin striking it into two, then respawns elsewhere
after 0.5s.

- Representation: an **existing lattice peg, lit up** — reuse `PegField`'s per-peg
  flash/pulse/halo/sparkle and `Coin`'s existing peg-strike reporting. Inherits
  void/gateway filtering for free.
- Split: **full value each, and split coins can split again** (geometric growth).
- **No cap, by explicit user decision.** Flagged as a risk against the
  "tens of thousands of coins" constraint. Keep the split site a single chokepoint
  so a ceiling is a one-line addition if it bites in testing.
- Split sends one coin left and one right (guaranteed divergence, no overlap).
- Never spawns on a voided or gateway column; MAY spawn on a peg holding a deflector
  (the deflector still resolves the halves' subsequent bounces).
- 8s wander with a 1s fade, matching `GAMEPLAY_TARGET_DURATION`. Independent timers
  per peg; two lucky pegs can never occupy the same peg.
- Upgrade level = number of simultaneous lucky pegs per board.
- Board is simply lucky-peg-free during the 0.5s respawn gap.

## 4. Blue — Board tilter

- Semantics: **centre-seeking bias** — at each peg the coin is biased toward (or away
  from) board-local x=0 depending on which side it is currently on. NOT a fixed
  left/right bias.
- Slider is **per board**, persisted; the upgrade level (global) sets extreme strength.
- Stepped, 5 notches: Centre / — / Default / — / Edges.
- Level 1 = 55/45 at the extremes, +2.5% per level, ceiling 75/25.
- A peg holding a deflector **ignores tilt entirely** — a deliberate player placement wins.
- Applies to earring boards too (same bounce resolution path).
- UI: **its own per-board Control anchored beneath the buckets**, separate from
  `DropSection`. Needs its own show/hide wiring on board switch.

## Cross-cutting

- Four new `Enums.UpgradeType` values, **appended last** (saves store `type` as int).
- `SaveManager.SAVE_VERSION` bump + migration when new persisted state first lands.
- Costs/caps proposed from the existing `.tres` curves for the user to tune.
- Green is unreachable-at-hard-cap by design (`TierRegistry.cap_raise_currency`
  returns -1 for the last tier) — the lucky peg ships behind a board you can reach
  but not complete. Not treated as a blocker.
