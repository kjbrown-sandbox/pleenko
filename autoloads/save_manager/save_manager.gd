extends Node

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 3
const AUTO_SAVE_INTERVAL := 30.0

var _auto_save_timer: Timer
var _board_manager: BoardManager


func setup(board_manager: BoardManager, should_autosave: bool) -> void:
	_board_manager = board_manager

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
	# LevelManager before CurrencyManager so current_level is correct
	# when currency_changed signals fire during currency restore
	LevelManager.deserialize(data.get("level", {}))
	CurrencyManager.deserialize(data.get("currency", {}))
	UpgradeManager.deserialize(data.get("upgrades", {}))
	_board_manager.deserialize(data.get("boards", {}))

	print("[SaveManager] Game loaded.")
	return true


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


func reset_game() -> void:
	# Capture prestige data before wiping the save — prestige survives resets
	var prestige_data := PrestigeManager.serialize()

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	# Write a minimal save containing only prestige + version so it persists
	var minimal_save := {
		"version": SAVE_VERSION,
		"prestige": prestige_data,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(minimal_save, "\t"))
		file.close()

	reset_state()
	get_tree().reload_current_scene()

func reset_state() -> void:
	CurrencyManager.reset()
	LevelManager.reset()
	UpgradeManager.reset()
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
	data["version"] = SAVE_VERSION
	return data

func toggle_auto_save(enabled: bool) -> void:
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