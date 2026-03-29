class_name ChallengeData
extends Resource

@export var id: String
@export var display_name: String
@export var time_limit_seconds: float

@export var objectives: Array[ChallengeObjective] = []
@export var constraints: Array[ChallengeConstraint] = []
@export var starting_conditions: Array[ChallengeStartingCondition] = []
@export var rewards: Array[ChallengeRewardData] = []
