extends Node

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const AUTO_SAVE_INTERVAL := 30.0

var _auto_save_timer: Timer
var _board_manager: BoardManager


func setup(board_manager: BoardManager) -> void:
	_board_manager = board_manager

	_auto_save_timer = Timer.new()
	_auto_save_timer.wait_time = AUTO_SAVE_INTERVAL
	_auto_save_timer.autostart = true
	_auto_save_timer.timeout.connect(save_game)
	add_child(_auto_save_timer)


func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"currency": CurrencyManager.serialize(),
		"level": LevelManager.serialize(),
		"upgrades": UpgradeManager.serialize(),
		"boards": _board_manager.serialize(),
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
	if version != SAVE_VERSION:
		print("[SaveManager] Save version mismatch: expected %d, got %d" % [SAVE_VERSION, version])
		# Future: add migration logic here
		return false

	# Deserialize in dependency order: currency first, then level, upgrades, boards
	CurrencyManager.deserialize(data.get("currency", {}))
	LevelManager.deserialize(data.get("level", {}))
	UpgradeManager.deserialize(data.get("upgrades", {}))
	_board_manager.deserialize(data.get("boards", {}))

	print("[SaveManager] Game loaded.")
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func reset_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	CurrencyManager.reset()
	LevelManager.reset()
	UpgradeManager.reset()
	_board_manager = null
	print("[SaveManager] Game reset. Reloading scene.")
	get_tree().reload_current_scene()
