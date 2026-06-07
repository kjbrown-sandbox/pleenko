extends Node

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 7
const AUTO_SAVE_INTERVAL := 30.0

var _auto_save_timer: Timer
var _board_manager: BoardManager
## Offline earnings from the last load_game() call. Keyed by CurrencyType string
## name -> amount earned. Empty if no offline time elapsed. Cleared after reading.
var last_offline_earnings: Dictionary = {}


func setup(board_manager: BoardManager, should_autosave: bool) -> void:
	_board_manager = board_manager

	# Clean up any existing timer from a previous scene
	if _auto_save_timer:
		_auto_save_timer.stop()
		_auto_save_timer.queue_free()
		_auto_save_timer = null

	if should_autosave:
		_auto_save_timer = Timer.new()
		_auto_save_timer.wait_time = AUTO_SAVE_INTERVAL
		_auto_save_timer.autostart = true
		_auto_save_timer.timeout.connect(save_game)
		add_child(_auto_save_timer)


func save_game() -> void:
	if not is_instance_valid(_board_manager):
		return

	# Reconcile state with current_level before serializing — covers the race
	# where current_level advanced but rewards haven't dispatched yet (deferred
	# to the level-up animation). Ensures saved state always matches level.
	LevelManager.ensure_state_for_level()

	var data := {
		"version": SAVE_VERSION,
		"save_timestamp": Time.get_unix_time_from_system(),
		"currency": CurrencyManager.serialize(),
		"level": LevelManager.serialize(),
		"upgrades": UpgradeManager.serialize(),
		"boards": _board_manager.serialize(),
		"prestige": PrestigeManager.serialize(),
		"challenges": ChallengeProgressManager.serialize(),
		"onboarding": OnboardingProgress.serialize(),
		"audio_muted": AudioManager.is_muted(),
		"master_volume": AudioManager.get_master_volume(),
		"vfx_settings": AudioManager.get_vfx_overrides(),
		"max_fps": PerformanceSettings.get_max_fps(),
		"window_mode": PerformanceSettings.get_window_mode(),
	}

	var json_string := JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		print("[SaveManager] Failed to open save file for writing: %s" % FileAccess.get_open_error())
		return

	file.store_string(json_string)
	file.close()
	print("[SaveManager] Game saved.")


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[SaveManager] No save file found.")
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		print("[SaveManager] Failed to open save file for reading.")
		return false

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		print("[SaveManager] Failed to parse save file: %s" % json.get_error_message())
		return false

	var data: Dictionary = json.data
	var version: int = data.get("version", 0)
	data = _migrate(data, version)

	# Compute offline earnings before deserializing into managers
	last_offline_earnings = {}
	var saved_time: float = data.get("save_timestamp", 0.0)
	if saved_time > 0.0:
		var elapsed: float = Time.get_unix_time_from_system() - saved_time
		var old_currency: Dictionary = data.get("currency", {}).duplicate(true)
		var updated := OfflineCalculator.calculate(data, elapsed)
		data["currency"] = updated["currency"]
		# Compute per-currency deltas
		for key in updated["currency"]:
			var new_bal: int = updated["currency"][key].get("balance", 0)
			var old_bal: int = old_currency.get(key, {}).get("balance", 0)
			var earned: int = new_bal - old_bal
			if earned > 0:
				last_offline_earnings[key] = earned
		print("[SaveManager] Applied offline earnings for %.0f seconds." % elapsed)

	# Deserialize prestige first — BoardManager queries it during deserialize
	PrestigeManager.deserialize(data.get("prestige", {}))
	ChallengeProgressManager.deserialize(data.get("challenges", {}))
	OnboardingProgress.deserialize(data.get("onboarding", {}))
	# LevelManager before CurrencyManager so current_level is correct
	# when currency_changed signals fire during currency restore
	LevelManager.deserialize(data.get("level", {}))
	CurrencyManager.deserialize(data.get("currency", {}))
	UpgradeManager.deserialize(data.get("upgrades", {}))
	_board_manager.deserialize(data.get("boards", {}))
	AudioManager.set_muted(data.get("audio_muted", false))
	AudioManager.set_master_volume(data.get("master_volume", 50.0))
	for key: String in data.get("vfx_settings", {}):
		AudioManager.set_vfx_override(key, bool(data["vfx_settings"][key]))
	PerformanceSettings.set_max_fps(int(data.get("max_fps", PerformanceSettings.DEFAULT_MAX_FPS)))
	PerformanceSettings.set_window_mode(int(data.get("window_mode", PerformanceSettings.DEFAULT_WINDOW_MODE)))

	# Failsafe: reconcile state with the level table.
	# Heals saves where current_level was saved ahead of claim_rewards().
	LevelManager.ensure_state_for_level()

	# Failsafe: rescue from 0 gold / 0 raw orange soft-lock on load.
	_board_manager.check_and_rescue_gold_soft_lock()

	print("[SaveManager] Game loaded.")
	return true


