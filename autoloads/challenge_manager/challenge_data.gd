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

## Growth mode for this challenge's boards.
##
## false (the default, and what every existing .tres gets with no edit): boards
## are UNCAPPED — ADD_ROW / add_two_rows grow the main triangle indefinitely, as
## they always have — and never sprout earrings. StartingBoards authors exact
## sizes by looping add_two_rows, so this is what lets a challenge specify a
## board bigger than the normal-play 9-bucket cap.
## true: boards behave like normal play — the main triangle caps, then earrings.
@export var grows_earrings: bool = false
@export var rewards: Array[ChallengeRewardData] = []
