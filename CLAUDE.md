# CLAUDE.md

## Developer Context

- I am an experienced programmer but brand new to Godot. I have no prior knowledge of Godot-specific concepts, APIs, functions, node types, signals, or documentation.
- When explaining Godot concepts, provide clear explanations rather than assuming familiarity.
- The developer is rebuilding this project from scratch to learn Godot hands-on. Provide guidance and explain approaches rather than writing large blocks of code unless asked.

## Guidelines

- When I propose a feature or approach, validate it against Godot best practices and game industry conventions before implementing. If my suggestion conflicts with established patterns, flag it and explain the recommended alternative.
- Prefer idiomatic Godot solutions (e.g., using signals over polling, scene composition over deep inheritance, built-in nodes over custom reimplementations).
- When making modifications, make as many edits to the .tscn file as possible before relying on .gd for functionality.

## Game Description

This is an incremental/idle Plinko game. The player operates an ever-growing Plinko machine. Coins are dropped from the top and land in slots at the bottom. Each slot grants a different reward. As the player progresses, the Plinko machine expands with more pegs, slots, and reward types.

### Art Style

This is a minimalist 3D game. Use simple primitive shapes (spheres, cylinders, boxes) — no complex meshes or high-poly models. Keep visuals clean and lightweight.

### Core Physics Approach

Do NOT use a real physics engine for coin movement. The game needs to scale to tens of thousands of coins, so all coin paths are simulated/predetermined. The pegs are purely visual. This keeps performance stable regardless of coin volume.

Coins should calculate their path **row by row**, not all at once. This way if the board changes mid-drop (e.g., rows added), the coin dynamically adapts to the new layout and always lands in the correct bucket position. The coin picks left/right randomly at each row, queries the board for the next waypoint, and determines its final bucket value at landing time.

### Key Godot Patterns to Follow

- **Signals up, calls down.** Children emit signals to notify parents. Parents call methods on children to command them. Never the reverse.
- **Autoloads (singletons)** for managers that need global access: CurrencyManager, LevelManager, SaveManager. Register these in Project > Project Settings > Autoload.
- **Resources for data.** Upgrade definitions (cost, cap, scaling formula) should be Resource subclasses or data dictionaries, not hardcoded if/else chains. One generic `buy(upgrade_id)` function replaces many individual upgrade functions.
- **Each node manages its own children.** The board builds its own pegs/buckets. The UI builds its own buttons. The drop manager owns its own timers.
- **Scenes are self-contained.** Each `.tscn` + `.gd` pair handles its own initialization, state, and cleanup.

### System Responsibilities

> **Living documentation.** This section is the authoritative map of how systems own state, emit signals, and call into each other. It is kept in sync with the code — each time a feature branch is ready to merge to `main`, the relevant entries below are updated to reflect the new behavior, signals, data flows, and cross-system relations. New systems get new entries. Removed systems are deleted. The goal is that reading this section alone is enough to understand how the systems fit together without diving into the code.

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

## Feature Planning Process (Plan Mode Only)

When the user enters plan mode and describes a feature, run a multi-agent review before writing any code. Five personalities evaluate the feature in parallel, debate concerns in rounds, and produce a consensus plan.

### The Five Personalities

Each personality evaluates proposed features through their specific lens. They should raise concerns, propose alternatives, and flag risks — all oriented toward **future code that will be written**, not auditing existing code.

**1. The Janitor — Code Cleanliness**

- Will this feature introduce duplication with existing code?
- Can it reuse or extend something that already exists?
- Will it create oversized files or tangled responsibilities?
- Does the proposed structure keep things easy to clean up later?

**2. The Godot Guru — Engine Best Practices**

- Is this using the right Godot nodes, patterns, and APIs?
- Does it follow "signals up, calls down"?
- Are there performance concerns (node count, per-frame work, memory)?
- Is the lifecycle correct (ready, enter_tree, exit_tree, queue_free)?
- Are tweens, timers, and resources handled properly?

**3. The Architect — Dependencies & Connections**

- How does this feature connect to existing systems?
- What signals need to be added or modified?
- What's the ripple effect — if this changes, what else breaks?
- Does this introduce circular dependencies or tight coupling?
- Is the data flow clear and traceable?

**4. The Newcomer — Readability & Clarity**

- Will a developer picking this up cold understand what it does?
- Are there magic numbers, cryptic names, or undocumented business logic?
- Is the control flow straightforward or entangled?
- Are naming conventions consistent with the rest of the codebase?

**5. The Consistency Lover — Standardization**

- Does this follow established codebase patterns (signal naming, typing, init patterns)?
- Are connection patterns consistent (direct method refs, not inline lambdas)?
- Does it use the same error handling approach as similar code?
- Are type annotations, naming conventions, and file structure consistent?
- Are we using theme variables instead of new ones like Color.WHITE (which is wrong)?

