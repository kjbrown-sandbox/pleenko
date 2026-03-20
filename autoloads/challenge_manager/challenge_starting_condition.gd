class_name ChallengeStartingCondition
extends Resource

class StartingUpgrades:
	extends ChallengeStartingCondition
	@export var board_type: Enums.BoardType
	@export var upgrade_type: Enums.UpgradeType
	@export var level: int

class StartingBoards:
	extends ChallengeStartingCondition
	@export var board_type: Enums.BoardType
	@export var rows: int

class StartingCoins:
	extends ChallengeStartingCondition
	@export var currency_type: Enums.CurrencyType
	@export var amount: int
