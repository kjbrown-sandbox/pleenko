# Feature: Hold-click Drop Buttons

**Branch:** feature/drone-volume-bump  
**Date:** 2026-05-14

## Feature Description

Extend the existing hold-to-drop mechanic (keyboard Space / B) to also work when the mouse button is held down on the normal or advanced drop button. A held mouse button on the drop button should fire coins continuously at the same rate as holding the keyboard shortcut.

Note: Holding B for advanced drop already existed via `Input.is_action_pressed("drop_unrefined")` in `_is_hold_to_drop_advanced_active()`.

---

## Round 1 — Concerns

### Janitor
- `_drop_main_held` / `_drop_advanced_held` as parallel booleans in PlinkoBoard creates duplication; if a third drop type appears, the pattern triples.
- Better: move held state into `FillBar` as `_held: bool` + `is_held() -> bool`. PlinkoBoard polls `is_held()` — no flags to manage, no signal wiring to duplicate.
- `main_mouse_exited` as a held-clear is surprising without a comment explaining drag-off intent.
- Double-fire (shortcut fires `pressed` + first-frame accumulator) is existing behavior; document it.

### Godot Guru
- `button_down` / `button_up` are the correct signals. `button_up` fires unconditionally on release (even off-button), so `mouse_exited` is not strictly needed for stuck-flag prevention.
- Input events (including `button_down`) process before `_process()` in the same frame — no ordering concern.
- No stuck-flag risk on scene reload: all nodes free together, new instances start with `_held = false`.
- Prestige slow-mo slows `delta`, so hold rate slows. Consistent with keyboard hold — acceptable.
- `hack_space` block (if still enabled) bypasses the accumulator; remove if the hold feature is "real."

### Architect
- Adding `main_button_down` / `main_button_up` to FillBar (shared component) leaks drop semantics into upgrade rows and currency bars.
- Better: subclass `FillBar` as `DropFillBar`, or add `is_held()` to FillBar (thin, generic enough).
- Inactive board `_drop_main_held` stuck risk: if state is in PlinkoBoard, a board switch leaves the flag true. `drop_section.visible` guard catches it, but only if visibility is updated synchronously.
- `_show_advanced_drop_bar()` being lazy means advanced hold wiring must be added there too.

### Newcomer
- `_drop_main_held` next to `_hold_drop_accumulator` is confusing — different abstraction layers.
- Two `main_mouse_exited` connects in the same block looks like a mistake; collapse into one lambda.
- Why `mouse_exited` clears held is non-obvious; comment should say "if the mouse leaves while held, button_up won't fire — clear manually."
- `main_pressed` + hold-accumulator coexistence looks like a double-fire bug; add a comment.

### Consistency Lover
- `main_button_down` / `main_button_up` breaks the `<element>_<event>` flat naming convention (no `_button_` in the middle). Should be `main_down` / `main_up`.
- `_drop_main_held` inverts the established `_hold_drop_*` prefix word order.
- New bool state vars must have explicit `: bool` type annotations.
- Consider whether adding signals to FillBar at all vs. just `is_held()` polling.

### Test Lead
- `_tick_hold_drop_accumulator` is already covered by 3 tests; no changes needed there.
- `_is_hold_to_drop_active()` is not headless-testable (depends on `@onready` nodes + `Input` singleton).
- `FillBar._held` wiring not testable headless (requires mouse events).
- One useful test: verify `_tick_hold_drop_accumulator` pacing is identical for advanced hold context (documents the shared-accumulator design).

---

## Resolution

**Agreed approach:** Move held state into `FillBar` as `_held: bool` + `is_held() -> bool`, wired internally in `_build()`. PlinkoBoard only polls `is_held()` — no new state variables or signal connections needed in PlinkoBoard.

This resolves:
- Janitor's duplication concern (state in one place)
- Architect's stuck-flag concern (FillBar owns and clears its own state)
- Consistency Lover's naming concern (no new signals → no naming debate)
- Newcomer's double-connect concern (internalized in FillBar)

**`mouse_exited` clearing `_held`:** Kept for UX — dragging off the button while pressed stops the hold. Wired internally in FillBar alongside the existing `mouse_exited` emit.

**`main_pressed` kept:** Single-click fires once from accumulator (first frame, primed) + once from `main_pressed` on release. Matches existing keyboard shortcut behavior. `request_drop()` affordability guards make this safe.

---

## Final Plan

**`entities/fill_bar/fill_bar.gd`:**
- Add `var _held: bool = false`
- Add `func is_held() -> bool: return _held`
- In `_build()`, wire: `button_down` → `_held = true`, `button_up` → `_held = false`, `mouse_exited` → `_held = false`

**`entities/plinko_board/plinko_board.gd`:**
- `_is_hold_to_drop_active()`: add `or _drop_main.is_held()`
- `_is_hold_to_drop_advanced_active()`: add `or _drop_advanced.is_held()`

**`test/test_plinko_board.gd`:**
- Add `test_hold_drop_advanced_uses_same_accumulator()` documenting shared-accumulator design.
