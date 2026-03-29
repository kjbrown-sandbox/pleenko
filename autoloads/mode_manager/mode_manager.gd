extends Node

enum Mode { MAIN, CHALLENGES }

signal mode_changed(new_mode: Mode)

var current_mode: Mode = Mode.MAIN


func switch_to_challenges() -> void:
	if not are_challenges_unlocked():
		return
	if current_mode == Mode.CHALLENGES:
		return
	current_mode = Mode.CHALLENGES
	mode_changed.emit(current_mode)


func switch_to_main() -> void:
	if current_mode == Mode.MAIN:
		return
	current_mode = Mode.MAIN
	mode_changed.emit(current_mode)


func is_main() -> bool:
	return current_mode == Mode.MAIN


func is_challenges() -> bool:
	return current_mode == Mode.CHALLENGES


func are_challenges_unlocked() -> bool:
	for board_type in Enums.BoardType.values():
		if PrestigeManager.is_board_unlocked_permanently(board_type):
			return true
	return false
