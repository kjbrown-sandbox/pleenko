class_name OnlyOneBoard
extends ChallengeConstraint

@export var board_type: Enums.BoardType

func get_text() -> String:
	return "Only %s board" % FormatUtils.board_name(board_type, false)
