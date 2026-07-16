class_name ChallengeData
extends Resource

@export var id: String
@export var display_name: String
@export var time_limit_seconds: float

## Optional per-challenge explanation shown on the failure screen beneath the
## reason. Empty for challenges that don't need a hint (no row is shown then).
@export_multiline var failure_hint: String = ""

@export var objectives: Array[ChallengeObjective] = []
@export var constraints: Array[ChallengeConstraint] = []
@export var starting_conditions: Array[ChallengeStartingCondition] = []
@export var hazards: Array[ChallengeHazard] = []
@export var rewards: Array[ChallengeRewardData] = []
