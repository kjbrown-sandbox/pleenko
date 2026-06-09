# CLAUDE.md

## Developer Context

- I am an experienced programmer but brand new to Godot. I have no prior knowledge of Godot-specific concepts, APIs, functions, node types, signals, or documentation.
- When explaining Godot concepts, provide clear explanations rather than assuming familiarity.
- The developer is rebuilding this project from scratch to learn Godot hands-on. Provide guidance and explain approaches rather than writing large blocks of code unless asked.

## Guidelines

- When I propose a feature or approach, validate it against Godot best practices and game industry conventions before implementing. If my suggestion conflicts with established patterns, flag it and explain the recommended alternative.
- Prefer idiomatic Godot solutions (e.g., using signals over polling, scene composition over deep inheritance, built-in nodes over custom reimplementations).
- When making modifications, make as many edits to the .tscn file as possible before relying on .gd for functionality.
- **Tests are a commit-time concern, not a mid-iteration concern.** The project has test infrastructure in `test/` using a custom `test_base.gd` runner (headless Godot scenes). Pure-logic functions and autoload methods can be tested in headless scenes. **Do not write tests during iteration** — they pollute the diff the user is trying to evaluate by ear/eye, and often have to be redone as the design shifts. Tests get added ONLY when the user signals the work is ready to ship (typically `/ship`, or an explicit "let's commit / let's add tests"). At that point, ensure tests exist for the files you modified — bug fixes and feature work alike. Other untested code in the diff is out of scope.

## Game Description

This is an incremental/idle Plinko game. The player operates an ever-growing Plinko machine. Coins are dropped from the top and land in slots at the bottom. Each slot grants a different reward. As the player progresses, the Plinko machine expands with more pegs, slots, and reward types.

### Art Style

This is a minimalist 3D game. Use simple primitive shapes (spheres, cylinders, boxes) — no complex meshes or high-poly models. Keep visuals clean and lightweight.

### Core Physics Approach

Do NOT use a real physics engine for coin movement. The game needs to scale to tens of thousands of coins, so all coin paths are simulated/predetermined. The pegs are purely visual. This keeps performance stable regardless of coin volume.

Coins should calculate their path **row by row**, not all at once. This way if the board changes mid-drop (e.g., rows added), the coin dynamically adapts to the new layout and always lands in the correct bucket position. The coin picks left/right randomly at each row, queries the board for the next waypoint, and determines its final bucket value at landing time.

**Invariant exception — voided columns.** Pegs are "purely visual" with exactly one carve-out: when a `BombHazard` detonates, the bucket's column is added to `PlinkoBoard._voided_columns` and the pegs along the strict vertical above it are scale-zeroed. Coins whose `next_lattice_cell` falls inside any voided column switch to a straight-fall and despawn off-screen (no bucket land, no currency credit, no burst). The coupling is column-indexed (`is_lattice_cell_voided(row, col)`), not peg-indexed — `Coin` never reads peg-mesh state, only asks the board whether the cell it's about to enter is voided.

### Key Godot Patterns to Follow

- **Signals up, calls down.** Children emit signals to notify parents. Parents call methods on children to command them. Never the reverse.
- **Autoloads (singletons)** for managers that need global access: CurrencyManager, LevelManager, SaveManager. Register these in Project > Project Settings > Autoload.
- **Resources for data.** Upgrade definitions (cost, cap, scaling formula) should be Resource subclasses or data dictionaries, not hardcoded if/else chains. One generic `buy(upgrade_id)` function replaces many individual upgrade functions.
- **Each node manages its own children.** The board builds its own pegs/buckets. The UI builds its own buttons. The drop manager owns its own timers.
- **Scenes are self-contained.** Each `.tscn` + `.gd` pair handles its own initialization, state, and cleanup.

### System Responsibilities

> **Living documentation — scope is deliberately narrow.** This is ONLY (1) a
> system map (who owns what state, what signals exist, who depends on whom) and
> (2) a ledger of non-obvious decisions/invariants ("why X, not Y" — things NOT
> derivable from reading the code). It is NOT a per-method behavior reference:
> do not add bullets that restate mechanics the code already shows. The code is
> the source of truth for *what* it does; this section exists for *why* and
> *how it connects*. Method-level prose goes stale fast and is re-read from
> source anyway — keep entries to ownership/signals + invariants, terse.
>
> **When to edit this section: only at post-implementation review (step 7 of
> the Branch Workflow below), NEVER mid-iteration.** Designs shift while the
> user is testing by ear/eye; updating the map before the design has settled
> means the doc has to be redone, and the churn pollutes the diff the user is
> evaluating. Wait until the user has confirmed the implementation is ready
> for review, then update in a separate commit.

#### Project layout

- `autoloads/` — singleton managers. One subdirectory per autoload.
- `entities/` — scenes (`.tscn` + `.gd` pairs). Each is self-contained.
- `scripts/` — shared data classes, utilities (enums, reward/tier data, format utils, offline earnings, `lattice.gd` Galton-lattice geometry).
- `style_lab/` — `VisualTheme` resource, presets under `style_lab/presets/*.tres`, plus the in-editor style lab scene.
- `assets/` — icons, sounds, fonts.

Autoload init order is set in `project.godot` and matters: `TierRegistry → CurrencyManager → UpgradeManager → LevelManager → PrestigeManager → SaveManager → SceneManager → ChallengeManager → ThemeProvider → ModeManager → ChallengeProgressManager → OnboardingProgress → AudioManager → PerformanceSettings`. Later autoloads may subscribe to earlier ones in `_ready`.

#### Autoloads

**TierRegistry** — `autoloads/tier_registry/tier_registry.gd`

- Pure data lookup over the ordered tier chain (gold, orange, red, ...). No mutable state, no signals.
- Consumed by nearly every manager for per-board currency, drop costs, tier indices.

**CurrencyManager** — `autoloads/currency_manager/currency_manager.gd`

- Owns balances + caps for all currencies.
- Emits: `currency_changed(type, new_balance, new_cap)` on every mutation.
- LevelManager, UpgradeManager (cap-raise unlocks), and ChallengeTracker listen.

**UpgradeManager** — `autoloads/upgrade_manager/upgrade_manager.gd`

- Owns per-board, per-upgrade state (level, cost, delta, caps, unlocked flag).
- `upgrade_gate: Callable` — optional gate set by `ChallengeManager` to block purchases during a challenge.
- Emits: `upgrade_purchased`, `upgrade_unlocked`, `cap_raise_unlocked`, `autodropper_unlocked`, `advanced_autodropper_unlocked`.
- Listens: `LevelManager.rewards_claimed` (unlock from level rewards), `CurrencyManager.currency_changed` (flip cap-raise availability when raw currency is first earned).

**LevelManager** — `autoloads/level_manager/level_manager.gd`

- Owns `current_level` and the level table (thresholds, messages, rewards per slot). Level table is rebuilt per tier based on `TierRegistry` + `PrestigeManager` unlock state.
- **Gold-only slot swap:** on the gold board, slot 3 unlocks the special upgrade (Autodropper) and slot 4 unlocks Queue — the reverse of every other board (queue-then-special). `_set_queue_slot` / `_set_special_slot` are the two arms; the swap is purely which slot index gets which, so `ensure_state_for_level` reconciliation (content-driven, not index-driven) heals existing saves regardless of order.
- Emits: `level_changed`, `level_up_ready` (VFX layer listens), `rewards_claimed(level, rewards: Array[RewardData])`.
- Listens: `CurrencyManager.currency_changed` (threshold crossings).

**PrestigeManager** — `autoloads/prestige_manager/prestige_manager.gd`

- Owns per-board prestige counts (0 = locked, ≥1 = permanently unlocked) and the current `PrestigePhase` (NONE, SLOW_MO, FREEZE, EXPAND, TRANSITION) which sets `Engine.time_scale`.
- Emits: `prestige_triggered`, `prestige_claimed`, `prestige_phase_changed`.
- `reset()` — full wipe of prestige counts + time scale, used only by `SaveManager.full_reset()`. Deliberately signal-free (no listeners exist on the main menu where the wipe runs); separate from the prestige flow, which preserves counts.
- Reads `ThemeProvider.theme` inside `enter_phase` for time-scale values. BoardManager queries multi-drop; LevelManager checks unlock state when rebuilding the level table.

**SaveManager** — `autoloads/save_manager/save_manager.gd`

