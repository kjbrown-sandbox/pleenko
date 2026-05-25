class_name BombHazard
extends ChallengeHazard

## Wandering "bomb" hazard. One or more buckets are armed at a time, each with
## a countdown. Defusing (coin lands in the bomb bucket) earns a multiplier
## bonus and migrates the bomb. Letting one tick to zero detonates the column
## above it — pegs are destroyed and the bucket becomes unreachable.

@export var board_type: Enums.BoardType = Enums.BoardType.GOLD
@export_range(1, 16, 1) var bomb_count: int = 1
@export_range(1.0, 60.0, 0.5) var timer_seconds: float = 15.0
@export_range(1.0, 10.0, 0.1) var defuse_multiplier: float = 2.0


func create_runtime() -> ChallengeHazardRuntime:
	var runtime := BombHazardRuntime.new()
	runtime.hazard = self
	return runtime


func get_text() -> String:
	if bomb_count > 1:
		return "%d bombs roam the board — defuse for %.1fx, or the column dies." \
			% [bomb_count, defuse_multiplier]
	return "A bomb roams the board — defuse for %.1fx, or the column dies." \
		% [defuse_multiplier]
