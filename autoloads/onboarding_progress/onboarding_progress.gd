extends Node

## Persistent first-time-UX flags that survive prestige resets. Tracks whether
## the player has been "peeked" at newly-unlocked navigation targets (boards,
## challenges) so we don't replay the peek every cold start.

var _peeked_boards: Dictionary = {}  # BoardType -> bool
var _peeked_challenges: bool = false
var _revealed_milestone_tiers: Dictionary = {}  # tier_start_level (int) -> bool
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


## True once the milestone level bar has been spawn-in-revealed for the given
## tier (keyed by tier_start_level). Used by `LevelSection.play_peek_reveal_animation`
## to no-op a second peek to the same tier so the cascade only plays once.
func has_revealed_milestone_tier(tier_start_level: int) -> bool:
	return _revealed_milestone_tiers.get(tier_start_level, false)


func mark_milestone_tier_revealed(tier_start_level: int) -> void:
	_revealed_milestone_tiers[tier_start_level] = true


## Drop a tier's reveal flag so the next peek replays the spawn-in cascade.
## Called by `LevelSection._spawn_bar_explosion` at every tier-completion
## explosion, so each gold→orange (and orange→red) transition restarts
## the reveal flow cleanly.
func clear_milestone_tier_revealed(tier_start_level: int) -> void:
	_revealed_milestone_tiers.erase(tier_start_level)


## Drop the peeked flag for a board so `PeekAnimator` will queue a fresh
## peek the next time that board unlocks. Paired with
## `clear_milestone_tier_revealed` at tier-completion: both flags must be
## cleared for the bar's spawn-in to replay on a subsequent run-through.
func clear_peeked_board(type: Enums.BoardType) -> void:
	_peeked_boards.erase(type)


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
	_revealed_milestone_tiers.clear()
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
	var revealed_tiers: Array[int] = []
	for tier_start in _revealed_milestone_tiers:
		if _revealed_milestone_tiers[tier_start]:
			revealed_tiers.append(tier_start)
	return {
		"peeked_boards": boards_data,
		"peeked_challenges": _peeked_challenges,
		"autodropper_intro_seen": _autodropper_intro_seen,
		"deflector_intro_seen": _deflector_intro_seen,
		"deflector_placed": _deflector_placed,
		"prestige_deflector_seeded": _prestige_deflector_seeded,
		"revealed_milestone_tiers": revealed_tiers,
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
	_revealed_milestone_tiers.clear()
	var revealed_tiers: Array = data.get("revealed_milestone_tiers", [])
	for tier_start in revealed_tiers:
		_revealed_milestone_tiers[int(tier_start)] = true