- Orchestrates save/load to `user://save.json`. No signals. `SAVE_VERSION = 6`.
- Deserialization order (strict): `PrestigeManager → ChallengeProgressManager → OnboardingProgress → LevelManager → CurrencyManager → UpgradeManager → BoardManager`. Order matters so signals fire against fully-initialized state.
- `_migrate(data, version)` runs sequential version upgrades. v4→v5 seeds `OnboardingProgress` peeked-boards from the existing `boards.board_types` so existing players don't see peeks for things they already unlocked. v5→v6 seeds `OnboardingProgress.autodropper_intro_seen = true` for any save with `boards.normal_autodroppers_unlocked = true`, so existing players don't see the first-time autodropper animation replay on load.
- All reset variants funnel through `_wipe_save(extra_blocks)`: delete the save, rewrite a minimal save (`version` + `_device_prefs()`) merged with `extra_blocks`, then `reset_state()`. `_device_prefs()` is the single source of truth for the surviving device preferences — audio (`audio_muted`, `master_volume`, `vfx_settings`) and `max_fps` + `window_mode` (`PerformanceSettings`).
- `reset_game` / `reset_game_without_reload` pass `_persistent_progress_blocks()` (prestige + challenges + onboarding) so that state survives a prestige reset; `reset_game` also reloads the scene.
- `full_reset()` — the main-menu "Reset Game" path. Passes NO progress blocks (true fresh start: prestige/challenges/onboarding all wiped), and first calls `PrestigeManager.reset()` / `ChallengeProgressManager.reset()` / `OnboardingProgress.full_reset()` *before* the wipe so the clear order matches the documented load order. No scene reload — runs from the menu, which shows no save-derived state. Only `_device_prefs()` survive.
- `reset_state()` resets the runtime managers only (currency/level/upgrades, autosave off, board ref cleared); it does not preserve or reload anything — those are the callers' jobs.
- Calls `OfflineCalculator` (`scripts/offline/`) to credit earnings accumulated since last save. Offline credits are gated per-currency: a non-starting-tier currency only accrues if its board appears in `state["prestige"]` with count > 0 — preserves the first-time prestige beat for raw currencies the player has never organically earned.

**SceneManager** — `autoloads/scene_manager/scene_manager.gd`

- Thin scene-transition helper. `set_new_scene(packed_scene, instant)` — optional 1s fade overlay.

**ChallengeManager** — `autoloads/challenge_manager/challenge_manager.gd` (+ child `ChallengeTracker`)

- Lifecycle manager for active challenges. Owns `is_active_challenge`, the current `ChallengeData`, and a child `ChallengeTracker` node that runs live tracking.
- Emits: `challenge_completed`, `challenge_failed(reason)`, `challenge_state_changed` (AudioManager listens), `tick(seconds_remaining)` (per integer second from the tracker — AudioManager and ChallengeClock listen).
- Challenge start flow: caller calls `set_challenge`, then `ThemeProvider.set_theme(CHALLENGE)`, then `get_tree().reload_current_scene()`. After reload, `Main._setup_challenge` calls `ChallengeManager.setup(board_manager)` which creates the tracker.
- `setup(board_manager)` installs `upgrade_gate` on `UpgradeManager` and `board_gate` on `BoardManager`; `clear_challenge` removes them. After starting conditions are applied (boards built), it calls `get_active_board().seed_first_peg_deflector()` so a player who owns a deflector slot starts the challenge with one on the active board's top peg (no-ops when no slot is available).

**ChallengeTracker** (child of ChallengeManager) — `autoloads/challenge_manager/challenge_tracker.gd`

- Runs one challenge: tracks coin landings, checks constraints and objectives, decrements `time_remaining`. Emits `tick` per integer second. Handles two-phase Survive objectives (WAITING → SURVIVING; activates autodroppers at transition).
- Listens: per-board `coin_landed`, `coin_dropped`, `autodrop_failed`; `BoardManager.board_switched`; `CurrencyManager.currency_changed`.
- Hazards: `setup_hazards()` instantiates a `ChallengeHazardRuntime` per authored `ChallengeHazard` and parents it to the tracker, so `_process` ticks and `queue_free` cascade through for free. `_on_coin_landed` forwards to each runtime in order. Hazard-triggered failure routes through `hazard_fail(reason)` so the single `failed` signal stays the one source of truth. `disconnect_all` tears runtimes down before the existing board-disconnect path.

**ChallengeHazard / ChallengeHazardRuntime** — `autoloads/challenge_manager/challenge_hazard.gd` (+ `hazards/*.gd` subclasses)

- `ChallengeHazard extends Resource` is the new sibling of objective/constraint/starting-condition, holding authored data; `create_runtime()` returns a `ChallengeHazardRuntime extends Node` per-challenge live instance. Subclasses today: `ForbiddenBucketHazard` (migrated from the legacy `NeverTouchBucket` constraint — same UID `dusuom0lv25os` preserved so existing `.tres` files resolve), `BombHazard` (wandering bomb with countdown).
- Runtime callable seams (PeekAnimator precedent): `rng_fn`, `get_reachable_buckets_fn`, `fail_challenge_fn`, `void_column_fn` — defaulted in `setup()` but injectable for headless tests. Direct board calls (`mark_bucket_bomb`, `set_bomb_countdown`, etc.) are `if board:` guarded so a null `_board_manager` lets the runtime no-op visual side effects, which is what the unit tests do.
- BombHazardRuntime is the canonical wandering hazard pattern: per-bomb `{bucket_index, time_remaining, last_int_second}` entries; tick decrements time; on integer-second boundary the countdown label updates; on zero the column is voided + bomb repicks; on `coin_landed` matching a live bomb the bomb defuses (multiplier applied on the board side via `mark_bucket_bomb(idx, multiplier)` → `get_active_bomb_multiplier` in `finalize_coin_landing` — mirrors the gameplay-target multiplier path so both wandering systems flow through one code site).
- `_try_repick` filters `get_reachable_buckets_fn` against other live bomb buckets so bombs never overlap and never spawn in a voided column. `WanderingBucketSelector.pick` is the shared "pick a target, never the current one" helper — also used by `PlinkoBoard._pick_new_gameplay_target` so the two wandering systems can't drift apart.

**ThemeProvider** — `autoloads/theme_provider/theme_provider.gd`

- Owns the active `VisualTheme` resource. Swaps `normal_theme ↔ challenge_theme` via `set_theme(kind)`. Configures the shared `WorldEnvironment` and (optionally) a `DirectionalLight3D` based on `theme.unshaded`.
- Emits: `theme_changed`. AudioManager reads `theme.audio_style` to route arcade audio; PrestigeManager reads theme fields for prestige time-scale values; every Bucket/Coin/Peg reads colors/materials on setup.

**ModeManager** — `autoloads/mode_manager/mode_manager.gd`

- Tracks `MAIN` vs `CHALLENGES` mode. Emits `mode_changed(new_mode)`. `are_challenges_unlocked` queries `PrestigeManager`.
- `pending_challenges_menu: bool` — one-shot intent flag. Set when a challenge ends; survives the scene reload (autoload), consumed once by `Main._ready` to switch back into the challenge menu instead of the board.

**ChallengeProgressManager** — `autoloads/challenge_progress/challenge_progress_manager.gd`

- Persistent state for challenge completion, unlock flags, starting modifiers, permanent upgrades. Survives a prestige reset (alongside PrestigeManager).
- Emits: `challenge_state_changed(id, state)`, `unlock_granted(unlock_type)`. Read by `PlinkoBoard.setup` to apply per-board bonus multipliers and permanent upgrade levels.
- `reset()` — full wipe of all challenge state, used only by `SaveManager.full_reset()`. Unlike `deserialize()` (which deliberately does NOT clear `_unlocks`, to merge with newer in-memory state), `reset()` DOES clear `_unlocks` — a full reset is a true fresh start, not a merge.
- `challenges_ever_visited: bool` — flipped to `true` the first time the player manually enters challenges mode (read by `Main._update_nav_arrow_blinks` to stop the down-arrow blink; peek-driven mode switches do NOT flip this flag, see `PeekAnimator`).
- `get_gold_coin_speed_boost_count()` — counts `GOLD_COIN_SPEED_BOOST` starting modifiers (board-agnostic, gold-only by design). Read by `Coin.start()` to scale fall-speed; the per-grant magnitude lives on `Coin.COIN_SPEED_BOOST_PER_UNLOCK`.
- `get_queue_rate_bonus_count()` — counts `QUEUE_RATE_BONUS` starting modifiers (board-agnostic count, gold-only by design — same shape as the speed-boost counter). Read by `PlinkoBoard.setup` (via `_queue_rate_bonus_for_board`) to raise the gold board's per-queued-coin drop-rate bonus; the per-grant magnitude lives on `PlinkoBoard.QUEUE_RATE_BONUS_PER_UNLOCK`.
- `ChallengeRewardData.ModifierType` is **append-only** — it is serialized by ordinal with no save-version guard, so reordering/inserting values silently corrupts existing saves.

**OnboardingProgress** — `autoloads/onboarding_progress/onboarding_progress.gd`

