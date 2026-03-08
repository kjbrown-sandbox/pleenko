# CLAUDE.md

## Developer Context

- I am an experienced programmer but brand new to Godot. I have no prior knowledge of Godot-specific concepts, APIs, functions, node types, signals, or documentation.
- When explaining Godot concepts, provide clear explanations rather than assuming familiarity.
- The developer is rebuilding this project from scratch to learn Godot hands-on. Provide guidance and explain approaches rather than writing large blocks of code unless asked.

## Guidelines

- When I propose a feature or approach, validate it against Godot best practices and game industry conventions before implementing. If my suggestion conflicts with established patterns, flag it and explain the recommended alternative.
- Prefer idiomatic Godot solutions (e.g., using signals over polling, scene composition over deep inheritance, built-in nodes over custom reimplementations).

## Game Description

This is an incremental/idle Plinko game. The player operates an ever-growing Plinko machine. Coins are dropped from the top and land in slots at the bottom. Each slot grants a different reward. As the player progresses, the Plinko machine expands with more pegs, slots, and reward types.

### Art Style

This is a minimalist 3D game. Use simple primitive shapes (spheres, cylinders, boxes) — no complex meshes or high-poly models. Keep visuals clean and lightweight.

### Core Physics Approach

Do NOT use a real physics engine for coin movement. The game needs to scale to tens of thousands of coins, so all coin paths are simulated/predetermined. The pegs are purely visual. This keeps performance stable regardless of coin volume.

Coins should calculate their path **row by row**, not all at once. This way if the board changes mid-drop (e.g., rows added), the coin dynamically adapts to the new layout and always lands in the correct bucket position. The coin picks left/right randomly at each row, queries the board for the next waypoint, and determines its final bucket value at landing time.

## Architecture (Rewrite Reference)

The prototype had nearly all logic in a single 2200-line `main.gd`. The rewrite should follow Godot's scene composition pattern with separated responsibilities.

### Recommended File Structure

```
scripts/
  game_manager.gd          # Thin orchestrator — wires signals between systems
  currency/
    currency_manager.gd     # All currency state, add/spend/check, caps
  boards/
    plinko_board.gd         # Board visuals, peg/bucket rendering, coin spawning
    board_manager.gd        # Multi-board creation, selection, camera, positioning
  coins/
    coin.gd                 # Coin animation (row-by-row waypoint resolution)
    drop_manager.gd         # Queues, cooldown timers, autodroppers
  progression/
    level_manager.gd        # XP, thresholds, level-up rewards, unlock gating
    upgrade_manager.gd      # Upgrade definitions, costs, caps, buy logic
  persistence/
    save_manager.gd         # Save/load/quicksave serialization
  ui/
    ui.gd                   # HUD, currency displays, upgrade panel, dialogs
```

### Key Godot Patterns to Follow

- **Signals up, calls down.** Children emit signals to notify parents. Parents call methods on children to command them. Never the reverse.
- **Autoloads (singletons)** for managers that need global access: CurrencyManager, LevelManager, SaveManager. Register these in Project > Project Settings > Autoload.
- **Resources for data.** Upgrade definitions (cost, cap, scaling formula) should be Resource subclasses or data dictionaries, not hardcoded if/else chains. One generic `buy(upgrade_id)` function replaces many individual upgrade functions.
- **Each node manages its own children.** The board builds its own pegs/buckets. The UI builds its own buttons. The drop manager owns its own timers.
- **Scenes are self-contained.** Each `.tscn` + `.gd` pair handles its own initialization, state, and cleanup.

### System Responsibilities

**CurrencyManager (Autoload)**

- Owns all balances: gold, unrefined orange, orange, unrefined red, red
- Owns all caps and cap upgrade costs
- Methods: add(), spend(), can_afford(), get_balance()
- Emits: currency_changed(type, new_amount, max_amount)
- UI listens directly to currency_changed — no manual update calls needed

**BoardManager**

