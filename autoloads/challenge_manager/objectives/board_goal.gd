class_name BoardGoal
extends ChallengeObjective

@export var board_type: Enums.BoardType

func get_text() -> String:
	return "Unlock the %s board" % FormatUtils.board_name(board_type, false)