- Persistent first-time-UX flags: `_peeked_boards: Dictionary` (BoardType → bool), `_peeked_challenges: bool`, and `_autodropper_intro_seen: bool`. All survive a prestige reset (`SaveManager.reset_game` and `reset_game_without_reload` preserve the serialized blob; `reset()` itself does not clear these).
- API: `has_peeked_board(type)`, `mark_board_peeked(type)`, `has_peeked_challenges()`, `mark_challenges_peeked()`, `has_seen_autodropper_intro()`, `mark_autodropper_intro_seen()`. No signals — pure data.
- `reset()` clears only the peek flags (prestige-preserving partial); `full_reset()` calls `reset()` then ALSO clears the permanent UX flags (autodropper/deflector intro etc.) for a true fresh start — used only by `SaveManager.full_reset()`.
- Read by `PeekAnimator` to decide whether to peek a newly-unlocked target. Read by `BoardManager._on_upgrade_purchased` to decide whether to fire the first-autodropper intro signal. Save migration v4→v5 pre-seeds peeked-boards; v5→v6 pre-seeds `autodropper_intro_seen` from existing autodropper-unlocked saves.

**AudioManager** — `autoloads/audio_manager/audio_manager.gd`

- Owns every sound in the game: procedural harp (long-decay variant for prestige), arcade square-wave + kick, ambient pads, drone pool (bucket drones + sparkles), bucket/coin chimes, click sounds.
- Owns the beat grid and per-board harmonic progression. `AudioStyle` resources can swap in alternate progressions/timbres (currently used for arcade challenges).
- Emits: `chord_changed(chord_index)` on every chord advance — visual-only signal (audio is not faded by chord change). `PlinkoBoard` listens to fade buckets back to their faded color.
- Listens: `ThemeProvider.theme_changed`, `ChallengeManager.challenge_state_changed` (re-select AudioStyle), `ChallengeManager.tick` (phase-lock beat grid + arcade kick), `PrestigeManager.prestige_phase_changed`.
- Chord-gated bucket drones: drones live in three states (ACTIVE, LINGERING, SPARKLE). On chord advance, ACTIVE drones flip to LINGERING and ring out via the synthesized tail; new coins fade lingering drones over `linger_fade_duration`. Per-coin-type voice caps (5 normal / 3 advanced) routed through a dedicated `Drones` bus with compressor + small-room reverb. Per-voice attenuation is filtered by coin type — co-tuned with compressor params.
- Activation rate-limit `try_consume_bucket_activation(is_advanced)` is per-coin-type with a one-shot `HARMONY_GRACE_WINDOW` for multi-drop two-note chords. Visual `mark_active` is intentionally coupled to this gate — rate-limited hits leave the bucket faded so the next tone-producing coin owns the activation.
- Prestige audio: on SLOW_MO entry, `_prestige_silencing` flag suppresses bucket plays + fades drones/ambient. At contact, `play_prestige()` plays a bass note + bell, then drives an ascending I maj7 arpeggio at 0.125s intervals. Arcade-specific: kick is the only audible backing layer; peg sparkle audio is currently disabled (peg ring VFX still fires).
- AudioStyle transitions fade all drones over 1s so worlds don't bleed.
- `get_chord_phase()` / `get_chord_duration()` drive Bucket's chord-synced scale pulse — all active buckets read the same global phase for visual sync.

**PerformanceSettings** — `autoloads/performance_settings/performance_settings.gd`

- Owns the player's display/performance preferences — frame-rate cap and window mode. No signals (pure data + apply).
- `FPS_OPTIONS = [30, 60, 120, 144]`, `DEFAULT_MAX_FPS = 120`. `set_max_fps(fps)` snaps unknown/stale values to the default (never uncapped), sets `Engine.max_fps`, and disables V-Sync so the cap is authoritative on every display (skipped under the headless driver). Applied on `_ready` and on every change.
- `WINDOW_MODE_OPTIONS = [Window.MODE_WINDOWED, Window.MODE_FULLSCREEN]`, `DEFAULT_WINDOW_MODE = Window.MODE_FULLSCREEN`. `set_window_mode(mode)` snaps unknown values to the default (same defensive pattern as `set_max_fps`) and writes `get_window().mode`. The window-mode apply is additionally gated on `not OS.has_feature("web")` — the browser Fullscreen API needs a real user gesture, so a startup-applied saved preference would silently fail; `OptionsDialog` hides the Display row on web for the same reason (the saved value sits dormant until the player returns to desktop).
- Persisted by `SaveManager` as `max_fps` + `window_mode`; treated as device preferences like audio — preserved across prestige resets (live in the minimal save like the audio prefs). `OptionsDialog`'s PERFORMANCE section drives them live; persistence rides the normal save cycle (same as master volume).

#### Scene-level systems

**BoardManager** — `entities/board_manager/board_manager.gd`

- Orchestrates all `PlinkoBoard` instances. Owns `_boards[]`, `_active_index`, autodropper pool + assignments, camera tweening, autodropper timer.
- Emits: `board_switched(board)`, `board_unlocked(type)`, `first_autodropper_purchased` (fired exactly once per player on the very first autodropper purchase, gated by `OnboardingProgress.has_seen_autodropper_intro` and suppressed in challenge mode — `AutodropperIntroAnimator` listens).
- Add-rows camera choreography: listens to per-board `row_upgrade_starting` (sets `_row_upgrade_camera_active = true` so the default `board_rebuilt` fit-tween is suppressed) and `row_upgrade_sweep_started(start_local_x, end_local_x, focus_local_y, sweep_duration)` (drives a three-phase `_camera_tween`: zoom in toward the start bucket → track horizontally with the wavefront → settle to the new fit framing). Track duration is floored at `row_upgrade_camera_min_track_duration` so first-purchase small boards don't whip, and extended by `row_upgrade_camera_track_extension` so the camera lingers before returning to centre. Flag is cleared in the final tween callback via `_clear_row_upgrade_camera_flag()`.
- Public API: `get_active_board()`, `get_active_index()`, `get_boards()`, `switch_board(index)`, `unlock_board(type)`, `reveal_autodropper_controls()` (called by `AutodropperIntroAnimator` when the intro animation completes; shows the +/– drop-button controls and refreshes button displays), `begin_cinematic_camera()` / `end_cinematic_camera()` (a transient cinematic — `CapRaiseRevealAnimator` — borrows the camera: `begin` kills the in-flight `_camera_tween` and raises `_cinematic_camera_active` to suppress the `board_rebuilt` fit-tween, `end` clears it and re-fits; mirrors the `_row_upgrade_camera_active` pattern).
- `camera_tween_duration: float` is public and can be borrowed temporarily by `PeekAnimator` to slow tweens for the peek; `_tween_camera_to_active_board` stores `_camera_tween` and kills any prior in-flight tween before creating a new one so rapid switches (manual + peek out-and-back) don't fight over the camera.
- Per-tick: `_autodrop_timer` (1.5s) calls `AudioManager.notify_autodropper_beat(wait_time)` to sync the beat grid, then dispatches to assigned boards.
- Listens: `UpgradeManager.{autodropper_unlocked, advanced_autodropper_unlocked, upgrade_purchased}`, `CurrencyManager.currency_changed`, `LevelManager.rewards_claimed`, per-board `board_rebuilt` / `autodropper_adjust_requested` / `coin_queue.count_changed` (refresh drop-button subtext when the queue rate bonus shifts the effective delay).
- Drop-button subtext reads `PlinkoBoard.get_effective_drop_delay()` so the displayed `Xs` reflects the current queue bonus.

**PlinkoBoard** — `entities/plinko_board/plinko_board.gd`