func save_challenge_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		# No existing save — write a minimal one with challenge + prestige data
		var data := {
			"version": SAVE_VERSION,
			"prestige": PrestigeManager.serialize(),
			"challenges": ChallengeProgressManager.serialize(),
		}
		var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(data, "\t"))
			file.close()
		return

	# Update challenges key in existing save
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	file.close()

	var data: Dictionary = json.data
	data["challenges"] = ChallengeProgressManager.serialize()
	var write_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if write_file:
		write_file.store_string(JSON.stringify(data, "\t"))
		write_file.close()
	print("[SaveManager] Challenge progress saved.")


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_prestige_only() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	file.close()
	var data: Dictionary = json.data
	PrestigeManager.deserialize(data.get("prestige", {}))
	ChallengeProgressManager.deserialize(data.get("challenges", {}))


## Audio/device preferences that survive EVERY reset variant (settings, not
## progress). Same rationale as the audio-prefs-survive-reset behavior.
func _device_prefs() -> Dictionary:
	return {
		"audio_muted": AudioManager.is_muted(),
		"master_volume": AudioManager.get_master_volume(),
		"vfx_settings": AudioManager.get_vfx_overrides(),
		"max_fps": PerformanceSettings.get_max_fps(),
		"window_mode": PerformanceSettings.get_window_mode(),
	}


## Progress blocks that the prestige-preserving resets keep but full_reset()
## drops. Serialized before the save file is deleted.
func _persistent_progress_blocks() -> Dictionary:
	return {
		"prestige": PrestigeManager.serialize(),
		"challenges": ChallengeProgressManager.serialize(),
		"onboarding": OnboardingProgress.serialize(),
	}


## Deletes the save, rewrites a minimal save (version + device prefs + any
## extra blocks the caller wants preserved), then resets runtime state. The
## only axis of variation across the reset variants is `extra_blocks`.
func _wipe_save(extra_blocks: Dictionary) -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	var minimal_save := {"version": SAVE_VERSION}
	minimal_save.merge(_device_prefs())
	minimal_save.merge(extra_blocks)

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(minimal_save, "\t"))
		file.close()

	reset_state()


func reset_game() -> void:
	_wipe_save(_persistent_progress_blocks())
	get_tree().reload_current_scene()


## Performs the same save wipe and state reset as reset_game(), but does NOT reload
## the current scene. Use this when the caller will handle the scene transition
## (e.g., transitioning from PrestigeScreen back to Main via SceneManager).
func reset_game_without_reload() -> void:
	_wipe_save(_persistent_progress_blocks())


## Hard wipe for the "Reset Game" main-menu option. Unlike reset_game(), this
## preserves NOTHING about progress — prestige, challenges, and onboarding are
## all cleared for a true fresh start. Only device preferences are kept. The
## caller is the main menu, so no scene reload is needed: autoload state is
## cleared in memory here, and the menu shows no save-derived state.
func full_reset() -> void:
	# Clear the persistent managers BEFORE _wipe_save() (which runs
	# reset_state()), so the wipe order matches the documented load order
	# (prestige first) and never rebuilds state off not-yet-cleared prestige.
	# Note the name asymmetry: PrestigeManager/ChallengeProgressManager have a
	# single (full) reset(); OnboardingProgress.reset() is the prestige-
	# preserving partial, so full_reset() is needed for a true wipe there.
	PrestigeManager.reset()
	ChallengeProgressManager.reset()
	OnboardingProgress.full_reset()
	_wipe_save({})  # no progress blocks = true fresh start
	print("[SaveManager] Game fully reset (all progress wiped, device prefs kept).")