### Process

1. **Parallel analysis:** Spin up all 5 agents simultaneously. Each receives the feature description and analyzes it through their lens.
2. **Round 1 — Concerns:** Collect all concerns from the 5 agents. Present a summary to the user showing each personality's key concerns.
3. **Round 2+ — Resolution:** If there are conflicts between agents, run another round where each agent sees the others' concerns and responds. Continue for up to 3 rounds. Do not ask the user to resolve disagreements during this process — let the agents work it out.
4. **Escalation:** If no consensus after 3 rounds, present the unresolved disagreements to the user for a decision.
5. **Approval:** Present the final plan to the user. Only begin implementation after explicit approval.

### Logging

All feature deliberations are logged to `agent-logs/<feature-name>.md` at the project root. Each log contains:

1. **Feature description** — what was proposed
2. **Round-by-round concerns** — each personality's input per round
3. **Disagreements** — where personalities conflicted
4. **Resolutions** — how conflicts were resolved (by consensus or user decision)
5. **Final plan** — the agreed-upon implementation approach

### When This Applies

This process runs **only when the user enters plan mode** for a new feature. It does not apply to:

- Simple bug fixes
- One-line tweaks
- Questions or explanations
- Work that doesn't involve plan mode

## Branch Workflow

### Plan Mode Creates a Branch

When the user enters plan mode for a feature, **create a new git branch** before any implementation begins:

1. **Branch naming:** Use `feature/<kebab-case-feature-name>` (e.g., `feature/juicy-prestige-animation`).
2. **Create the branch** from `main` after the plan is approved but before writing any code.
3. **All implementation work** for this feature happens on the feature branch.
4. **Commit regularly** on the feature branch as work progresses.

### Post-Implementation Review

After the user confirms the implementation looks good, run a **post-implementation review** using the same five personalities before merging to main. This mirrors the pre-implementation plan review but evaluates the actual code changes.

#### Process

1. **Collect the diff:** Run `git diff main...HEAD` to get all changes on the feature branch.
2. **Parallel review:** Spin up all 5 agents simultaneously. Each receives the full diff and reviews it through their lens:
   - **The Janitor** — Did the implementation introduce duplication, oversized files, or dead code? Is anything left behind that should be cleaned up?
   - **The Godot Guru** — Are Godot patterns correct in the actual code? Proper node lifecycle, signal usage, resource handling, performance?
   - **The Architect** — Do the actual connections match the plan? Any unplanned coupling, missing signal disconnections, or ripple effects?
   - **The Newcomer** — Is the implemented code readable? Magic numbers, unclear names, confusing control flow?
   - **The Consistency Lover** — Does the code match existing codebase patterns? Naming, typing, structure?
3. **Round 1 — Concerns:** Collect and present all concerns, noting which are blocking (must fix before merge) vs. advisory (nice to fix, not required).
4. **Round 2+ — Resolution:** Same multi-round debate as the planning phase. Agents see each other's concerns and resolve conflicts. Up to 3 rounds.
5. **Escalation:** Unresolved disagreements after 3 rounds go to the user.
6. **Fix:** Address all blocking concerns on the feature branch. Advisory concerns are listed but do not block the merge.
7. **Update living documentation:** Before merging, edit the "System Responsibilities" section of this `CLAUDE.md` so it reflects the state of the code on the branch. Scope of the edit:
   - For every system touched, update its ownership/methods/signals/data-flow bullets to match the actual implementation. If a signal was added, renamed, or removed, that change must appear here.
   - Add a new subsection for any new system (autoload, manager, resource, major scene) introduced by the branch.
   - Remove or rewrite subsections for systems that were deleted or fundamentally restructured.
   - Capture cross-system relations explicitly — "X emits foo_changed, which Y and Z listen to" is the kind of line that belongs here.
   - Prefer behavior over implementation detail: readers should come away understanding *what each system owns and how it talks to others*, not line-by-line specifics.

   Commit this documentation update as its own commit (e.g. `docs: update system responsibilities for <feature>`) so the living-docs change is easy to spot in history. If a branch made no meaningful system-level change, explicitly note that in the commit message rather than skipping the check.
8. **Merge:** Once all blocking concerns are resolved and the living docs are updated, merge the feature branch into `main` and delete the feature branch.

#### Logging

Post-implementation reviews are appended to the same `agent-logs/<feature-name>.md` file used during planning, under a `## Post-Implementation Review` heading. This keeps the full lifecycle — plan, concerns, implementation review, and merge — in one place.

#### When This Applies

The post-implementation review runs when:

- Work was done on a feature branch created through plan mode
- The user confirms the implementation is complete and ready for review

It does not run for:

- Work done directly on `main` (bug fixes, tweaks)
- Incomplete work (user hasn't confirmed it's ready)

## Final notes

The old code from the prototype can be found under `deprecated`. This was how things used to work.