- Per-board gameplay: peg + bucket multimesh rendering, coin spawning, drop queue, drop timer, per-board upgrade multipliers, bucket marking API for challenges.
- Emits: `coin_dropped`, `coin_landed(board_type, bucket_index, currency_type, amount, multiplier)`, `board_rebuilt`, `autodropper_adjust_requested`, `prestige_coin_landed`, `cap_raise_coin_landed(coin, predicted_bucket)` (final-bounce start of the coin that first earns a raw currency post-prestige — `CapRaiseRevealAnimator` listens; mutually exclusive with `prestige_coin_landed` via `_will_reveal_cap_raise` / `_will_trigger_prestige`), `autodrop_failed(board_type)`, `row_upgrade_starting`, `row_upgrade_sweep_started(start_local_x, end_local_x, focus_local_y, sweep_duration)`, `bomb_spawned(board_type, bucket_index, seconds)` / `bomb_defused(board_type, bucket_index, multiplier)` / `bomb_detonated(board_type, bucket_index)` / `column_voided(board_type, bucket_index)` (bomb-hazard lifecycle; BombHazardRuntime listens to itself via its own state machine, audio + future VFX can subscribe externally).
- Owns `_voided_columns: PackedInt32Array` (bucket indices whose strict vertical was destroyed by `void_column(idx)`) and `_active_bomb_multipliers: Dictionary` (bucket_index → defuse multiplier set by `mark_bucket_bomb(idx, multiplier)`, consumed in `finalize_coin_landing` next to the gameplay-target multiplier path). `_voided_columns` is cleared in `build_board()` — voids are per-challenge runtime state, not persistent.
- Add-rows juice: `add_two_rows(animated := true)` is the player-purchase entry point (UpgradeSection passes default `true`; `ChallengeManager._apply_starting_conditions` passes `false` so challenge setup just rebuilds with no animation). The animated path emits `row_upgrade_starting` *before* `build_board()` so BoardManager can suppress the default fit-tween in time, then runs `_play_row_upgrade_glissando`: the pure scheduler `_compute_row_upgrade_schedule` returns per-column drop times + new-peg reveal indices; the cascade lifts every bucket up by `2*vertical_spacing` (the OLD row height) and snap-hides the two new edge buckets at indices 0 and `num_buckets-1` (positions that didn't exist on the previous row); each column step then plunges + bounces (`Bucket.fall_to_rest`), sings (`Bucket.mark_singing`), fires `AudioManager.force_play_bucket` with `degree = column index` for an ascending diatonic glissando, reveals that column's new pegs (MultiMesh per-instance transform restore), and (for the two edges only) calls `Bucket.fade_in`. Reuses `_upgrade_animating` + `_upgrade_ripple_tween` shared with the bucket-value ripple, so `build_board()`'s kill-on-rebuild handles re-trigger mid-animation for free. All tunables live in `VisualTheme` under the VFX group (`row_upgrade_*`).
- Listens: `AudioManager.chord_changed` — fades all buckets to faded color on every chord advance. `coin_queue.count_changed` — rescales the active drop timer proportionally and refreshes the bonus label.
- On coin land: `AudioManager.request_bucket_play` + `on_coin_landed`. Singing is suppressed while `_upgrade_animating` is true (the upgrade ripple owns the arpeggio).
- Owns a `CoinBurstField` child (created once in the MultiMesh-init path, persists across rebuilds like the drop-burst MM). `finalize_coin_landing` calls `_coin_burst_field.spawn(coin.global_position, theme.get_coin_color(coin.coin_type))` for non-prestige coins only, just before `queue_free` — prestige coins skip both (PrestigeAnimator owns their lifecycle).
- On peg contact: `flash_nearest_peg` calls `AudioManager.should_sparkle` (gates the ring VFX in coin color); flash + halo + pulse always fire.
- Bucket value upgrade ripple: `increase_bucket_values` updates buckets in-place with a center-outward arpeggio at `BUCKET_WAIT / 2` intervals via `force_play_bucket`, instead of rebuilding the board.
- Queue capacity: the pure static `_queue_capacity_for_level(level)` is the single source of truth — `0` until the first level is owned, then `level + 1` (first purchase grants 2 slots). Applied at all three `coin_queue.set_capacity` sites (`setup`, `apply_saved_state`, `increase_queue_capacity`); the last recomputes from the live `UpgradeManager` level (committed by `buy()` before the call) + permanent challenge level rather than blind `+1`.
- Queue rate bonus: `get_effective_drop_delay()` returns `drop_delay / (1 + _queue_rate_bonus_per_coin * coin_queue.count)` — additive in rate, never reaches zero. `_queue_rate_bonus_per_coin` is cached in `setup()` via the pure `_queue_rate_bonus_for_board(type)`: base `QUEUE_RATE_BONUS_PER_COIN` for every board, plus `ChallengeProgressManager.get_queue_rate_bonus_count() * QUEUE_RATE_BONUS_PER_UNLOCK` on the gold board only (mirrors the `GOLD_COIN_SPEED_BOOST` → `Coin` precedent; challenge progress only changes on scene reload so the cache can't go stale). `_start_drop_timer` and `decrease_drop_delay` track `_last_effective_delay` so a queue-size change mid-cycle rescales `_drop_timer_remaining` proportionally without losing accumulated progress.
- Per frame, `_update_queue_bonus_label_position` projects `coin_queue.global_position + coin_queue.start_position` to viewport space (using a cached `Camera3D`) and tells `DropSection` where to anchor its bonus label. Skipped when `drop_section.visible` is false.
- Lattice math (`position_x_for`, `cell_to_world`, `next_lattice_cell`, and the `vertical_spacing = space*√3/2` derivation) forwards to the shared pure `Lattice` module (`scripts/lattice.gd`) — single source of truth shared with `Coin` and the decorative `MenuBoard`, so they can't drift. Public signatures unchanged; `cell_to_world` passes the stored `vertical_spacing`/`COIN_ROW_Y_OFFSET` in (not recomputed). `style_lab.gd`'s editor-only re-derivations are deliberately deferred (`# TODO(Lattice)`).
- Deflectors: `_deflectors` (peg_index → ±1 dir) is the model; `DEFLECTOR_BASE_STRENGTH = 5` → bias `(s+1)/(s+2) = 6/7 ≈ 86%` (a 1:6 split — *encourage, never force*). Single source of truth: `resolve_bounce_direction` reads it live (bit-identical to the legacy 50/50 when no deflector — trajectory tests depend on this) and `UpgradeRow`'s "current odds" hover reads the static `deflector_bias_for_strength(s)`. `deflector_outcome(row, col, direction) -> DeflectorOutcome {NONE, FOLLOWED, MISSED}` is a pure RNG-free comparator over `_deflectors` (does NOT re-roll). `notify_deflector_resolved(row, col, direction)` is a pure-view event hook called DOWN by `Coin` that dispatches FOLLOWED/MISSED to `_deflector_editor.play_deflector_hit/miss`; safe no-op when no editor (bare test boards), never mutates the model, never saves.

**Coin** — `entities/coin/coin.gd`

- Individual coin animation. Picks left/right at each row, queries the board for the next waypoint, determines final bucket at landing time.
- Emits: `final_bounce_started(coin, predicted_bucket)` (triggers prestige handover), `landed`.
- `start()` caches `_fall_speed_multiplier` from `ChallengeProgressManager.get_gold_coin_speed_boost_count()` (gold coins only); reused by `_bounce_or_despawn()` so the autoload isn't queried per bounce. Per-grant magnitude is the local `COIN_SPEED_BOOST_PER_UNLOCK` constant — keep it in sync with any `data/challenges/*.tres` description that grants the reward, since `ChallengeInfoPanel` displays the description verbatim.
- `_bounce_or_despawn()`, after resolving the bounce direction and while `_row/_col` still point at the peg just struck (before reassignment), calls `board.notify_deflector_resolved(_row, _col, direction)` next to the existing `flash_nearest_peg` call — drives the deflector reaction VFX. Pure view, no gameplay effect; never reads `_deflectors` itself.

**Bucket** — `entities/bucket/bucket.gd`

- Per-bucket visual: `MeshInstance3D` with a per-instance `StandardMaterial3D`, `Label3D` showing value. No signals (pure view).
- Buckets always start in the faded color and only light up while activated. `mark_active` snaps to full main color, then schedules a tween that holds full color and fades to faded over `bucket_fade_duration` aligned with chord end. While active, `_process` reads `AudioManager.get_chord_phase()` and eases scale from `bucket_active_scale_peak` to 1.0 — uniform across all active buckets.
- `mark_inactive(duration)` is a backstop on chord change. All `mark_*` methods go through `_apply_color`/`_kill_color_tween`/`_stop_pulsing`. Both `mark_active` and `mark_inactive` no-op when `_is_hit` is true so challenge markers win.
- Visual activation is coupled to the audio rate-limit gate: `mark_active` only fires on accepted `try_consume_bucket_activation` calls (see AudioManager).
- Add-rows animation methods, owned by `PlinkoBoard`'s glissando: `lift_for_fall(offset)` snaps `position.y = _rest_y + offset` (pre-stages the new row at the OLD row height); `fall_to_rest(start_offset, overshoot, duration)` is the ball-under-gravity two-segment tween (TRANS_QUAD EASE_OUT plunge → TRANS_QUAD EASE_IN lift); `snap_invisible()` enables `TRANSPARENCY_ALPHA` and sets albedo + label alpha to 0; `fade_in(duration)` tweens alpha back to 1 (TRANS_SINE) and restores `TRANSPARENCY_DISABLED` at completion. Contract: **`_apply_color` preserves the current alpha** (only sets RGB) so colour-marking flows (`mark_singing`, etc.) don't clobber an in-flight fade.

**DeflectorEditor** — `entities/deflector_editor/deflector_editor.gd` (child of `PlinkoBoard`)

- Player-facing peg-deflector placement UI: pooled solid arrows (`_placed`, one per `_deflectors` key, re-bound by enumeration order on `refresh`), the hover placement preview (`_ghost_arrow`, peg colour @ 50% opacity via `_ghost_color`), and the screen-space remove-X. Emits `deflector_change_requested(peg_index, dir)` UP; everything else is called DOWN by PlinkoBoard/BoardManager/Main (`setup`, `refresh`, `set_active`, `set_input_allowed`, `set_capacity`). Signals up, calls down.
- Reaction VFX: `play_deflector_hit(peg_idx)` / `play_deflector_miss(peg_idx)` (called DOWN by `PlinkoBoard.notify_deflector_resolved`) route through `_start_reaction`, which snaps the pooled arrow to a colour and records `_active_reactions[peg_idx] = {elapsed, color, pulse, duration}`. `_process` eases the tint back to `peg_color` (and, when `pulse`, scales it up→back to 1.0 via `sin(k·π)`) — an allocation-free fade mirroring `PlinkoBoard.flash_nearest_peg`'s `_active_flashes` (no tween, no spawned nodes; `set_process` gated to only run while reactions are active). HIT = `theme.deflector_hit_color` (one neutral shade darker, default `BG_3`) + pulse over `deflector_hit_glow_duration`; MISS = `theme.deflector_miss_color` (`RED_MAIN`, no pulse) over `deflector_miss_fade_duration`. Gated by `theme.deflector_reaction_enabled`.
- `_placed_arrow_for(peg_idx)` is the single peg_idx → `_placed` slot resolver (recomputed each use, never cached, since `refresh` re-binds slots). `_clear_reactions()` snaps tracked arrows back to peg colour + scale 1.0 and is called wherever the pool is re-bound or re-materialised (`refresh` / `_apply_theme` / `set_active(false)` / `_exit_tree`) so a half-finished reaction can't stick on the wrong arrow. Pure view: no save, no model mutation.

**CoinBurstField** — `entities/coin_burst_field/coin_burst_field.{gd,tscn}` (`class_name CoinBurstField`, child of `PlinkoBoard`)

- Self-contained pooled downward particle spray on coin landing. Owns one `MultiMeshInstance3D` (reuses `drop_burst_multimesh.gdshader`), a fixed slot pool, and its own per-second emission cap — cost is bounded at any coin volume (the proven `drop_burst` mechanism). No signals: pure view, called DOWN via `spawn(world_pos, color)`.
- Invariants: motion is analytic (`position_at` kinematics + gravity, no physics engine per Core Physics); `_process` divides `delta` by `Engine.time_scale` so bursts run real-time during prestige slow-mo; the rate-limit timestamp is recorded only when ≥1 particle actually spawned (an exhausted-pool no-op must not suppress the next visible burst); colour comes per-coin from `get_coin_color(coin_type)` (the `coin_halo`/`drop_burst` precedent — deliberately NOT a Palette source). Static `seed_particle`/`position_at`/`alpha_at` + the slot pool are pure/RNG-injectable for headless tests; the only scene-tree-dependent side effects (MultiMesh writes) are null-guarded so the lifecycle bookkeeping is unit-testable. Theme config: `coin_burst_*`; suppressible via the `coin_burst` `AudioManager` VFX-override key.

**ChallengeClock** — `entities/challenge_clock/challenge_clock.gd` + `.tscn`

- White pie-slice countdown inside `ChallengeHUD`. Updates only on `ChallengeManager.tick` (discrete once-per-second steps — reinforces the audio kick). Hides on `challenge_completed`/`challenge_failed`.

**ChallengeHUD** — `entities/main/challenge_hud.gd` + nodes in `entities/main/main.tscn`

- Challenge UI container: timer label, objective label, progress label, result label, embedded `ChallengeClock`. Polls `ChallengeManager.get_time_remaining` + `get_objective_progress` per frame.

**MenuBoard** — `entities/menu_board/menu_board.{gd,tscn}` (`class_name MenuBoard`)

- Decorative, visual-only Plinko board behind the main menu; instanced by `main_menu.tscn`. Self-contained: reads `ThemeProvider.theme` + shared `Lattice` + calls `AudioManager.play_pitched_chime` for two audio layers (peg-contact ticks + background chord bed); emits nothing, no Currency/Save/Upgrade/BoardManager/`Coin` coupling, no buckets/rewards.
- Perspective `Camera3D` + `fov` are **authored in `menu_board.tscn`** (editor-tunable); code never writes the camera transform (only the menu-only `DirectionalLight3D` rotation/energy, since the gameplay theme is `unshaded`). Theme is read once in `_ready` — static for the node's lifetime by design (no `theme_changed` subscription).
- MultiMesh near-flat disc pegs with per-row alpha fade (vertex-colour albedo) + an elastic "jello" scale wobble on coin contact (`_peg_wobbles` per-peg dedupe). Lightweight `MeshInstance3D` coins spawned on a `Timer`, bounce row-by-row via `Lattice`, ride `COIN_ROW_Y_OFFSET` above the pegs (same Z plane → no parallax). Every Nth coin (`SPARKLE_EVERY_NTH_COIN`) flagged at spawn emits peg-ring sparkles on every peg it strikes — purely visual, no audio coupling. Rare per-bounce particle burst reusing a prebuilt shared mesh + the coin's shared material. All tweens tracked + killed in `_exit_tree` (SceneManager frees the menu mid-fade), and the `$ChimeBeatTimer` is also `stop()`-ed there; `_track_tween` prune is amortized. All visual tuning is local `MENU_*`/`PEG_*` consts (never the shared `VisualTheme` schema).
- **Two audio layers, independent in timing.** Both call `AudioManager.play_pitched_chime(pitch_mult, vol, sustain, instrument_type)`. Timing/cadence is decoupled (the peg layer fires on coin contact, the chord bed on its own `ChimeBeatTimer`), but the peg layer is now a **read-consumer** of the chord-bed sequencer's `_chord_index` / `_chime_pitches` so its pitches stay diatonic to the active chord.
  - **Peg-contact layer (`PegTick` glass-marble timbre, chord-aware pitch).** `_advance_coin_bounce` → `_try_play_peg_tick` on *every* peg strike of *every* coin. Rate-limited via `_peg_tick_next_time` with a per-hit random interval rolled in `[PEG_TICK_INTERVAL_MIN_S, MAX_S]`. Each accepted hit picks a random note from `_chime_pitches[_chord_index]` (the active chord) and shifts it by `PEG_TICK_PITCH_MULT` (= 4.0, two octaves up). The octave shift exists because `PegTick` is a pre-rendered noise burst with a fixed 2800 Hz resonance — at the chord's authored C3-B3 octave (pitch_mult ≈ 0.5) the sample stretches at half speed and loses its marble clink; +2 octaves lands it in the bright, in-character speed band AND moves the resonance closer to the actual chord pitch.
  - **Chord-bed layer (`MusicBox` via `CHIME_INSTRUMENT_TYPE` const).** `$ChimeBeatTimer` ticks `PEG_CHIME_BEAT_SECONDS` (0.5s) regardless of coin activity. Per-tick state: `_chord_index` walks `PEG_CHIME_PROGRESSION`, `_beat_index` walks `[0, PEG_CHIME_BEATS_PER_CHORD)`, `_loop_index` tracks completed progression cycles. Each chord's notes are authored *ascending*; even chord indices arpeggiate ascending, odd ones descending (direction emerges from index iteration). Crescendo/decrescendo: per-note volume scales with `note_idx` over `PEG_CHIME_DYNAMIC_RANGE_DB`.
  - **Layered reveal across loops.** Loop 0 = bare arpeggios. Loop 1+ adds `intro` accents on beat 0 (gated `_loop_index >= PEG_CHIME_INTRO_START_LOOP`). Loop 2+ adds `mid` grace notes on `PEG_CHIME_MID_BEAT` (gated `_loop_index >= PEG_CHIME_MID_START_LOOP`), producing the x-x- pattern across the chord.
  - **`PEG_CHIME_ENABLED` const** master toggle — false keeps the timer ticking + state advancing but no notes play; useful for A/B muting the bed while iterating.
- **No theme audio coupling.** `CHIME_INSTRUMENT_TYPE` is hardcoded (currently `MUSIC_BOX`), NOT read from `theme.bucket_instrument` — the menu chime is its own role, not a copy of the gameplay bucket sound.

**MenuTriangleField** — `entities/menu_triangle_field/menu_triangle_field.{gd,tscn}` (`class_name MenuTriangleField`)

- Pooled drifting-triangle backdrop, used by both `menu_board.tscn` (decorative menu backdrop) and `parallax_backdrop.tscn` (gameplay parallax cloud field). Fixed MultiMesh pool (count = hard cap), per-instance fade-in/hold/fade-out + drift + spin + recycle (no runtime alloc/free). 1-tri `ArrayMesh` + shared `drop_burst_multimesh.gdshader` with `render_priority = -1` so it always sorts behind the (also-transparent) pegs.
- Two coloring modes: default reads `ThemeProvider.theme.background_color` and picks a darken/lighten nudge (background-tinted greys). `use_theme_triangle_shades = true` lerps every triangle randomly between two palette colours picked **per-instance** via `triangle_light_source` / `triangle_dark_source` (`VisualTheme.Palette` enums, resolved through `theme.resolve(...)`). Sources are scene-level on purpose: menu and gameplay backdrop point at different "dark" entries (e.g. lofi's BG_HAZE vs BG_HAZE_SUBTLE) so the gameplay field can be gentler — cumulative ink is heavier with the larger spawn count and viewport.
- Per-triangle PEAK alpha is rolled at spawn in `[min_peak_alpha, max_peak_alpha]` (defaults 1.0/1.0 → no variation) and multiplied into the fade curve — currently unused by either scene; available for future per-instance tuning without code changes.
- All tunables that differ between menu and gameplay (count, sizes, drift speed, spawn zone, shade mode, peak-alpha range) are `@export` with menu defaults preserved; gameplay instance overrides them in `parallax_backdrop.tscn`. Pure static `spawn_rect_for` extracted for testability.

**ParallaxBackdrop** — `entities/parallax_backdrop/parallax_backdrop.{gd,tscn}` (`class_name ParallaxBackdrop`)

- Wrapper that lags behind the gameplay's **orthographic** camera to fake parallax (depth alone produces no parallax under ortho — this script does). Owns one `MenuTriangleField` child; signals up, calls down.
- `setup(camera)` is called DOWN from `Main._ready()` after `board_manager.setup(camera)`, then `_capture_rest` is `call_deferred` so it runs after `BoardManager._snap_camera_to_active_board`. Captures the wrapper's own authored `global_position` as `_anchor` (NOT the camera's position — propagating camera Z would push triangles in front of the pegs); captures camera XY + ortho `size` as the rest framing. `process_priority = 10` so per-frame transform writes happen AFTER `BoardManager`'s camera tween on the same frame.
- Each frame in `_process`: `global_position = parallax_offset(cam_pos, _rest_cam, _anchor, parallax_factor)` (XY lag by `(1 - factor)` of camera delta; Z pinned to `_anchor.z`) and `scale = parallax_scale(cam.size, _rest_size, zoom_factor)` on X/Y (Z=1) so the field grows subtly when the camera zooms out. Static helpers `parallax_offset` / `parallax_scale` are pure and unit-tested. Defaults: `parallax_factor = 0.20`, `zoom_factor = 0.5` (semantics deliberately invert: parallax_factor=0 → glued to camera; zoom_factor=0 → no zoom response).

**MainMenu** — `entities/main_menu/main_menu.gd` + `.tscn`

- App entry scene. Instances `MenuBoard` (decorative backdrop) + a themed title; styles all buttons + the reused confirm card from the palette (no raw colors) and adds the gameplay `Vignette`.
- Buttons: "Play" → `SceneManager.set_new_scene(main.tscn)`; Discord/Press Kit/Report-a-Bug → `OS.shell_open` placeholder URLs; "Quit" → `get_tree().quit()`; "Settings" → opens the reused `OptionsDialog` (MAIN_MENU context). Side-effecting actions go through injectable `_shell_open_fn`/`_quit_fn`/`_full_reset_fn` Callable seams (PeekAnimator precedent) for headless tests.
- Reset Game lives inside Settings: `OptionsDialog` emits `reset_requested` UP; MainMenu owns the reused palette-styled `ConfirmLayer` and calls `SaveManager.full_reset()` on confirm (no scene reload — menu shows no save-derived state). Cancel re-opens Settings.

**OptionsDialog** — `entities/options_dialog/options_dialog.gd`

- Reused by both the in-game gear menu and the main menu. `enum Context { IN_GAME, MAIN_MENU }` (default IN_GAME) must be set by the parent BEFORE `add_child` (the whole UI, incl. footer, builds in `_ready`). `_build_footer` branches: IN_GAME → "Return to Game / Return to Main Menu"; MAIN_MENU → "Reset Game" (emits `reset_requested`) + "Close", and deliberately does NOT construct the return button or reference `_on_return_pressed`/`MAIN_MENU_PATH` (in-game scene-nav is structurally unreachable from the menu, not just hidden). In-game caller `Main._setup_options_dialog` sets `IN_GAME` explicitly before `add_child`.

**Main** — `entities/main/main.gd`

- Root scene orchestrator. Wires up BoardManager, ChallengeHUD, dialogs, UI panels, prestige animator, peek animator. On `_ready` decides between `_setup_normal()` and `_setup_challenge()` based on `ChallengeManager.is_active_challenge`.
- Listens: `ModeManager.mode_changed`, `PrestigeManager.{prestige_claimed, prestige_phase_changed}`, `BoardManager.{board_switched, board_unlocked}`, `UpgradeManager.upgrade_unlocked`, `ChallengeManager.{challenge_completed, challenge_failed}`.
- `apply_input_lock(locked)` — called by `PeekAnimator` to toggle navigation input across BoardManager, ChallengeGroupingManager, Main's own `_input`, and the four nav-arrow buttons. Single chokepoint for "all navigation locked" (covers both peek and prestige).
- `_on_mode_changed` / `_on_board_switched` consult `peek_animator.is_peeking()` and skip the "mark visited / clear unseen" side effects when the switch is peek-driven — preserves the blink as a real signal of "you haven't been here yet."
- `is_loading_from_save()` accessor exposes `_loading_from_save` to `PeekAnimator` so it can suppress peek enqueues during deserialize.
- `_exit_challenge_to_menu()` — single teardown shared by `_on_challenge_completed`/`_on_challenge_failed`: sets `ModeManager.pending_challenges_menu`, `SaveManager.reset_state()`, reloads `main.tscn` (NORMAL). `_ready` then consumes the flag and calls `ModeManager.switch_to_challenges()` so the player lands back on the challenge selection menu.

**PeekAnimator** — `entities/main/peek_animator.gd`

- Child of Main (script-on-Node + child `LingerTimer`). Drives a brief auto-pan to a newly-unlocked navigation target (new board or challenges-first-unlocked), holds for `VisualTheme.peek_linger_duration`, then returns. Each transition uses `VisualTheme.peek_camera_tween_duration` (longer than normal so the move feels gentle); the challenges peek also waits `peek_pre_challenges_pause` before pulling the camera away.
- Listens: `BoardManager.board_unlocked` → enqueue peek; `PrestigeManager.prestige_phase_changed` → clear queue + stop timer on non-NONE so prestige owns the camera, drain on NONE.
- Public API: `setup(board_manager)`, `is_peeking()`, `is_input_locked()`, `queue_peeks_for_existing_unlocks()` (called by Main after `SaveManager.load_game` to catch unlocks from prior sessions), `set_drain_deferred(deferred)` (`CapRaiseRevealAnimator` holds the new-board peek queued-but-not-drained until its reveal finishes; releasing re-drains).
- Callable seams (`switch_board_fn`, `switch_to_challenges_fn`, `switch_to_main_fn`, `apply_input_lock_fn`, `loading_query`, `wait_fn`) — production defaults wire to BoardManager/ModeManager/Main; tests inject stubs to bypass camera tweens and `await`s.
- Suppresses peeks during active challenges, during deserialize, and for already-peeked targets. Marks `OnboardingProgress.mark_board_peeked` / `mark_challenges_peeked` after a peek completes and calls `SaveManager.save_game()`.
- Borrows BoardManager's and ChallengeGroupingManager's `camera_tween_duration` for the peek's duration; restores on exit (all early-returns are inside `_run_peek` so the restore at the bottom always runs).
- `LingerTimer` has `ignore_time_scale = true` so `Engine.time_scale` changes during prestige can't warp the linger.

**AutodropperIntroAnimator** — `entities/main/autodropper_intro_animator.gd`

- Child of Main (script-on-Node, wired in `Main._setup_normal()` only — challenges intentionally bypass the intro). Plays a one-time first-autodropper-purchase animation: sparkle particles burst from the autodropper upgrade row in `CoinValues` and swoop to the gold drop button, then `BoardManager.reveal_autodropper_controls()` is called to expose the +/– controls and the `+` button pulses (`VisualTheme.blink_scale_fade`) until the player's first click stops it.
- Listens: `BoardManager.first_autodropper_purchased`. No signals emitted.
- Reuses the `level_section.gd` particle pattern (`level_up_particle_count`, `level_up_particle_burst_duration`, `level_up_particle_swoop_duration` from `VisualTheme`). Particle overlay is parented to Main's `CanvasLayer` so it renders above the 3D scene.
- After particles arrive: calls `OnboardingProgress.mark_autodropper_intro_seen()` + `SaveManager.save_game()` so the intro never replays. A `_completed` re-entry guard makes the per-particle tween_callbacks idempotent.
- Reads `PlinkoBoard.get_drop_button_screen_center(bid)` (added for this feature) to find the screen-space target for the swoop tween — both the `CoinValues` upgrade row and the drop button are 2D Controls, so `get_global_rect().get_center()` is sufficient (no `unproject_position` needed).

**CapRaiseRevealAnimator** — `entities/main/cap_raise_reveal_animator.gd`

- Child of Main (wired in `Main._setup_normal()` only — challenges bypass it). Plays the once-per-board-tier "cap-raise reveal": when a coin first earns a raw currency *after* a prestige, borrows the camera for a gentle zoom + `Engine.time_scale` slow-mo on the falling coin, then a 2D particle stream swoops from the coin up to the HUD revealing each new max-cap "+" button (currency cap explodes → the new raw-currency bar fades in → universal-upgrade caps explode → stream swoops right → board-upgrade caps explode), then releases the deferred new-board peek.
- **Not prestige:** no `PrestigeManager`, no `PrestigePhase`, no scene reload — `Engine.time_scale` is set directly and restored on every exit path. `_teardown` is idempotent and runs on normal finish, on `prestige_phase_changed` (non-NONE), on `BoardManager.board_switched` (a level reward can auto-switch boards mid-reveal), and on `_exit_tree`. `PROCESS_MODE_ALWAYS` so the camera-follow runs real-time during slow-mo.
- Listens: per-board `cap_raise_coin_landed` (`connect_board`, PrestigeAnimator precedent — also re-wired in `Main._on_board_unlocked`); `PrestigeManager.prestige_phase_changed`; `BoardManager.board_switched`. No signals emitted.
- Trigger lives in `PlinkoBoard._will_reveal_cap_raise`: raw-currency bucket, NOT a prestige (post-prestige), cap raises not yet available for *this* board. One-shot per tier with no new persistent flag — `UpgradeManager._cap_raise_available` is already serialized.
- Suppression handshake: while a reveal runs, `CoinValues` and the board's `UpgradeSection` keep cap "+" buttons wired-but-hidden (`begin_cap_raise_reveal` → `get_pending_currency_cap_targets` / `get_pending_universal_cap_targets` / `get_pending_cap_raise_targets` → `end_cap_raise_reveal`). `end_*` force-shows every button **and** the delayed raw-currency bar, so an interrupted reveal can never strand a button hidden. `CoinValues` additionally delays the freshly-earned raw-currency bar (created hidden, `reveal_delayed_currency_bar` fades it in mid-sequence). All tunables live in `VisualTheme` under the `Cap Raise Reveal VFX` group.

**DropSection** — `entities/drop_section/drop_section.gd` + `.tscn`

- Contains `DropButton` instances (normal + advanced). Each emits `drop_pressed` (wired to `PlinkoBoard.request_drop()`) and `autodropper_adjust_requested` (wired to `BoardManager` via the board's matching signal).
- Owns the `QueueBonusLabel` (top-left-anchored 2D `Label`). `set_queue_bonus(queued_count, bonus_per_coin)` updates the two-line text and visibility; `set_queue_bonus_position(viewport_pos)` writes `global_position` directly so the label anchors in screen space regardless of `DropSection`'s parent layout (it sits under a `Node3D`).
- Listens: `ThemeProvider.theme_changed` to re-apply font/color overrides on the bonus label so it survives theme swaps (e.g. challenge mode).

**CoinQueue** — `entities/coin_queue/coin_queue.gd` + `.tscn`

- FIFO queue of `Coin` nodes (FULL coins ahead of FILLING autodrop coins).
- Emits: `coin_enqueued(index, coin_type)`, `coin_dequeued()`, `capacity_changed(cap)`, `count_changed(new_count)`. `count_changed` carries the new total and fires only on actual size changes — used by `PlinkoBoard` for the rate bonus and by `BoardManager` for subtext refresh.
- Mutations that affect total count (`enqueue`, `dequeue`, `dequeue_full`, `complete_first_filling`, `complete_and_requeue_filling`, `remove_filling_coins_of_type`) all call `_emit_count_if_changed`.

#### Resources (data)

**VisualTheme** — `style_lab/visual_theme.gd`, presets in `style_lab/presets/*.tres`

- Bundle of visual configuration: background shades, per-currency colors, coin/bucket/label materials, VFX toggles, coin physics timings, audio flags. Consumed via `ThemeProvider.theme`.
- Deflector reaction config (palette-sourced, consumed by `DeflectorEditor`): `deflector_reaction_enabled`, `deflector_hit_color`/`deflector_miss_color` (resolved from `deflector_hit_color_source`/`deflector_miss_color_source` Palette assignments), `deflector_hit_glow_duration`, `deflector_hit_pulse_scale`, `deflector_miss_fade_duration`.
- Audio-related: `audio_lofi_enabled`, `audio_style: AudioStyle` (optional override; null = main harp).

**AudioStyle** — `autoloads/audio_manager/audio_style.gd`

- Data-only resource attached to a `VisualTheme`. Describes an alternate audio world: `display_name`, `active_during_challenge_only`, `beats_per_tick`, `has_backing_kick`, `has_backing_bass`, `timbre` (`"square" | "harp"`), `progression[]`, `chord_duration`, `bucket_accent_motif[]`.
- Current preset: `style_lab/presets/arcade_audio_style.tres` — square timbre, i-VI-VII-i in A minor, kick backing only.

**ChallengeData** — `autoloads/challenge_manager/challenge_data.gd`

- Per-challenge metadata: `id`, `display_name`, `time_limit_seconds`, `objectives[]`, `constraints[]`, `starting_conditions[]`, `rewards[]`.

**ChallengeRewardData** — `autoloads/challenge_manager/challenge_reward_data.gd`

- Structured challenge reward (`type`, `modifier_type`, `modifier_amount`, board/currency/upgrade refs). No hand-written `description` — removed.
- `display_text()` is the **single source of truth** for reward text: both the pre-challenge info panel (`ChallengeInfoPanel`) and the post-challenge modal (`Main`) call it, so they can't drift. Generated from the structured fields; `GOLD_COIN_SPEED_BOOST`/`QUEUE_RATE_BONUS` pull their magnitude live from `Coin.COIN_SPEED_BOOST_PER_UNLOCK` / `PlinkoBoard.QUEUE_RATE_BONUS_PER_UNLOCK` (those constants are canonical — no `.tres` edits needed when they change). `ADVANCED_COIN_MULTIPLIER` is gold-only by design (text hardcodes "raw orange"). Every `RewardType`/`ModifierType` must map to non-empty text — `test_challenge_reward_data` guards this for the append-only enum.
- Board/upgrade/currency naming and the prestige multi-drop/board-access phrasing all route through shared `FormatUtils` helpers (`board_name`, `upgrade_name`, `currency_name`, `lower_tier_names_phrase`, `multi_drop_phrase`, `access_board_phrase`); the prestige screen + dialog reuse the same helpers so wording stays identical everywhere.

**Objective types** (`autoloads/challenge_manager/objectives/`): `Survive`, `LandInEveryBucket`, `HitBucketsInOrder`, `HitXBucketYTimes`, `GetSameBucketXTimes`, `EarnWithinXDrops`, `BoardGoal`, `CoinGoal`. Evaluated by `ChallengeTracker`.

**StartingCondition** subclasses (also under challenge_manager/): `StartingCap`, `StartingCoins`, `StartingUpgrades`, `StartingBoards`, `StartingDropDelay`. Applied by `ChallengeManager._apply_starting_conditions`.

**RewardData** — `scripts/reward_data.gd`

- Unified reward container used by `LevelManager` level rewards and challenge completion rewards. `type: RewardType` enum: `UNLOCK_UPGRADE`, `DROP_COINS`, `UNLOCK_AUTODROPPER`, `UNLOCK_ADVANCED_AUTODROPPER`, `UNLOCK_ADVANCED_BUCKET`.

**BaseUpgradeData** — `autoloads/upgrade_manager/base_upgrade_data.gd`, presets in `autoloads/upgrade_manager/data/*.tres`

- Per-upgrade economy: `type`, `display_name`, `base_cost`, `max_level`, `cost_delta`. `max_level` is the starting cap.

**TierData** — `scripts/tier_data.gd`, presets in `autoloads/tier_registry/data/*.tres`

- Per-tier config: `board_type`, `display_name`, `primary_currency`, `raw_currency`, economy caps, drop costs.

#### Cross-cutting data flows

- **Currency → Progression:** `currency_changed` → `LevelManager` (threshold crossings) → `rewards_claimed` → `UpgradeManager.unlock` / reward dispatch.
- **Cap raises:** `currency_changed` on a tier's raw currency → `UpgradeManager.cap_raise_unlocked(board_type)`.
- **Challenge pulse:** `ChallengeTracker._process` → `ChallengeManager.tick` → `AudioManager` (arcade kick + beat grid) + `ChallengeClock` (pie slice).
- **Theme/Challenge → Audio:** `theme_changed` or `challenge_state_changed` → `AudioManager._reselect_audio_style`. Any style transition fades all drones over 1s.
- **Autodropper → Audio beat:** `BoardManager._on_autodrop_tick` → `AudioManager.notify_autodropper_beat` syncs the harp beat grid.
- **Coin lifecycle:** `request_drop` → `Coin.start` → per-row board queries → `final_bounce_started` → `PlinkoBoard.finalize_coin_landing` → `coin_landed` (ChallengeTracker, BoardManager listen) + `AudioManager.play_bucket`.
- **Peek lifecycle:** `BoardManager.board_unlocked` (or `Main._setup_normal` → `PeekAnimator.queue_peeks_for_existing_unlocks` post-load) → enqueue PeekRequest → `_drain_loop` → `apply_input_lock(true)` → `switch_board_fn` / `switch_to_challenges_fn` → wait → switch back → `OnboardingProgress.mark_*_peeked` → `SaveManager.save_game` → `apply_input_lock(false)`. Suppressed during active challenges, during deserialize, and for already-peeked targets.
- **Peek-driven side-effect suppression:** `Main._on_mode_changed` / `Main._on_board_switched` consult `peek_animator.is_peeking()` before flipping `challenges_ever_visited` / clearing `_boards_with_unseen_upgrades`, so nav-arrow blinks survive the peek as cues the player still hasn't visited.
- **Autodropper intro lifecycle:** `UpgradeManager.upgrade_purchased(AUTODROPPER, GOLD, 1)` → `BoardManager._on_upgrade_purchased` (in main mode, with `OnboardingProgress.has_seen_autodropper_intro = false`) → `first_autodropper_purchased.emit()` (early-returns before auto-assigning) → `AutodropperIntroAnimator._on_first_autodropper_purchased` → particle burst+swoop tween → `BoardManager.reveal_autodropper_controls()` (shows +/– on drop button) → `OnboardingProgress.mark_autodropper_intro_seen` + `SaveManager.save_game` → `+` button pulses via `blink_scale_fade` until `FillBar.plus_pressed` fires → `_on_first_plus_pressed` kills the tween. Suppressed during active challenges (signal not emitted) and after first replay (gate flag flipped). Load and `_apply_prestige_rewards` paths are unchanged — they call `set_normal_autodroppers_visible(true)` directly.
- **Challenge exit lifecycle:** `ChallengeTracker` completed/failed → `ChallengeManager.challenge_{completed,failed}` → `Main._on_challenge_{completed,failed}` → (results dialog) → `Main._exit_challenge_to_menu()` sets `ModeManager.pending_challenges_menu` + `SaveManager.reset_state()` + reload `main.tscn` → `Main._ready` consumes the flag → `ModeManager.switch_to_challenges()` → `_on_mode_changed` → `ChallengeGroupingManager.enter_challenges_mode()`. Player returns to the challenge selection menu, not the board.
- **Save:** `SaveManager.save_game/load_game` serializes/deserializes managers in the strict order above.

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

## Feature Planning Process (Plan Mode Only)

When the user enters plan mode and describes a feature, run a multi-agent review before writing any code. Six personalities evaluate the feature in parallel, debate concerns in rounds, and produce a consensus plan.

### The Six Personalities

Each evaluates proposed features through their lens, oriented toward **future code that will be written**, not auditing existing code.

1. **The Janitor — Code Cleanliness.** Duplication, reuse, oversized files, tangled responsibilities, future cleanup.
2. **The Godot Guru — Engine Best Practices.** Right nodes/patterns/APIs, "signals up, calls down", performance (node count, per-frame work, memory), lifecycle (`_ready`, `_enter_tree`, `_exit_tree`, `queue_free`), tweens/timers/resources.
3. **The Architect — Dependencies & Connections.** How it connects to existing systems, signals added/modified, ripple effects, circular dependencies, data-flow clarity.
4. **The Newcomer — Readability & Clarity.** Cold-read comprehension, magic numbers, cryptic names, undocumented business logic, control flow, naming consistency.
5. **The Consistency Lover — Standardization.** Codebase patterns (signal naming, typing, init), connection style (direct method refs over inline lambdas), error handling, type annotations, theme variables (never raw `Color.WHITE`).
6. **The Test Lead — Testing & Testability.** Logic testable without running the game, isolatable behaviors, critical paths needing coverage, mockable dependencies, explicit state transitions, regression coverage.

### Process

1. **Parallel analysis:** Spin up all 6 agents simultaneously.
2. **Round 1 — Concerns:** Collect all concerns, present a summary per personality.
3. **Round 2+ — Resolution:** If conflicts exist, run another round where agents see each other's concerns and respond. Up to 3 rounds. Don't ask the user to resolve disagreements during this — let agents work it out.
4. **Escalation:** Unresolved disagreements after 3 rounds go to the user.
5. **Approval:** Present the final plan. Only begin implementation after explicit approval.

### Logging

All deliberations are logged to `agent-logs/<feature-name>.md`: feature description, round-by-round concerns, disagreements, resolutions, final plan.

### When This Applies

Only when the user enters plan mode for a new feature. Not for: simple bug fixes, one-line tweaks, questions/explanations.

## Branch Workflow

### Plan Mode Creates a Worktree

When the user enters plan mode for a feature, after the plan is approved but before any implementation begins, create a new git **worktree** (not just a branch) so the work never disturbs the primary checkout — the user may have another agent actively working there and testing in Godot. Mechanics:

- Run `tools/new_worktree.sh <kebab-case-name>`. It creates the worktree under `.claude/worktrees/<name>/` on a new branch `feature/<name>` off `main` and pre-seeds the Godot import cache (copies `.godot/imported` from the primary checkout, or falls back to a headless import) so the worktree opens warm.
- All implementation happens inside the worktree; commit regularly. The primary checkout is left untouched.

**Getting the work onto `main` to test:** the worktree's commits live on the `feature/<name>` branch, so from the primary checkout (on a clean `main`):

- **`tools/land_worktree.sh <name>`** — fast-forward-merges `feature/<name>` into `main` with the warm import cache intact. Add `--remove` to also tear down the worktree + branch in the same step. It is fast-forward-only by design: if `main` has advanced since the worktree was cut it refuses and tells you to `git rebase main` inside the worktree first (keeps history linear and testing sequential).
- To back out after testing: `git reset --hard origin/main`. To test in isolation without merging: `git switch feature/<name>`.

When a worktree is abandoned without landing: `git worktree remove .claude/worktrees/<name>` (and `git branch -D feature/<name>`).

### Post-Implementation Review

After the user confirms the implementation looks good, run a post-implementation review using the same six personalities before merging to main.

#### Process

1. **Collect the diff:** `git diff main...HEAD`.
2. **Parallel review:** All 6 agents review the diff through their lens (Janitor: dead code/duplication; Godot Guru: lifecycle/signals/perf in actual code; Architect: matches plan, no unplanned coupling; Newcomer: readability of implemented code; Consistency Lover: matches existing patterns; Test Lead: tested key behaviors).
3. **Round 1 — Concerns:** Mark each as **blocking** (must fix before merge) or **advisory** (nice to fix).
4. **Round 2+ — Resolution:** Same multi-round debate as planning. Up to 3 rounds.
5. **Escalation:** Unresolved disagreements go to the user.
6. **Fix:** Address all blocking concerns on the feature branch.
7. **Update living documentation (only if the system map changed):** If the branch added/removed a system, changed an ownership/signal/dependency relationship, or established a non-obvious invariant, update "System Responsibilities" — terse, per its narrow scope (map + invariants only; NOT per-method mechanics). Add a subsection for a new system, remove a deleted one, fix a now-wrong relationship/invariant. Do NOT restate mechanics or re-summarize the diff. If nothing at the map/invariant level changed (most refactors, tweaks, bug fixes), skip this step entirely — don't write prose just to have written it. When you do update, commit it separately (`docs: update system responsibilities for <feature>`).
8. **Merge:** Once blocking concerns are resolved and docs are updated, merge into `main` and delete the feature branch.

#### Logging

Post-implementation reviews are appended to the same `agent-logs/<feature-name>.md` under a `## Post-Implementation Review` heading.

#### When This Applies

Runs when the user confirms an implementation done on a feature branch (created via plan mode) is ready for review. Doesn't run for work on `main` directly or for incomplete work.

## Final notes

The old code from the prototype can be found under `deprecated`. This was how things used to work.
