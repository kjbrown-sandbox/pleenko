extends Node

## Wraps the GameAnalytics SDK to track player progression, retention, and
## engagement events. Gracefully no-ops when the SDK plugin is not installed,
## so the game runs fine without it during development.
##
## Autoload order: after AudioManager (last in the chain — listen-only, no
## other system depends on this).
##
## Setup:
##   1. Install the GameAnalytics GDExtension plugin into addons/GameAnalytics/
##   2. Enable it in Project > Project Settings > Plugins
##   3. Set your game key and secret key below (or load from a config file)
##
## All events are fire-and-forget. The SDK handles batching, offline queueing,
## and session tracking automatically.

## Keys are loaded from analytics_keys.cfg (gitignored) at runtime.
const KEYS_PATH := "res://analytics_keys.cfg"

## Path for persisting the anonymous player ID across sessions.
const PLAYER_ID_PATH := "user://analytics_player_id.txt"

var _ga: Object  # GameAnalytics singleton — null if SDK not installed
var _enabled := false
var _board_manager: Node  # BoardManager reference for scene-level signals


func _ready() -> void:
	if not Engine.has_singleton("GameAnalytics"):
		print("[AnalyticsManager] GameAnalytics SDK not found — analytics disabled.")
		return

	var keys := _load_keys()
	if keys.is_empty():
		print("[AnalyticsManager] analytics_keys.cfg not found or missing keys — analytics disabled.")
		return

	_ga = Engine.get_singleton("GameAnalytics")
	_ga.setEnabledInfoLog(false)
	_ga.setEnabledVerboseLog(false)
	_ga.init(keys["game_key"], keys["secret_key"])

	var player_id := _load_or_create_player_id()
	_ga.configureUserId(player_id)

	_enabled = true
	print("[AnalyticsManager] Initialized with player ID: %s" % player_id)

	# Connect to autoload signals (available immediately)
	LevelManager.level_changed.connect(_on_level_changed)
	LevelManager.rewards_claimed.connect(_on_rewards_claimed)
	PrestigeManager.prestige_claimed.connect(_on_prestige_claimed)
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	ChallengeManager.challenge_completed.connect(_on_challenge_completed)
	ChallengeManager.challenge_failed.connect(_on_challenge_failed)


## Called from main.gd after BoardManager is ready, so we can listen to
## scene-level signals that aren't available at autoload _ready() time.
func setup(board_manager: Node) -> void:
	if not _enabled:
		return

	# Disconnect from previous board_manager if scene was reloaded
	if is_instance_valid(_board_manager):
		if _board_manager.board_unlocked.is_connected(_on_board_unlocked):
			_board_manager.board_unlocked.disconnect(_on_board_unlocked)
	_board_manager = board_manager
	_board_manager.board_unlocked.connect(_on_board_unlocked)


# -- Event handlers --------------------------------------------------------

func _on_level_changed(new_level: int) -> void:
	_design_event("progression:level_reached", new_level)


func _on_rewards_claimed(level: int, _rewards: Array[RewardData]) -> void:
	_design_event("progression:rewards_claimed", level)


func _on_prestige_claimed(board_type: Enums.BoardType) -> void:
	var board_name: String = Enums.BoardType.keys()[board_type]
	_design_event("prestige:claimed:%s" % board_name.to_lower(), 1.0)


func _on_board_unlocked(board_type: Enums.BoardType) -> void:
	var board_name: String = Enums.BoardType.keys()[board_type]
	_design_event("progression:board_unlocked:%s" % board_name.to_lower(), 1.0)


func _on_upgrade_purchased(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType, new_level: int) -> void:
	var upgrade_name: String = Enums.UpgradeType.keys()[upgrade_type]
	var board_name: String = Enums.BoardType.keys()[board_type]
	_design_event("upgrade:%s:%s" % [board_name.to_lower(), upgrade_name.to_lower()], new_level)


func _on_challenge_completed() -> void:
	var challenge: ChallengeData = ChallengeManager.get_challenge()
	if challenge:
		_progression_event("Complete", challenge.id, ChallengeManager.get_time_taken())


func _on_challenge_failed(reason: String) -> void:
	var challenge: ChallengeData = ChallengeManager.get_challenge()
	if challenge:
		_progression_event("Fail", challenge.id, ChallengeManager.get_time_taken())
		_design_event("challenge:fail_reason:%s:%s" % [challenge.id, reason], 1.0)


# -- SDK wrappers ----------------------------------------------------------

func _design_event(event_id: String, value: float) -> void:
	if not _enabled:
		return
	_ga.addDesignEventWithValue(event_id, value, {})


func _progression_event(status: String, challenge_id: String, score: float) -> void:
	if not _enabled:
		return
	_ga.addProgressionEventWithScore(status, "challenge", challenge_id, "", int(score), {})


# -- Key loading -----------------------------------------------------------

func _load_keys() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(KEYS_PATH) != OK:
		return {}
	var game_key: String = config.get_value("analytics", "game_key", "")
	var secret_key: String = config.get_value("analytics", "secret_key", "")
	if game_key.is_empty() or secret_key.is_empty():
		return {}
	return {"game_key": game_key, "secret_key": secret_key}


# -- Player ID persistence -------------------------------------------------

func _load_or_create_player_id() -> String:
	if FileAccess.file_exists(PLAYER_ID_PATH):
		var file := FileAccess.open(PLAYER_ID_PATH, FileAccess.READ)
		if file:
			var id := file.get_as_text().strip_edges()
			file.close()
			if not id.is_empty():
				return id

	# Generate a new anonymous ID (v4 UUID-style)
	var id := _generate_uuid()
	var file := FileAccess.open(PLAYER_ID_PATH, FileAccess.WRITE)
	if file:
		file.store_string(id)
		file.close()
	return id


func _generate_uuid() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var hex: String = ""
	for i in 16:
		hex += "%02x" % rng.randi_range(0, 255)
	# Format as 8-4-4-4-12
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]
