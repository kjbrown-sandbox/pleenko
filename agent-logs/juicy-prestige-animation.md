# Feature: Juicy Prestige Animation

## Feature Description

When a coin is about to land in a bucket that triggers a prestige:
1. On the final peg bounce, camera focuses on the coin and world slows down
2. Coin slowly approaches the prestige bucket
3. On contact, world freezes
4. Coin turns white, grows to fill the screen (transition to white background)
5. Transition to a new "Prestige Screen" scene showing "Prestige Up!", unlocked rewards, and "Claim rewards" button
6. Claiming loads main scene back (not main menu)
7. SceneManager gets an "instant" transition function (no fade)

## Round 1 — Initial Concerns

### The Janitor (Code Cleanliness)
- Prestige Screen risks duplicating existing prestige_dialog. Reuse or replace, don't have two.
- plinko_board.gd is already 557 lines — don't add prediction logic there, it'll blow up.
- Camera focus must stay in board_manager.gd (owns camera). time_scale in prestige_manager.gd.
- Proposed: new `prestige_animator.gd` (~80 lines) for visual sequence.
- Reuse visual_theme.gd pulse helpers and material creation for white flash.

### The Godot Guru (Engine Best Practices)
- Predicting final bounce requires a pure simulation function — extract path prediction with no side effects.
- Engine.time_scale affects ALL tweens/timers. Never set to 0.0 — use 0.1-0.15.
- Camera chasing a tween-animated coin: lerp in _process, don't reparent camera.
- Coin-fills-screen must be 2D, not 3D mesh scaling. Use unproject_position() → 2D ColorRect on CanvasLayer.
- Kill coin tweens before freeing nodes during transition.
- Add completion signal to SceneManager.

### The Architect (Dependencies & Connections)
- Prediction belongs in PlinkoBoard, not Coin. Coin stays a leaf node.
- New signal: `prestige_imminent(coin, bucket_position)` from PlinkoBoard.
- PrestigeAnimator listens to this signal, owns animation, emits `prestige_animation_complete`.
- Replace PrestigeDialog with Prestige Screen scene — fundamentally different UX contract.
- Edge case: multi-coin approaching prestige simultaneously — need a "locked" flag.
- Disable autosave during animation window.

### The Newcomer (Readability & Clarity)
- Prediction logic is cross-cutting (coin position + board layout + currency + prestige state) — needs a named home.
- Animation state machine must be explicit: enum `PrestigePhase` with SLOW_MO, FREEZE, EXPAND, TRANSITION.
- Engine.time_scale assignment needs named methods (_enter_slow_mo, _restore_time_scale), not inline.
- All timing values need named constants.
- Signal name: `prestige_imminent`.

### The Consistency Lover (Standardization)
- Animation timing must go in ThemeProvider/VisualTheme.
- Signal naming: past tense convention.
- SceneManager: add `instant` parameter to existing `set_new_scene()`, don't fork the API.
- Camera work through BoardManager using EASE_IN_OUT + TRANS_CUBIC.
- Dialog must be PROCESS_MODE_ALWAYS.

## Round 1 Disagreements

1. **Dialog overlay vs full scene** — Janitor (extend dialog) vs Architect (new scene) vs Consistency (keep dialog pattern)
2. **Animation ownership** — Janitor (split: animator + manager) vs Architect (PrestigeAnimator owns all)
3. **Coin-fills-screen: 2D or 3D?** — Guru (2D CanvasLayer) vs others (didn't address)
4. **time_scale = 0 vs small value** — Guru (never 0) vs Newcomer (phase enum)

## Round 2 — Resolutions

### Disagreement 1: Full scene (RESOLVED)
All 5 agents conceded to Architect. User explicitly said "transition to a new scene" and "use SceneManager." This is a stated requirement, not an architectural preference. Full scene wins.

### Disagreement 2: Split ownership (RESOLVED, 4-1)
- **Majority (Janitor, Guru, Architect, Consistency):** Split — PrestigeAnimator owns visuals (camera focus, white flash, coin effect). PrestigeManager owns time_scale and phase state (the phase enum).
- **Minority (Newcomer):** Preferred single owner to avoid hidden coordination. Conceded that the split follows "signals up, calls down" and the project's separation-of-concerns pattern.

### Disagreement 3: 2D for coin effect (RESOLVED, unanimous)
All concede to Guru. 3D mesh scaling in orthographic camera is unreliable. Use `unproject_position()` → 2D ColorRect on CanvasLayer.

### Disagreement 4: time_scale floor + phase enum (RESOLVED, unanimous)
Both positions are compatible. Use phase enum AND enforce 0.05-0.1 floor. Phase enum lives in PrestigeManager.

## Final Consensus

1. **Prestige Screen is a full scene**, transitioned via SceneManager
2. **Split ownership**: PrestigeAnimator for visuals, PrestigeManager for time_scale + phase state
3. **2D CanvasLayer** for coin-fills-screen effect using `unproject_position()`
4. **Phase enum** (`PrestigePhase`) in PrestigeManager: SLOW_MO, FREEZE, EXPAND, TRANSITION
5. **time_scale floor** of ~0.05, never 0.0
6. **Prediction in PlinkoBoard** — new method checks if landing will trigger prestige
7. **SceneManager** gets `instant` parameter on `set_new_scene()`
8. **Replace existing PrestigeDialog** with new Prestige Screen scene
9. All animation timing values in ThemeProvider/VisualTheme
10. Camera work through BoardManager, lerp-tracking in `_process` during slow-mo
