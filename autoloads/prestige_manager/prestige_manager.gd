extends Node

signal prestige_triggered(board_type: Enums.BoardType)
signal prestige_claimed(board_type: Enums.BoardType)
signal prestige_phase_changed(phase: PrestigePhase)

enum PrestigePhase { NONE, SLOW_MO, FREEZE, EXPAND, TRANSITION }

# BoardType -> int: how many times the player has prestiged into this board tier
var _prestige_counts: Dictionary = {}
var current_phase: PrestigePhase = PrestigePhase.NONE
## Set before transitioning to PrestigeScreen so it knows which board was prestiged.
var pending_board_type: Enums.BoardType


func can_prestige(board_type: Enums.BoardType) -> bool:
	return _prestige_counts.get(board_type, 0) == 0


func is_board_unlocked_permanently(board_type: Enums.BoardType) -> bool:
	return _prestige_counts.get(board_type, 0) > 0


## Returns how many coins should drop per single drop on a given board.
## Each tier gets +1 for every prestige count from tiers at higher indices.
## e.g. Gold gets bonuses from orange AND red prestige, orange from red only.
func get_multi_drop(board_type: Enums.BoardType) -> int:
	var idx := TierRegistry.get_tier_index(board_type)
	var bonus := 0
	for i in range(idx + 1, TierRegistry.get_tier_count()):
		var higher_tier := TierRegistry.get_tier_by_index(i)
		bonus += _prestige_counts.get(higher_tier.board_type, 0)
	return 1 + bonus


func trigger_prestige(board_type: Enums.BoardType) -> void:
	_prestige_counts[board_type] = 1
	prestige_triggered.emit(board_type)


func claim_prestige(board_type: Enums.BoardType) -> void:
	prestige_claimed.emit(board_type)


func enter_phase(phase: PrestigePhase) -> void:
	current_phase = phase
	var t: VisualTheme = ThemeProvider.theme
	match phase:
		PrestigePhase.SLOW_MO:
			Engine.time_scale = t.prestige_slow_mo_scale
		PrestigePhase.FREEZE:
			Engine.time_scale = t.prestige_freeze_scale
		PrestigePhase.EXPAND, PrestigePhase.TRANSITION:
			Engine.time_scale = t.prestige_freeze_scale
		PrestigePhase.NONE:
			Engine.time_scale = 1.0
	prestige_phase_changed.emit(phase)


func reset_time_scale() -> void:
	current_phase = PrestigePhase.NONE
	Engine.time_scale = 1.0


func serialize() -> Dictionary:
	var data := {}
	for board_type in _prestige_counts:
		var key: String = Enums.BoardType.keys()[board_type]
		data[key] = _prestige_counts[board_type]
	return data


func deserialize(data: Dictionary) -> void:
	_prestige_counts.clear()
	for key in data:
		var board_type: Enums.BoardType = Enums.BoardType[key]
		_prestige_counts[board_type] = data[key]
