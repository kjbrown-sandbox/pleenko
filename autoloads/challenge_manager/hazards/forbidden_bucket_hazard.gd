class_name ForbiddenBucketHazard
extends ChallengeHazard

## A bucket whose contact detonates a circular blast of pegs + buckets around it
## (radius-based, vs the bomb hazard's strict-column cut). The challenge keeps
## running on a now-broken board: coins routed into the voided region fall off
## the map exactly like a coin caught in a voided bomb-column.

@export var board_type: Enums.BoardType
@export var bucket_index: int
## Local-space radius of the radial detonation centered on the bucket.
## ≈ 1–2 row heights feels visceral without obliterating the board.
@export var detonation_radius: float = 3.0


func create_runtime() -> ChallengeHazardRuntime:
	var runtime := ForbiddenBucketHazardRuntime.new()
	runtime.hazard = self
	return runtime


func get_text() -> String:
	return "Never land in bucket %d" % bucket_index
