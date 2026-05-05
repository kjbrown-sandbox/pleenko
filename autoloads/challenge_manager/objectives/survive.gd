class_name Survive
extends ChallengeObjective

@export var board_type: Enums.BoardType
@export var autodropper_count: int = 1
## Real-time delay before the autodroppers appear and start dropping.
@export var start_delay: float = 0.0
## After the autodroppers start, how long the player must survive.
@export var survive_duration: float = 30.0

func get_text() -> String:
	# return "Survive with %d autodropper(s)" % autodropper_count
	var tier_name: String = TierRegistry.get_tier(board_type).display_name.to_lower()
	return "Survive the %s autodropper%s" % [tier_name, "s" if autodropper_count != 1 else ""]