func reset_state() -> void:
	CurrencyManager.reset()
	LevelManager.reset()
	UpgradeManager.reset()
	# reset() on these managers is silent (unlike deserialize, which broadcasts).
	# Re-broadcast the cleared state so any UI that subscribed before this reset
	# repaints from zeroed state instead of showing stale pre-reload values. This
	# matters on challenge entry: the level bar + currency HUD _ready (and connect
	# their signals) as children BEFORE Main's _ready runs reset_state, so without
	# this they keep painting the previous session's tier/balances until the first
	# in-challenge currency_changed. Level first so currency listeners that read
	# current_level see the reset value.
	LevelManager.level_changed.emit(LevelManager.current_level)
	CurrencyManager.notify_all()
	toggle_auto_save(false)
	_board_manager = null
	print("[SaveManager] Runtime state reset (currency/level/upgrades).")

func _migrate(data: Dictionary, version: int) -> Dictionary:
	if version < 2:
		data["prestige"] = {}
		print("[SaveManager] Migrated save v%d -> v2" % version)
	if version < 3:
		# No-op: old saves just won't have save_timestamp.
		# load_game() defaults to 0.0, so offline calculator will skip.
		print("[SaveManager] Migrated save v%d -> v3" % version)
	if version < 4:
		data["challenges"] = {}
		print("[SaveManager] Migrated save v%d -> v4" % version)
	if version < 5:
		# Pre-onboarding: assume the player has already seen every navigation
		# target they've unlocked. Otherwise they'd peek again at boards/challenges
		# they already know about.
		var boards_data: Dictionary = data.get("boards", {})
		var board_types: Array = boards_data.get("board_types", [])
		var peeked_boards: Array[int] = []
		for board_type_int in board_types:
			if int(board_type_int) != Enums.BoardType.GOLD:
				peeked_boards.append(int(board_type_int))
		var challenge_data: Dictionary = data.get("challenges", {})
		var challenges_visited: bool = challenge_data.get("challenges_ever_visited", false)
		data["onboarding"] = {
			"peeked_boards": peeked_boards,
			"peeked_challenges": challenges_visited,
		}
		print("[SaveManager] Migrated save v%d -> v5 (onboarding seeded from existing state)" % version)
	if version < 6:
		# Existing players who already have the autodropper unlocked should not
		# see the intro animation — mark it as already seen.
		var boards_data: Dictionary = data.get("boards", {})
		if boards_data.get("normal_autodroppers_unlocked", false):
			var onboarding: Dictionary = data.get("onboarding", {})
			onboarding["autodropper_intro_seen"] = true
			data["onboarding"] = onboarding
		print("[SaveManager] Migrated save v%d -> v6 (autodropper intro seeded)" % version)
	if version < 7:
		# Existing players have already seen the milestone bar in whatever tier
		# they're in; seed `revealed_milestone_tiers` so peek-driven and squish-
		# cascade reveals don't replay on next launch.
		var level_data: Dictionary = data.get("level", {})
		var current_level: int = int(level_data.get("current_level", 0))
		var revealed_tiers: Array[int] = []
		var tier_start: int = 0
		while tier_start <= current_level:
			revealed_tiers.append(tier_start)
			tier_start += LevelManager.LEVELS_PER_TIER
		var onboarding: Dictionary = data.get("onboarding", {})
		onboarding["revealed_milestone_tiers"] = revealed_tiers
		data["onboarding"] = onboarding
		print("[SaveManager] Migrated save v%d -> v7 (milestone tiers seeded)" % version)
	data["version"] = SAVE_VERSION
	return data

func toggle_auto_save(enabled: bool) -> void:
	if not _auto_save_timer:
		return
	if enabled:
		if not _auto_save_timer.is_stopped():
			return
		_auto_save_timer.start()
		print("[SaveManager] Auto-save enabled.")
	else:
		if _auto_save_timer.is_stopped():
			return
		_auto_save_timer.stop()
		print("[SaveManager] Auto-save disabled.")
