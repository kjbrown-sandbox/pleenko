extends Node

signal prestige_triggered(board_type: Enums.BoardType)
signal prestige_claimed(board_type: Enums.BoardType)

# BoardType -> int: how many times the player has prestiged into this board tier
var _prestige_counts: Dictionary = {}


func can_prestige(board_type: Enums.BoardType) -> bool:
	return _prestige_counts.get(board_type, 0) == 0


func is_board_unlocked_permanently(board_type: Enums.BoardType) -> bool:
	return _prestige_counts.get(board_type, 0) > 0


## Returns how many coins should drop per single drop on a given board.
## Gold: 1 + sum of all prestige counts.  Orange: 1 + red count.  Red: always 1.
func get_multi_drop(board_type: Enums.BoardType) -> int:
	match board_type:
		Enums.BoardType.GOLD:
			var total := 0
			for count in _prestige_counts.values():
				total += count
			return 1 + total
		Enums.BoardType.ORANGE:
			return 1 + _prestige_counts.get(Enums.BoardType.RED, 0)
		_:
			return 1


func trigger_prestige(board_type: Enums.BoardType) -> void:
	_prestige_counts[board_type] = 1
	prestige_triggered.emit(board_type)


func claim_prestige(board_type: Enums.BoardType) -> void:
	prestige_claimed.emit(board_type)


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
