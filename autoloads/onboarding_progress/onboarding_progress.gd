extends Node

## Persistent first-time-UX flags that survive prestige resets. Tracks whether
## the player has been "peeked" at newly-unlocked navigation targets (boards,
## challenges) so we don't replay the peek every cold start.

var _peeked_boards: Dictionary = {}  # BoardType -> bool
var _peeked_challenges: bool = false
var _autodropper_intro_seen: bool = false
var _deflector_intro_seen: bool = false
var _deflector_placed: bool = false
var _prestige_deflector_seeded: bool = false


func has_peeked_board(type: Enums.BoardType) -> bool:
	return _peeked_boards.get(type, false)


func mark_board_peeked(type: Enums.BoardType) -> void:
	_peeked_boards[type] = true


func has_peeked_challenges() -> bool:
	return _peeked_challenges


func mark_challenges_peeked() -> void:
	_peeked_challenges = true


func has_seen_autodropper_intro() -> bool:
	return _autodropper_intro_seen


func mark_autodropper_intro_seen() -> void:
	_autodropper_intro_seen = true


func has_seen_deflector_intro() -> bool:
	return _deflector_intro_seen


func mark_deflector_intro_seen() -> void:
	_deflector_intro_seen = true


## True once the player has placed their first-ever deflector — used to stop
## the discoverability pulse on the ghost arrow / center-peg hint.
func has_placed_deflector() -> bool:
	return _deflector_placed


func mark_deflector_placed() -> void:
	_deflector_placed = true


## True once the orange-prestige reward has auto-placed its one permanent
## deflector on the gold board — so we only seed it once (the player is then
## free to move or remove it).
func has_seeded_prestige_deflector() -> bool:
	return _prestige_deflector_seeded


func mark_prestige_deflector_seeded() -> void:
	_prestige_deflector_seeded = true


func reset() -> void:
	_peeked_boards.clear()
	_peeked_challenges = false
	# _autodropper_intro_seen / _deflector_intro_seen / _deflector_placed /
	# _prestige_deflector_seeded are intentionally NOT cleared — they're
	# permanent UX flags that survive prestige resets, like _peeked_challenges.


## Clears EVERYTHING, including the permanent UX flags that the prestige-
## preserving reset() intentionally keeps. Used only by SaveManager.full_reset()
## (the "Reset Game" main-menu option) for a true fresh start.
func full_reset() -> void:
	reset()
	_autodropper_intro_seen = false
	_deflector_intro_seen = false
	_deflector_placed = false
	_prestige_deflector_seeded = false


func serialize() -> Dictionary:
	var boards_data: Array[int] = []
	for board_type in _peeked_boards:
		if _peeked_boards[board_type]:
			boards_data.append(board_type)
	return {
		"peeked_boards": boards_data,
		"peeked_challenges": _peeked_challenges,
		"autodropper_intro_seen": _autodropper_intro_seen,
		"deflector_intro_seen": _deflector_intro_seen,
		"deflector_placed": _deflector_placed,
		"prestige_deflector_seeded": _prestige_deflector_seeded,
	}


func deserialize(data: Dictionary) -> void:
	_peeked_boards.clear()
	var boards_data: Array = data.get("peeked_boards", [])
	for board_type_int in boards_data:
		_peeked_boards[int(board_type_int)] = true
	_peeked_challenges = data.get("peeked_challenges", false)
	_autodropper_intro_seen = data.get("autodropper_intro_seen", false)
	_deflector_intro_seen = data.get("deflector_intro_seen", false)
	_deflector_placed = data.get("deflector_placed", false)
	_prestige_deflector_seeded = data.get("prestige_deflector_seeded", false)
