class_name ForbiddenBucketHazard
extends ChallengeHazard

## A bucket that fails the challenge on contact. Migrated from the legacy
## NeverTouchBucket constraint — same fail-on-contact semantics, reclassified
## as a hazard so all "dangerous bucket" concepts live together.

@export var board_type: Enums.BoardType
@export var bucket_index: int


func create_runtime() -> ChallengeHazardRuntime:
	var runtime := ForbiddenBucketHazardRuntime.new()
	runtime.hazard = self
	return runtime


func get_text() -> String:
	return "Never land in bucket %d" % bucket_index
