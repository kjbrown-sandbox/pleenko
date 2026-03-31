class_name HitXBucketYTimes
extends ChallengeObjective

@export var board_type: Enums.BoardType
@export var bucket_index: int
@export var times: int

func get_text() -> String:
	return "Land a coin in the target bucket %d times" % times
