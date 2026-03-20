class_name ChallengeConstraint
extends Resource

class NeverMoreThanXCoins:
	extends ChallengeConstraint
	@export var currency_type: Enums.CurrencyType
	@export var amount: int

class NeverLessThanXCoins:
	extends ChallengeConstraint
	@export var currency_type: Enums.CurrencyType
	@export var amount: int

class NeverTouchBucket:
	extends ChallengeConstraint
	@export var board_type: Enums.BoardType
	@export var bucket_index: int

class UpgradesLimited:
	extends ChallengeConstraint
	## If all_upgrades is true, no upgrades can be purchased.
	## Otherwise, only the listed upgrade types are blocked.
	@export var all_upgrades: bool = false
	@export var blocked_upgrades: Array[Enums.UpgradeType] = []

class OnlyOneBoard:
	extends ChallengeConstraint
	@export var board_type: Enums.BoardType
