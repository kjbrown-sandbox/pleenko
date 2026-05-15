# Feature: Autodropper Intro Animation

## Feature Description

When the first autodropper is bought, instead of immediately auto-assigning it to the gold board, play a guided first-time experience: sparkle particles fly from the autodropper upgrade row (in CoinValues HUD) to the gold drop button, the drop button transforms to reveal its +/– controls, and the + button pulses until the player clicks it. Subsequent purchases auto-assign to gold as before.

---

## Round 1 — Parallel Personality Analysis

### The Janitor — Code Cleanliness

**[BLOCKING]** First-time flag ownership is unclear — `OnboardingProgress` is the correct home (matches existing `_peeked_boards` / `_peeked_challenges` pattern). Flag must be precisely named to capture what it gates: `_autodropper_intro_seen` (animation has played), not "autodropper purchased."

**[BLOCKING]** `BoardManager._on_upgrade_purchased` is already doing too much. Adding "check first-time flag, trigger particle animation, skip assignment" to it would push it further into UI orchestration. Animation trigger must live in a coordinator (new AutodropperIntroAnimator child of Main, like PeekAnimator), not inline in BoardManager.

**[ADVISORY]** Particle emitter code will duplicate `level_section.gd`. Extract-or-copy consciously; don't silently clone.

**[ADVISORY]** Pulse teardown responsibility must be documented — tween reference owned by AutodropperIntroAnimator, stopped via `plus_pressed` one-shot connection.

---

### The Godot Guru — Engine Best Practices

**[BLOCKING]** Signals up, calls down. BoardManager must not reach into UI nodes. Correct pattern: BoardManager emits `first_autodropper_purchased`; Main-owned AutodropperIntroAnimator listens and orchestrates between CoinValues and DropSection.

**[BLOCKING]** `camera.unproject_position()` is NOT the right API. Both the CoinValues upgrade row and the DropSection FillBar are 2D Control nodes — use `Control.get_global_rect().get_center()` for screen-space coordinates.

**[ADVISORY]** `await` chains across scene boundaries need `is_instance_valid()` guards.

**[ADVISORY]** Confirm FillBar is visible before starting pulse (controls shown first, then pulse — ordering is correct in this design).

---

### The Architect — Dependencies & Connections

**[BLOCKING]** Position-bridging problem: source (CoinValues UpgradeRow) and target (DropSection FillBar) are both 2D Controls, accessible via `get_global_rect()`. AutodropperIntroAnimator (child of Main) can reach both. No camera projection needed.

**[BLOCKING]** SaveManager migration: bump to v6, seed `autodropper_intro_seen = true` for existing players who already have `normal_autodroppers_unlocked = true`.

**[BLOCKING]** Load/deserialize path must be unaffected — `deserialize()` calls `set_normal_autodroppers_visible(true)` directly when flag is set. Only the live first-purchase path is gated by OnboardingProgress.

**[ADVISORY]** `_apply_prestige_rewards()` is also unaffected — it runs in a context where `_normal_autodroppers_unlocked` is already true (set during `_apply_prestige_rewards` itself or already saved).

**[ADVISORY]** Pool shows "1 free" before player clicks +, since `_normal_pool` increments immediately. Acceptable design — controls aren't visible yet, so no confusing display.

---

### The Newcomer — Readability & Clarity

**[BLOCKING]** "First time" is overloaded. Clarify: flag guards "has the animation ever played," which is equivalent to "have the controls ever been revealed via the intro." Name: `_autodropper_intro_seen`.

**[ADVISORY]** Sequence should be named as discrete phases: burst → swoop → complete_intro → pulse. Use named functions, not a single long chain.

**[ADVISORY]** Pulse stopped on first click has implicit state — use a one-shot signal connection on `FillBar.plus_pressed` to document intent.

**[ADVISORY]** "Sparkle particles" → explicitly use the same `ColorRect` tween pattern from `level_section.gd` lines 268–333. Don't invent a new particle system.

---

### The Consistency Lover — Standardization

**[BLOCKING]** State must live in `OnboardingProgress` (not BoardManager) — it persists through prestige resets. `BoardManager` state resets on prestige; `OnboardingProgress` does not.

**[BLOCKING]** `set_normal_autodroppers_visible()` must remain the single entry point for revealing controls — both the intro path (via `reveal_autodropper_controls()` callback after animation) and the deserialize path call it.

**[BLOCKING]** Pulse must use FillBar's existing APIs correctly. `set_attention(true)` pulses the whole FillBar. For pulsing just the + button: call `ThemeProvider.theme.blink_scale_fade(fill_bar.plus_button)` directly; stop it on `plus_pressed` via one-shot connection.

**[ADVISORY]** Signal name `first_autodropper_purchased` follows `verb_noun` convention. Good.

---

### The Test Lead — Testing & Testability

**[BLOCKING]** First-purchase-no-auto-assign is directly testable headlessly. Add to `test_prestige_autodropper.gd`.

**[BLOCKING]** `test_all_normal_autodroppers_auto_assign_to_gold` tests second+ purchase behavior (pre-sets `_normal_autodroppers_unlocked = true`). Add clarifying comment; add new test for first-purchase path.

**[BLOCKING]** `OnboardingProgress._autodropper_intro_seen` flag: add round-trip test (starts false, mark → true, serialize/deserialize → true, reset → still true).

**[ADVISORY]** Animation itself is not headlessly testable (tween/Control scene dependency). Document explicitly.

---

## Round 2 — Resolutions

All blocking concerns resolved in design:

1. **Coordinator pattern**: New `AutodropperIntroAnimator` node, child of Main. BoardManager emits `first_autodropper_purchased`. Animator handles all UI orchestration.
2. **Position API**: Confirmed both endpoints are 2D Controls (`get_global_rect().get_center()`). DropSection.tscn is a Control child of PlinkoBoard, anchored to viewport center-top.
3. **Flag location**: `OnboardingProgress._autodropper_intro_seen`, survives prestige (`reset()` does NOT clear it).
4. **SaveManager migration v5→v6**: Seeds intro_seen for existing players with autodroppers already unlocked.
5. **Pulse target**: `blink_scale_fade(fill_bar.plus_button)` directly; stopped on `FillBar.plus_pressed` one-shot.
6. **Tests**: Two new headless tests; existing test clarified with comment.

---

## Final Plan

See `/Users/kjbrown/.claude/plans/i-want-a-new-piped-lake.md`.

---

## Post-Implementation Review

*(to be appended after implementation)*
