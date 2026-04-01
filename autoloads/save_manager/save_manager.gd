extends Node

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 4
const AUTO_SAVE_INTERVAL := 30.0

var _auto_save_timer: Timer
var _board_manager: BoardManager


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
	var data := {
		"version": SAVE_VERSION,
		"save_timestamp": Time.get_unix_time_from_system(),
		"currency": CurrencyManager.serialize(),
		"level": LevelManager.serialize(),
		"upgrades": UpgradeManager.serialize(),
		"boards": _board_manager.serialize(),
		"prestige": PrestigeManager.serialize(),
		"challenges": ChallengeProgressManager.serialize(),
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
	var saved_time: float = data.get("save_timestamp", 0.0)
	if saved_time > 0.0:
		var elapsed: float = Time.get_unix_time_from_system() - saved_time
		var updated := OfflineCalculator.calculate(data, elapsed)
		data["currency"] = updated["currency"]
		print("[SaveManager] Applied offline earnings for %.0f seconds." % elapsed)

	# Deserialize prestige first — BoardManager queries it during deserialize
	PrestigeManager.deserialize(data.get("prestige", {}))
	ChallengeProgressManager.deserialize(data.get("challenges", {}))
	# LevelManager before CurrencyManager so current_level is correct
	# when currency_changed signals fire during currency restore
	LevelManager.deserialize(data.get("level", {}))
	CurrencyManager.deserialize(data.get("currency", {}))
	UpgradeManager.deserialize(data.get("upgrades", {}))
	_board_manager.deserialize(data.get("boards", {}))

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


func reset_game() -> void:
	# Capture persistent data before wiping the save — prestige + challenges survive resets
	var prestige_data := PrestigeManager.serialize()
	var challenge_data := ChallengeProgressManager.serialize()

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	# Write a minimal save containing persistent data so it survives reset
	var minimal_save := {
		"version": SAVE_VERSION,
		"prestige": prestige_data,
		"challenges": challenge_data,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(minimal_save, "\t"))
		file.close()

	reset_state()
	get_tree().reload_current_scene()


## Performs the same save wipe and state reset as reset_game(), but does NOT reload
## the current scene. Use this when the caller will handle the scene transition
## (e.g., transitioning from PrestigeScreen back to Main via SceneManager).
func reset_game_without_reload() -> void:
	var prestige_data := PrestigeManager.serialize()
	var challenge_data := ChallengeProgressManager.serialize()

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	var minimal_save := {
		"version": SAVE_VERSION,
		"prestige": prestige_data,
		"challenges": challenge_data,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(minimal_save, "\t"))
		file.close()

	reset_state()


func reset_state() -> void:
	CurrencyManager.reset()
	LevelManager.reset()
	UpgradeManager.reset()
	toggle_auto_save(false)
	_board_manager = null
	print("[SaveManager] Game reset (prestige preserved). Reloading scene.")

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
