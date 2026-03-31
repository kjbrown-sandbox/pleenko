# Codebase Audit Findings

Five agents analyzed this codebase from different perspectives. This document consolidates all findings.

---

## Table of Contents

1. [The Janitor — Code Cleanliness](#1-the-janitor--code-cleanliness)
2. [The Godot Guru — Best Practices](#2-the-godot-guru--best-practices)
3. [The Architect — Dependencies & Connections](#3-the-architect--dependencies--connections)
4. [The Newcomer — Readability & Clarity](#4-the-newcomer--readability--clarity)
5. [Cross-Agent Priority Summary](#5-cross-agent-priority-summary)
6. [The Consistency Lover — Standardization Audit](#6-the-consistency-lover--standardization-audit)

---

## 1. The Janitor — Code Cleanliness

### 1.1 Duplicate Code

**1.1.1 Duplicate Objective Text Generation (HIGH)**
- **File:** `autoloads/challenge_manager/challenge_manager.gd` (~lines 411-439 and 489-517)
- `get_objective_text()` and `get_objective_text_for()` are nearly identical — ~60 lines of duplicated logic.
- **Fix:** Consolidate into a single method with a shared `_format_single_objective()` helper.

**1.1.2 Duplicate Constraint Text Generation (MEDIUM)**
- **File:** `autoloads/challenge_manager/challenge_manager.gd` (~lines 462-486)
- `get_constraint_text()` has inline text generation that could be pushed to individual constraint classes (e.g., `NeverMoreThanXCoins.get_text()`).

**1.1.3 Duplicate Tooltip/Hover Setup (LOW)**
- **Files:** `entities/icon/icon.gd` (lines 26-32), `entities/nav_arrow/nav_arrow.gd` (lines 36-42)
- Identical mouse_entered/exited hover logic (pulse + shader color update).
- **Fix:** Extract to a shared utility or base class for interactive icon elements.

**1.1.4 Duplicate Label Creation Pattern (MEDIUM)**
- **Files:** `entities/main/main.gd` (lines 266-293), `entities/plinko_board/plinko_board.gd` (lines 131-146), `entities/challenge_info_panel/challenge_info_panel.gd` (lines 108-137)
- Same label theme override boilerplate repeated 3+ times.
- **Fix:** Create a `ThemeProvider.create_styled_label(text, color, size) -> Label` utility.

### 1.2 Oversized Files

**1.2.1 challenge_manager.gd — 550 lines (MEDIUM)**
- Handles: state management, objective tracking, objective validation, constraint checking, text generation, board rebuilding logic, autodropper setup, signal connections/disconnections.
- **Fix:** Split into `challenge_manager.gd` (state/setup/signals), `challenge_validator.gd` (objective/constraint checking), and `challenge_text_generator.gd` (all text generation). Or push formatting to objective/constraint classes themselves.

**1.2.2 plinko_board.gd — 557 lines (LOW, monitor)**
- Large but cohesive. Approaching refactor threshold.

**1.2.3 visual_theme.gd — 376 lines (LOW)**
- Monolithic but expected for a theme system.

### 1.3 Dead Code

**1.3.1** `entities/drop_section/drop_button.gd` line 23 — `_autodropper_controls_visible` is set but never read. Remove it.

**1.3.2** `entities/coin_queue/coin_queue.gd` line 11 — Commented-out `@export var coin_rotation`. Remove it.

**1.3.3** `entities/challenges_menu/challenges_menu.gd` line 9 — `const MainScene` preloaded but only used in one challenge handler; other handlers are commented out. Indicates incomplete feature or stubs.

**1.3.4** `autoloads/scene_manager/scene_manager.gd` — Contains commented-out signal definitions and incomplete signal. Clean up or complete.

### 1.4 Clutter / Verbose Code

**1.4.1 Excessive Inline Lambdas in main.gd (LOW)**
- Lines 249-263: Multiple inline lambda connections. Extract to named `_on_*` methods for consistency.

**1.4.2 Repeated Variable Capture in upgrade_section.gd (LOW)**
- Lines 65-82: Same variables captured three times in nested closures. Works but verbose.

### 1.5 Improvement Opportunities

**1.5.1 Signal Disconnection Boilerplate (LOW)**
- `challenge_manager.gd` lines 537-548: Manual `is_connected` / `disconnect` repeated 5+ times.
- **Fix:** Wrapper utility or Godot 4.2+ disconnection features.

**1.5.2 Inline String Formatting for Enums (LOW)**
- Multiple places do `Enums.CurrencyType.keys()[x].to_lower().replace("_", " ")`.
- **Fix:** Add `Enums.currency_name_pretty(type)` helper.

---

## 2. The Godot Guru — Best Practices

### 2.1 Critical Issues

**2.1.1 SceneManager Creates Orphaned Nodes (CRITICAL)**
- **File:** `autoloads/scene_manager/scene_manager.gd`
- CanvasLayer is added as child of SceneManager (an autoload), not root. It persists after scene transitions and accumulates — memory leak and z-ordering issues.
- **Fix:** Add canvas_layer to `get_tree().root` instead of `self`. Ensure `queue_free()` is called on canvas_layer, not just overlay.

**2.1.2 CoinQueue Timer Leak (CRITICAL)**
- **File:** `entities/coin_queue/coin_queue.gd`
- `get_tree().create_timer()` creates Timer nodes not explicitly freed. Lambda captures `coin` by reference — if coin is freed before timer fires, crash risk. Orphaned timers accumulate.
- **Fix:** Replace with tweens (lifecycle-managed by owner node):
  ```gdscript
  var tween: Tween = create_tween()
  tween.set_delay(i * 0.1)
  tween.tween_property(coin, "position", target, slide_time)
  ```

### 2.2 Important Issues

**2.2.1 Coin Reaches Up to Call Board Methods (IMPORTANT)**
- **File:** `entities/coin/coin.gd`
- `board.on_coin_landed(self)` violates "Signals Up, Calls Down" pattern.
- **Fix:** Coin emits `signal coin_landed(coin)`, board connects to it at spawn time.

**2.2.2 PlinkoBoard Multi-Drop Timer Leaks (IMPORTANT)**
- **File:** `entities/plinko_board/plinko_board.gd`
- Same `get_tree().create_timer()` leak pattern as CoinQueue for staggered multi-drops.
- **Fix:** Use tweens or store timer references.

**2.2.3 CoinQueue Reparenting Not Safe (IMPORTANT)**
- **Files:** `entities/coin_queue/coin_queue.gd`, `entities/plinko_board/plinko_board.gd`
- Coin is briefly parentless between `dequeue()` (removes child) and `add_child()` (re-parents). If interrupted, coin is orphaned.
- **Fix:** `transfer_coin_to(target)` method that handles removal and re-parenting atomically.

**2.2.4 Unnecessary _process() Fill Updates (IMPORTANT)**
- **File:** `entities/plinko_board/plinko_board.gd`
- `_update_drop_fill()` called every frame when `is_waiting`. Only needs update when fill percentage actually changes (>1% delta).
- **Fix:** Track `_last_displayed_fill` and skip updates below threshold.

**2.2.5 Tweens Not Stored (IMPORTANT, affects many files)**
- **Files:** `coin.gd`, `bucket.gd`, `plinko_board.gd`, others
- Tweens created without stored references. Can't check state or kill them on cleanup.
- **Fix:** Store tween in `var _tween: Tween`, kill previous before creating new, kill in `_exit_tree()`.

**2.2.6 Dependency Initialization Order (IMPORTANT)**
- **File:** `entities/main/main.gd`
- `board_manager.setup()` queries `TierRegistry`, `PrestigeManager`, etc. Assumes autoloads are ready. Generally safe (autoloads init first), but fragile.
- **Fix:** Add explicit assertion checks or `await get_tree().process_frame` at start of `_ready()`.

### 2.3 Nice-to-Have

**2.3.1 Shader Material Created Per-Bucket (NICE-TO-HAVE)**
- **File:** `entities/bucket/bucket.gd`
- `mark_forbidden()` creates new ShaderMaterial per bucket. Identical materials should be shared/cached.

**2.3.2 Deferred Calls Without Safety Checks (NICE-TO-HAVE)**
- **File:** `entities/plinko_board/plinko_board.gd`
- `_position_drop_hover.call_deferred()` could fire after board is freed. Add `if not is_node_ready(): return` guard.

**2.3.3 Missing _exit_tree() Handlers (NICE-TO-HAVE)**
- Most nodes don't implement `_exit_tree()` to clean up signal connections. Low risk since autoloads persist, but good hygiene.

### 2.4 Strengths Noted
- Excellent autoload hierarchy — clear responsibilities, no god objects.
- Strong type safety throughout — typed variables, return types, signal parameters.
- All input uses input actions, not hardcoded keys.
- Export variables well-organized with `@export_group`.

---

## 3. The Architect — Dependencies & Connections

### 3.1 Component Inventory

#### Autoloads (Singletons)
| Component | Responsibility |
|-----------|---------------|
| **CurrencyManager** | All currency balances, caps, cap-raise levels |
| **LevelManager** | Player level, XP, thresholds, level-up rewards |
| **UpgradeManager** | Upgrade state per board, purchase logic, costs, caps |
| **SaveManager** | Serialize/deserialize game state, autosave |
| **PrestigeManager** | Prestige counts per board, multi-drop bonuses |
| **ChallengeManager** | Active challenge state, objectives, constraints |
| **ChallengeProgressManager** | Challenge completion persistence, unlocks, starting modifiers |
| **TierRegistry** | Tier chain definitions, currency mappings, drop costs |
| **ModeManager** | MAIN vs CHALLENGES mode toggle |
| **ThemeProvider** | Visual theme — colors, fonts, meshes, timing constants |

#### Core Entities
| Component | Responsibility |
|-----------|---------------|
| **main.gd** | Root orchestrator, wires systems, input routing |
| **BoardManager** | Spawns/switches boards, camera, autodropper coordination |
| **PlinkoBoard** | Builds pegs/buckets, spawns coins, drop cooldown |
| **Coin** | Row-by-row fall animation, bounce, land |
| **Bucket** | Renders bucket, tracks hits, pulse on landing |

#### UI
| Component | Responsibility |
|-----------|---------------|
| **CoinValues** | Currency bars, cap-raise button UI |
| **LevelSection** | Level progress display |
| **LevelUpDialog** | Modal overlay for level-up rewards |
| **UpgradeSection** | Spawns upgrade rows on unlock |
| **ChallengeHUD** | Timer, objectives, progress during challenges |
| **ChallengeGroupingManager** | Challenge groups per tier, camera switching |

### 3.2 Signal Map

| Signal | Defined In | Listened By |
|--------|-----------|-------------|
| `currency_changed` | CurrencyManager | LevelManager, UpgradeManager, BoardManager, CoinValues, LevelSection, PlinkoBoard |
| `level_up_ready` | LevelManager | LevelUpDialog |
| `rewards_claimed` | LevelManager | UpgradeManager, BoardManager, PlinkoBoard |
| `level_changed` | LevelManager | LevelSection, MainHUD |
| `upgrade_purchased` | UpgradeManager | BoardManager |
| `upgrade_unlocked` | UpgradeManager | UpgradeSection |
| `cap_raise_unlocked` | UpgradeManager | CoinValues, UpgradeSection |
| `autodropper_unlocked` | UpgradeManager | BoardManager |
| `board_switched` | BoardManager | main.gd, ChallengeGroupingManager, ChallengeManager |
| `board_unlocked` | BoardManager | main.gd |
| `board_rebuilt` | PlinkoBoard | BoardManager, ChallengeManager |
| `coin_landed` | PlinkoBoard | ChallengeManager |
| `challenge_completed` | ChallengeManager | main.gd |
| `challenge_failed` | ChallengeManager | main.gd |
| `mode_changed` | ModeManager | main.gd |

#### Signals Defined But Never Emitted
- `PrestigeManager.prestige_triggered`
- `ThemeProvider.theme_changed`

#### Signals Emitted But Never Connected
- `ChallengeProgressManager.unlock_granted`

### 3.3 Autoload Dependency Web

```
CurrencyManager (leaf — no manager dependencies)
  ← LevelManager, UpgradeManager, PlinkoBoard, CoinValues

LevelManager (mid-layer)
  → CurrencyManager, TierRegistry
  ← PrestigeManager

UpgradeManager (mid-layer)
  → CurrencyManager, LevelManager, ChallengeManager

SaveManager (hub — serializes everything)
  → CurrencyManager, LevelManager, UpgradeManager, PrestigeManager,
    ChallengeProgressManager, BoardManager

BoardManager (hub — creates scenes)
  → CurrencyManager, UpgradeManager, PrestigeManager, LevelManager

PlinkoBoard (leaf entity)
  → CurrencyManager, LevelManager, UpgradeManager, ThemeProvider,
    ChallengeProgressManager, PrestigeManager

ChallengeManager (hub — gates systems)
  → CurrencyManager, UpgradeManager, BoardManager, TierRegistry
```

**Circular dependencies: NONE** — dependency graph is acyclic.

### 3.4 Scene Tree at Runtime

```
main.tscn (Main)
├── BoardManager (Node3D)
│   ├── PlinkoBoard [Gold]
│   │   ├── Pegs (dynamically populated)
│   │   ├── Buckets (dynamically populated)
│   │   ├── UpgradeSection (CanvasLayer)
│   │   │   └── UpgradeRows → UpgradeRow.tscn per unlock
│   │   ├── DropSection (CanvasLayer)
│   │   │   └── DropButtons → DropButton.tscn
│   │   └── CoinQueue (Node3D)
│   ├── PlinkoBoard [Orange, unlocked later]
│   └── PlinkoBoard [Red, unlocked later]
├── ChallengeGroupingManager (Node3D)
│   ├── ChallengeGrouping [Gold]
│   ├── ChallengeGrouping [Orange]
│   └── ChallengeGrouping [Red]
├── Camera3D
└── CanvasLayer (UI)
    ├── CoinValues
    ├── LevelSection
    ├── LevelUpDialog
    ├── ChallengeHUD
    ├── NavArrows (4x)
    └── OptionsIcon → OptionsDialog
```

### 3.5 Key Data Flow Paths

#### Coin Lands → UI Updates
```
Coin._bounce_or_despawn()
  → board.on_coin_landed(self)
    → CurrencyManager.add(bucket.currency_type, amount)
      → currency_changed.emit()
        ├→ LevelManager: check threshold → level_up_ready.emit()
        ├→ UpgradeManager: check raw currency → cap_raise_unlocked.emit()
        ├→ BoardManager: check unlock/prestige triggers
        ├→ CoinValues: update progress bars
        └→ LevelSection: update level progress
    → coin_landed.emit() → ChallengeManager (if challenge active)
```

#### Upgrade Purchase → Board Change
```
UpgradeRow._buy_upgrade()
  → UpgradeManager.buy()
    → CurrencyManager.spend() → currency_changed.emit()
    → upgrade_purchased.emit()
      → UpgradeSection applies effect:
        ├─ ADD_ROW → board.add_two_rows() → build_board() → board_rebuilt.emit()
        ├─ BUCKET_VALUE → board.increase_bucket_values() → build_board()
        ├─ DROP_RATE → board.decrease_drop_delay()
        ├─ QUEUE → board.increase_queue_capacity()
        └─ AUTODROPPER → level increment only
```

#### Challenge Completion → Save & Reload
```
ChallengeManager.challenge_completed.emit()
  → main._on_challenge_completed()
    → ChallengeProgressManager.complete_challenge()
    → SaveManager.save_challenge_progress()
    → SaveManager.reset_state() (resets Currency, Level, Upgrades)
    → get_tree().reload_current_scene()
```

### 3.6 "If I Change X, What Else Is Affected?"

| Change | Ripple Effect |
|--------|---------------|
| `CurrencyManager.add()` | 5 signal listeners (LevelManager, UpgradeManager, BoardManager, CoinValues, LevelSection) |
| `LevelManager.claim_rewards()` | 3 listeners (UpgradeManager, BoardManager, PlinkoBoard) |
| `UpgradeManager.buy()` | BoardManager (autodropper count), UpgradeSection (visual) |
| `PlinkoBoard.build_board()` | BoardManager (camera), ChallengeManager (objective visuals) |
| Add new Tier | TierRegistry → LevelManager rebuilds levels → UpgradeManager init → all drop costs recalculate |
| Add new Upgrade | Create BaseUpgradeData.tres → export in UpgradeManager → auto-appears on unlock |
| Add new Challenge | Create ChallengeData.tres → add button to ChallengeGrouping → appears in UI |
| Change theme colors | ThemeProvider → all nodes read in _ready() → recolor on next scene load |

### 3.7 Missing Connections (vs CLAUDE.md Plan)

**Partially Implemented:**
- **DropManager** — No standalone manager. Coin queuing is per-board (CoinQueue), drop timer is per-board. No global queue coordinator.
- **SceneManager** — File exists but unused. Scene transitions handled directly in main.gd.
- **MainMenu** — Scene exists but integration with game flow is unclear.

**Not Yet Implemented:**
- **Prestige UI Dialog** — PrestigeManager exists but no UI to claim prestige. `prestige_triggered` emitted but never shown.
- **Offline Calculator Integration** — Computed on reload only; no continuous background runner.

---

## 4. The Newcomer — Readability & Clarity

### 4.1 Naming Issues

**4.1.1 Inconsistent Private Variable Prefixes (HIGH)**
- Mix of `_private` and non-prefixed throughout. Example: `main.gd` has `_options_dialog` (underscore) alongside `challenges_down_icon` (no underscore via `@onready`). Unclear what's public vs internal.

**4.1.2 Cryptic Dictionary Keys (MEDIUM)**
- `challenge_manager.gd` lines 13-17: `_bucket_hits` uses magic string keys `"BoardType_BucketIndex"`. Should have a `_make_bucket_key()` helper.

**4.1.3 Ambiguous "gate" Naming (MEDIUM)**
- `upgrade_manager.gd` line 21, `board_manager.gd` line 19: `upgrade_gate` and `board_gate` are permission check callables, not gates. Better: `upgrade_permission_check`, `board_unlock_permission`.

**4.1.4 Magic Parameter `-1` for coin_type (MEDIUM)**
- `plinko_board.gd` line 162: `coin_type: int = -1` as "no override" is a C convention, not idiomatic Godot.

### 4.2 Missing Context / Undocumented Business Logic

**4.2.1 Multi-Drop Logic (HIGH)**
- `plinko_board.gd` lines 162-197: Why 0.15 second stagger? Why bypass cost for extra coins? Why queue-first then force-drop-later? No comments explaining game design decisions.
- **Needs:** Comment block explaining multi-drop mechanic.

**4.2.2 Prestige Bonus Rule Buried in Code (MEDIUM)**
- `prestige_manager.gd` lines 18-27: "Higher tiers grant multi-drop to lower tiers" is non-obvious business logic with no comment.
- **Needs:** Docstring explaining the rule and its implications.

**4.2.3 Offline Calculator is Opaque (HIGH)**
- `scripts/offline/offline_calculator.gd` (~150 lines): Massive static function, no explanation of 10-second batch algorithm, bucket layout derivation, or cap-based affordability logic.
- **Needs:** Top-level docstring explaining the simulation approach.

**4.2.4 Challenge Constraints Are Scattered (MEDIUM)**
- `challenge_manager.gd`: Currency constraints checked on `_on_currency_changed`, bucket constraints on coin land, drop limits on coin land — all in different methods. Hard to see all constraints at once.

**4.2.5 Level Thresholds Are Magic Numbers (MEDIUM)**
- `level_manager.gd` lines 3-4: `TIER_THRESHOLDS := [7, 13, 35, 55, 100, 150, 200, 300, 400, 500]` — what do these mean? Not documented.

### 4.3 Confusing Control Flow

**4.3.1 ChallengeManager Has Entangled State (HIGH)**
- Time-tracking state, bucket-hit tracking state, and goal-specific state are all flat variables on the class. State isn't grouped by objective. Example: `_survive_passed` set in `_on_time_up()` but checked in `_is_objective_met()` — non-obvious dependency.
- **Fix:** Inner class `ObjectiveState` to group per-objective tracking variables.

**4.3.2 SaveManager Has Multiple Deserialization Paths (MEDIUM)**
- `load_game()` and `load_prestige_only()` share JSON parsing with slightly different logic. Deserialization order is fragile and documented only in inline comments.
- **Fix:** Factor out JSON parsing; document or enforce deserialization order.

**4.3.3 Board Rebuild Cascades (MEDIUM)**
- `challenge_manager.gd` `_on_board_rebuilt()`: Re-marks all visual states when board rebuilds. Not documented as idempotent. Edge case if objective completes during rebuild.

### 4.4 Inconsistencies

**4.4.1 Signal Naming (LOW)**
- Most signals are past tense (`board_rebuilt`, `board_switched`) but some are future/present (`level_up_ready`). Minor but adds cognitive load.

**4.4.2 Callback Setup Patterns Vary (MEDIUM)**
- `plinko_board.gd` uses inline lambdas with `.connect()`. `upgrade_section.gd` passes callables to `setup()`. Different patterns for similar operations.

**4.4.3 Error Handling Inconsistent (LOW-MEDIUM)**
- `save_manager.gd` uses early `return false`. `currency_manager.gd` has silent failures. `upgrade_manager.gd` returns defaults for invalid inputs. No consistent approach.

**4.4.4 File-to-Class Naming Inconsistent (MEDIUM)**
- Some files have `class_name` (Bucket, Coin, BoardManager, DropButton). Others don't (coin_values.gd, challenge_hud.gd) and must be imported by full path.

### 4.5 Configuration & Constants

**4.5.1 Theme Provider is Opaque (MEDIUM)**
- `visual_theme.gd`: ~200+ flat configuration values with no grouping. Changing a value requires knowing all usage sites.
- **Fix:** Group related values into inner classes (BucketVisuals, CoinVisuals, etc.).

**4.5.2 Magic Numbers Without Constants (MEDIUM)**
- `plinko_board.gd` line 192: `i * 0.15` stagger timing — no named constant.
- `plinko_board.gd` line 9: `distance_for_advanced_buckets = 3` has a comment but should be a documented constant.

**4.5.3 Initialization Order is Implicit (MEDIUM)**
- `SaveManager.load_game()` lines 82-90: Deserialization order (Prestige → Level → Currency) is critical but only documented in inline comments. Not enforced systemically.

### 4.6 Confidence Assessment: Can a developer pick this up cold?

| Task | Confidence |
|------|-----------|
| Bug fix in UI/visual | HIGH |
| Add a new upgrade type | MEDIUM |
| Modify game balance | MEDIUM (need to find magic numbers) |
| Modify prestige system | LOW (logic buried, no tests) |
| Modify challenge objectives | MEDIUM-HIGH (pattern clear, state entangled) |
| Add offline feature | LOW (calculator is opaque) |

---

## 5. Cross-Agent Priority Summary

### Critical (Fix First)
| # | Issue | Source |
|---|-------|--------|
| 1 | SceneManager creates orphaned CanvasLayer nodes on autoload (memory leak) | Guru |
| 2 | CoinQueue timer leak — `get_tree().create_timer()` without cleanup | Guru |

### High Priority
| # | Issue | Source |
|---|-------|--------|
| 3 | Duplicate objective/constraint text generation (~60 lines) | Janitor |
| 4 | PlinkoBoard multi-drop timer leaks (same pattern as CoinQueue) | Guru |
| 5 | ChallengeManager entangled state — flat variables for different objectives | Newcomer |
| 6 | Offline calculator completely undocumented | Newcomer |
| 7 | Multi-drop business logic undocumented | Newcomer |
| 8 | challenge_manager.gd is 550 lines and should be split | Janitor |

### Medium Priority
| # | Issue | Source |
|---|-------|--------|
| 9 | Coin violates "signals up, calls down" — calls `board.on_coin_landed()` directly | Guru |
| 10 | CoinQueue reparenting not safe (coin briefly parentless) | Guru |
| 11 | Tweens not stored — can't kill on cleanup (affects many files) | Guru |
| 12 | Unnecessary per-frame `_update_drop_fill()` calls | Guru |
| 13 | Duplicate label creation boilerplate (3+ files) | Janitor |
| 14 | Initialization/deserialization order fragile and implicit | Newcomer |
| 15 | Callback setup patterns inconsistent (lambdas vs setup() callables) | Newcomer |
| 16 | Magic numbers without named constants | Newcomer |
| 17 | Ambiguous "gate" naming for permission check callables | Newcomer |
| 18 | Dictionary keys as magic strings in challenge tracking | Newcomer |
| 19 | File-to-class naming inconsistent (some have class_name, some don't) | Newcomer |
| 20 | Unused signals: `prestige_triggered`, `theme_changed`, `unlock_granted` | Architect |
| 21 | DropManager concept incomplete (no global queue coordinator) | Architect |
| 22 | SceneManager exists but unused — delete or implement | Architect |

### Low Priority / Polish
| # | Issue | Source |
|---|-------|--------|
| 23 | Dead code: `_autodropper_controls_visible`, commented-out `coin_rotation` | Janitor |
| 24 | Signal disconnection boilerplate in challenge_manager.gd | Janitor |
| 25 | Inline lambdas in main.gd should be named handlers | Janitor |
| 26 | Shader material created per-bucket instead of cached | Guru |
| 27 | Missing `_exit_tree()` cleanup handlers | Guru |
| 28 | Signal naming inconsistency (past vs future tense) | Newcomer |
| 29 | Theme provider values not grouped | Newcomer |
| 30 | Prestige UI dialog not yet implemented | Architect |
| 31 | Signal connection patterns inconsistent (3 different patterns) | Consistency |
| 32 | Array/Dictionary typing inconsistent (typed params vs comments vs untyped) | Consistency |
| 33 | `initialize()` vs `setup()` naming (1 file uses `initialize()`) | Consistency |
| 34 | Missing `-> void:` return type on `drop_button.gd` `_ready()` | Consistency |

---

## 6. The Consistency Lover — Standardization Audit

### 6.1 Type Annotations

**6.1.1 Return Types (LOW — 1 file)**
- `entities/drop_section/drop_button.gd` line 26: `func _ready():` missing `-> void:`.
- All other 23 files use `-> void:` on `_ready()`.
- **Standard:** Always include `-> void:`.

**6.1.2 Variable Type Annotations (MEDIUM — 5-10 files)**
- Most variables use full type annotations: `var x: int = 5`.
- Some Array/Dictionary declarations are untyped: `var _pending: Array = []` (level_manager.gd).
- **Standard:** Always use `Array[Type]` and `Dictionary[KeyType, ValueType]` syntax.

### 6.2 Signal Connection Patterns

Three distinct patterns found across the codebase:

| Pattern | Usage | Example |
|---------|-------|---------|
| **A: Direct method ref** | ~70% | `signal.connect(_on_signal_name)` |
| **B: Inline lambda** | ~25% | `signal.connect(func(): do_thing())` |
| **C: Callable with bind()** | ~5% | `signal.connect(_handler.bind(arg))` |

**Mixed-pattern files:**
- `level_up_dialog.gd` — uses both methods and lambdas
- `plinko_board.gd` — uses all three patterns
- `main.gd` — predominantly lambdas

**Standard:** Pattern A (direct method reference) for consistency. Pattern C (bind) when arguments needed. Avoid inline lambdas.

### 6.3 Initialization Patterns

| Pattern | Usage | Files |
|---------|-------|-------|
| `_ready()` only | ~70% | Most UI components |
| `_ready()` + external `setup()` | ~30% | BoardManager, PlinkoBoard, DropButton |

- No clear convention for when to use `setup()` vs relying solely on `_ready()`.
- **One file uses `initialize()` instead of `setup()`:** `challenge_grouping.gd` line 11.
- **Standard:** Use `setup()` everywhere. Reserve `_ready()` for self-contained init. Document when `setup()` is needed (external configuration after instantiation).

### 6.4 Array/Dictionary Typing

| Pattern | Usage | Example |
|---------|-------|---------|
| Fully typed | ~60% | `Dictionary[Enums.CurrencyType, int]` |
| Untyped + comments | ~35% | `Dictionary = {} # "key" -> int` |
| Completely untyped | ~5% | `Dictionary = {}` |

**Standard:** Use type parameters when possible. Fall back to comments only when types are too complex.

### 6.5 Node Referencing

Consistent — `@onready var node = $Path` is the standard (~80%). `get_node_or_null()` used appropriately for optional nodes (~5-10%). `%UniqueNode` syntax not used.

### 6.6 String Formatting

Consistent — `%` interpolation used in ~95% of cases. Minimal concatenation.

### 6.7 Signal Naming

- Past tense: `rewards_claimed`, `prestige_claimed`, `board_unlocked`, `challenge_completed`
- Present tense: `level_changed`, `mode_changed`, `theme_changed`
- Future/potential: `level_up_ready`
- **Standard:** Use past tense for all signals.

### 6.8 Null/Empty Checks

Consistent — `is_empty()` for collections (~70%), truthiness `if not x:` for nulls (~20%). Modern Godot patterns used correctly.

### 6.9 Method Naming

Consistent — `get_x()` for expensive operations, property access for cheap. `_on_signal_name()` for callbacks. `setup()` for external init (except `initialize()` in one file).

### 6.10 Preload vs Load

Consistent — `preload()` for `const` declarations, `load()` for runtime. All 19 preloads use `const`.

### 6.11 Comment Styles

Consistent — `##` for doc comments on public API, `#` for implementation. Comment density varies by file but intentionally (complex files get more comments).

### 6.12 Error Handling

- Silent `return` (~60%)
- `print("[Module]...")` logging (~35%)
- `bool` return values for important operations
- No assertions used anywhere
- **Standard:** Current approach is reasonable but could benefit from a consistent logging utility.

### 6.13 Standards to Adopt

1. Always include return type annotations (even `-> void:` on `_ready()`)
2. Use `Array[Type]` and `Dictionary[K, V]` syntax instead of untyped + comments
3. Standardize signal connections to direct method references; avoid inline lambdas
4. Document when to use `_ready()` only vs `setup()` + `_ready()`
5. Use past-tense signal names consistently
6. Rename `initialize()` to `setup()` in challenge_grouping.gd
