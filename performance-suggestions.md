# Performance Suggestions

## Profiler Findings (2026-04-04)

### Critical: FillBar UI Cascade

Profiled during autodrop with 19 coins dropping in one frame. Total frame time: ~123ms (target: 16.6ms for 60fps).

**Root cause:** Every `currency_changed` signal triggers a full UI refresh across all FillBars and UpgradeRows. 27 currency_changed signals in one frame causes:

| Function | Self Time | Calls | Per Call |
|---|---|---|---|
| `FillBar._update_corner_radii` | 68.29ms | 135 | 0.51ms |
| `FillBar.set_plus_filled` | 18.86ms | 324 | 0.06ms |
| `FillBar.apply_fill_colors` | 16.97ms | 543 | 0.03ms |

These 3 functions account for **84% of frame time** (104ms / 123ms).

**Why it's expensive:**
- `_update_corner_radii` costs 0.5ms per call — likely triggers Godot layout recalculation (StyleBox property changes, corner_radius modifications)
- Call counts are multiplied: 27 signals × 5 FillBars = 135 calls to `_update_corner_radii`
- `UpgradeRow._update_button` was called 378 times (27 signals × 14 upgrade rows)

**Suggested fixes:**
1. **Debounce UI updates.** Mark UI as dirty on `currency_changed`, defer the actual update to end of frame so 27 signals = 1 update instead of 27:
   ```gdscript
   var _dirty := false

   func _on_currency_changed(_type, _amount, _max) -> void:
       if not _dirty:
           _dirty = true
           _update_all_cap_buttons.call_deferred()

   func _update_all_cap_buttons() -> void:
       _dirty = false
       # ... actual update logic
   ```
2. **Batch spends.** Accumulate total cost for multiple coin drops and call `spend()` once instead of per-coin.
3. **Investigate `_update_corner_radii`.** At 0.5ms per call it's the single most expensive function. May be possible to optimize or avoid calling it on every currency change.

### Other Notable Costs

| Function | Self Time | Calls | Notes |
|---|---|---|---|
| `CoinQueue.enqueue` | 6.09ms | 19 | ~0.32ms per coin enqueue |
| `Coin._apply_visuals` | 5.12ms | 19 | ~0.27ms per coin visual setup |
| `FillBar.set_fill` | 1.61ms | 570 | Low per-call but very high call count |

---

## General Optimization Opportunities

### Rendering: MultiMeshInstance3D
Currently drawing 901 objects with 420 draw calls (from Monitors tab). MultiMeshInstance3D would batch identical meshes (coins, pegs, buckets) into single draw calls. This is the biggest rendering optimization available — can take thousands of individual mesh nodes down to a handful of draw calls.

### Rendering: Unshaded Materials
For a minimalist art style, `unshaded` materials skip all lighting calculations. Use where lighting isn't needed.

### Processing: Object Pooling
Instead of `queue_free()` + instantiate for every coin, keep a pool of deactivated coins and reuse them. Avoids node creation/destruction overhead at high coin volumes.

### Processing: Disable Processing on Static Nodes
Pegs and buckets don't move. Ensure they have `set_process(false)` and `set_physics_process(false)` so Godot skips them in the process loop.

### Node Count
At 90 seconds of play: 1,429 nodes, 9,288 objects. Watch if node count grows over time — if it climbs continuously, coins or other nodes aren't being freed. Orphan nodes were 0 at time of measurement (good).

### Memory
Static memory at ~104 MiB, video memory at ~137 MiB. Both normal for a simple 3D game. No concerns currently.

### Cache Frequent Lookups
Profiler showed these called hundreds of times per frame:
- `VisualTheme.resolve()` — 543 calls/frame. Returns constant colors from a match statement. Pre-cache as variables.
- `TierRegistry.get_next_tier()` — 567 calls/frame. Dictionary lookup, fast per-call but adds up.
- `TierRegistry.get_tier()` — 479 calls/frame.
- `TierRegistry.primary_currency()` — 387 calls/frame. Called multiple times in the same function (e.g., UpgradeRow._update_button calls it twice).

Cache these at the call site — store the result in a variable during setup or once per frame instead of re-querying every time.

### Typed Arrays
`var coins: Array[Coin] = []` is faster to iterate than untyped `var coins = []` because Godot skips runtime type checking per element.

### Cache Node References
Avoid `get_node()` / `$Path` / `get_node_or_null()` inside frequently-called functions. Store the reference in a variable during `_ready()`.

### Visibility-Based Processing
If multiple boards exist but only one is on screen, disable processing and hide off-screen boards entirely. Use `is_visible_in_tree()` to toggle processing on/off as the camera moves.

### Pre-Create StyleBoxes Instead of Modifying Properties
`_update_corner_radii` modifies StyleBox properties at runtime which triggers layout recalculation. Pre-create a StyleBox for each state (joined/unjoined) and swap between them instead.

