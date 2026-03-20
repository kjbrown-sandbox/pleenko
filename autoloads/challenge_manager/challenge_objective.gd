class_name ChallengeObjective
extends Resource

class CoinGoal:
	extends ChallengeObjective
	@export var currency_type: Enums.CurrencyType
	@export var amount: int
	@export var exact: bool = false

class BoardGoal:
	extends ChallengeObjective
	@export var board_type: Enums.BoardType

class Survive:
	extends ChallengeObjective
	## Player must not go below 0 of a currency while autodroppers run.
	@export var board_type: Enums.BoardType
	@export var autodropper_count: int = 1

class GetSameBucketXTimes:
	extends ChallengeObjective
	@export var board_type: Enums.BoardType
	@export var times: int
	@export var in_a_row: bool = false

class LandInEveryBucket:
	extends ChallengeObjective
	@export var board_type: Enums.BoardType

class EarnWithinXDrops:
	extends ChallengeObjective
	@export var currency_type: Enums.CurrencyType
	@export var amount: int
	@export var max_drops: int
