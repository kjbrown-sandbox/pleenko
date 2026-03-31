class_name GetSameBucketXTimes
extends ChallengeObjective

@export var board_type: Enums.BoardType
@export var times: int
@export var in_a_row: bool = false

func get_text() -> String:
	if in_a_row:
		return "Hit the same bucket %d times in a row" % times
	return "Hit the same bucket %d times" % times
