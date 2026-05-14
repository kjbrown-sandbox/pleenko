extends Node

## Persistent first-time-UX flags that survive prestige resets. Tracks whether
## the player has been "peeked" at newly-unlocked navigation targets (boards,
## challenges) so we don't replay the peek every cold start.

var _peeked_boards: Dictionary = {}  # BoardType -> bool
var _peeked_challenges: bool = false


func has_peeked_board(type: Enums.BoardType) -> bool:
	return _peeked_boards.get(type, false)


func mark_board_peeked(type: Enums.BoardType) -> void:
	_peeked_boards[type] = true


func has_peeked_challenges() -> bool:
	return _peeked_challenges


func mark_challenges_peeked() -> void:
	_peeked_challenges = true


func reset() -> void:
	_peeked_boards.clear()
	_peeked_challenges = false


func serialize() -> Dictionary:
	var boards_data: Array[int] = []
	for board_type in _peeked_boards:
		if _peeked_boards[board_type]:
			boards_data.append(board_type)
	return {
		"peeked_boards": boards_data,
		"peeked_challenges": _peeked_challenges,
	}


func deserialize(data: Dictionary) -> void:
	_peeked_boards.clear()
	var boards_data: Array = data.get("peeked_boards", [])
	for board_type_int in boards_data:
		_peeked_boards[int(board_type_int)] = true
	_peeked_challenges = data.get("peeked_challenges", false)