---

## Codebase Scan Findings (2026-04-04)

### FillBar._update_corner_radii — Why It's So Expensive

**File:** `entities/fill_bar/fill_bar.gd:316-330`

The function modifies 8+ StyleBox `corner_radius` properties across `_main_styles`, `_plus_styles`, and `_minus_styles` arrays. Each property change can trigger Godot's layout system to recalculate. Called from `show_plus_button()` and `show_minus_button()`, which are called from `CoinValues._update_all_cap_buttons()` on every `currency_changed` signal.

**Fix:** Guard with a visibility-changed check — only call `_update_corner_radii` if the button visibility actually changed:
```gdscript
func show_plus_button(show: bool) -> void:
    if plus_button.visible == show:
        return  # No change, skip expensive work
    plus_button.visible = show
    _update_corner_radii()
```

### currency_changed Signal — Full Cascade Map

`CurrencyManager.currency_changed` is connected to **9+ handlers**, all firing on every coin drop:

| Handler | File | What It Does |
|---|---|---|
| `CoinValues._on_currency_changed` | `entities/main/coin_values.gd:28` | Loops ALL currencies, updates ALL bars, calls show_plus_button on each |
| `UpgradeRow._on_currency_changed` | `entities/upgrade_row/upgrade_row.gd:29` | Calls `_update_button()` with TierRegistry lookups (×14 rows = 378 calls) |
| `DropButton._on_currency_changed` | `entities/drop_section/drop_button.gd:27` | Loops all required currencies to check affordability |
| `PlinkoBoard._on_currency_changed` | `entities/plinko_board/plinko_board.gd:78` | Checks advanced bucket unlock |
| `BoardManager._on_currency_changed` | `entities/board_manager/board_manager.gd:36` | Loops all tiers checking unlock conditions |
| `LevelProgressBar._on_currency_changed` | `entities/level_progress_bar/level_progress_bar.gd:42` | Updates display text (triggers label layout) |
| `LevelManager._on_currency_changed` | `autoloads/level_manager/level_manager.gd:24` | Checks level-up conditions |
| `UpgradeManager._on_currency_changed` | `autoloads/upgrade_manager/upgrade_manager.gd:46` | **Does nothing — dead connection** |
| `ChallengeTracker._on_currency_changed` | `autoloads/challenge_manager/challenge_tracker.gd` | Tracks challenge progress |

### Dead Signal Connection

**File:** `autoloads/upgrade_manager/upgrade_manager.gd:46`

`UpgradeManager._on_currency_changed` is connected to `currency_changed` but the handler does nothing. Free CPU cycles by removing it.

### CoinValues._update_all_cap_buttons — Unnecessary Looping

**File:** `entities/main/coin_values.gd:162-171`

Loops ALL visible currencies on every `currency_changed`, calling `show_plus_button()` → `_update_corner_radii()` on each. The plus button visibility rarely changes — it depends on `UpgradeManager.is_cap_raise_available()`, which only changes on upgrade purchases, not coin drops.

**Fix:** Only update cap buttons when upgrade state changes, not on every currency change.

### apply_fill_colors — Redundant Theme Overrides

**File:** `entities/fill_bar/fill_bar.gd:195-207`

Calls `t.resolve()` and `add_theme_color_override()` every time, even when the color hasn't changed. `add_theme_color_override()` is a Godot engine call that may trigger redraws.

**Fix:** Track the current state and skip if unchanged:
```gdscript
var _last_disabled_state: bool = false
func apply_fill_colors(is_disabled: bool, at_max: bool = false) -> void:
    var new_state := is_disabled or at_max
    if new_state == _last_disabled_state:
        return
    _last_disabled_state = new_state
    # ... actual color update
```

### BoardManager._on_currency_changed — Loop Instead of Lookup

**File:** `entities/board_manager/board_manager.gd:129-140`

Loops through all tiers on every `currency_changed` to find which tier uses that currency type. Should use a reverse lookup map (`CurrencyType → TierData`) in TierRegistry for O(1) access.

### DropButton._on_currency_changed — Checks All Currencies

**File:** `entities/drop_section/drop_button.gd:86-94`

Loops all required currencies on every `currency_changed`. Could early-exit by only checking the specific currency type that changed, since it's passed as a parameter.

### Coin — Uncached get_node_or_null Calls

**File:** `entities/coin/coin.gd:25,56,62,68`

`_apply_visuals()`, `get_color()`, and `set_color()` all call `get_node_or_null("MeshInstance3D")` separately. Should cache the reference in `_ready()`.

### LevelProgressBar — Updates Text on Every Currency Change

**File:** `entities/level_progress_bar/level_progress_bar.gd:51-68`

Rebuilds the label text string and calls `update_text()` on every `currency_changed`, even when the displayed value hasn't changed. String formatting + label text assignment triggers layout recalculation.

**Fix:** Compare new text to current text before assigning.
