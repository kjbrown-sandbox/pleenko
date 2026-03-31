class_name NeverTouchBucket
extends ChallengeConstraint

@export var board_type: Enums.BoardType
@export var bucket_index: int

func get_text() -> String:
	return "Never land in bucket %d" % bucket_index