- Creates/destroys board instances (gold, orange, red)
- Handles board positioning and spacing
- Manages board selection and camera tweening
- Keyboard navigation between boards

**PlinkoBoard**

- Builds pegs and buckets procedurally based on num_rows
- Spawns coins via drop_coin()
- Exposes methods for coins to query: get_peg_position(row, col), get_bucket_position(col), get_bucket_value(col), get_bucket_type(col)
- Emits: coin_landed(value, bucket_type)
- Shares mesh resources (peg_mesh, bucket_mesh, materials) across instances

**Coin**

- Receives board reference and starting info on spawn
- Animates row by row: picks left/right, asks board for next waypoint
- Determines bucket value at landing time (not drop time)
- Emits: landed(bucket_value) then queue_free()

**DropManager**

- Owns per-board queues and cooldown timers
- Owns autodropper pool and assignment
- Handles queue drainage on timer callbacks
- Methods: request_drop(board_type), add_to_queue(board_type, multiplier)

**LevelManager**

- Owns player_level and XP tracking
- Defines level thresholds and rewards
- Emits: level_changed(new_level), level_up(level, rewards)
- Gates feature unlocks (shop, upgrades, boards) behind levels

**UpgradeManager**

- Stores upgrade definitions as data (not code branches)
- Each upgrade: id, display_name, cost_formula, max_level, cap_raise_currency, effect
- Methods: buy(upgrade_id), can_buy(upgrade_id), get_upgrades_for_board(board_type)
- Talks to CurrencyManager to spend, emits upgrade_purchased(id, new_level)

**SaveManager**

- Queries other managers for serializable state
- Writes/reads JSON to user:// path
- Auto-save timer (30 seconds)
- Quicksave/quickload support

### Three-Currency Economy

| Currency         | Earned On                       | Used For                                          |
| ---------------- | ------------------------------- | ------------------------------------------------- |
| Gold             | Gold board buckets              | Gold board upgrades                               |
| Unrefined Orange | Gold board (orange buckets)     | Refined by dropping on gold board (3x multiplier) |
| Orange           | Orange board buckets            | Orange upgrades + raise gold upgrade caps         |
| Unrefined Red    | Gold/orange board (red buckets) | Refined by dropping (9x on gold, 3x on orange)    |
| Red              | Red board buckets               | Red upgrades + raise orange upgrade caps          |

### Board Progression Flow

1. Start with gold board (2 rows)
2. Add rows -> orange buckets appear at edges (requires ORANGE_ROW_GATE rows)
3. Earn unrefined orange -> orange board unlocks
4. Add rows to orange -> red buckets appear (requires RED_ROW_GATE rows on gold, ORANGE_ROW_GATE on orange)
5. Earn unrefined red -> red board unlocks

### Lessons from the Prototype

- **Coin paths must be dynamic.** The prototype pre-calculated all waypoints at drop time. When rows were added mid-drop, coins landed at stale positions. Row-by-row waypoint resolution fixes this.
- **Upgrade data should be data, not code.** The prototype had 42 separate upgrade handler functions. A data-driven approach (array of upgrade definitions) with one generic buy function is far more maintainable.
- **Cooldown timers per board.** Gold = 2s base, Orange = 4s base, Red = 8s base. Drop rate upgrades multiply by 0.8 per level.
- All queues can overfill during a level up
- **Shared mesh resources matter for performance.** Create CylinderMesh, BoxMesh, and materials once, reuse for all pegs/buckets. Don't instantiate new meshes per peg.
- **Tween patterns.** Use create_tween() for fire-and-forget animations. Chain tween_property() calls for sequential movement. Use .set_ease(EASE_IN) + .set_trans(TRANS_QUAD) for gravity-like feel. End with tween_callback() for cleanup.
- **Node cleanup.** Always queue_free() nodes when done (coins after landing, old pegs/buckets on rebuild). Nodes that aren't freed are memory leaks.
- **Save format versioning.** Plan for save format changes from the start. The prototype had to handle migration of old gold_queue format (int vs array of multipliers).
