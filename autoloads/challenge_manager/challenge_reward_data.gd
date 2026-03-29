class_name ChallengeRewardData
extends Resource

enum RewardType {
	UNLOCK,
	STARTING_MODIFIER,
}

enum UnlockType {
	HOLD_TO_DROP,
}

enum ModifierType {
	STARTING_AUTODROPPERS,
	STARTING_COINS,
	MULTI_DROP,
}

@export var type: RewardType
@export var unlock_type: UnlockType
@export var modifier_type: ModifierType
@export var modifier_amount: int = 1
@export var currency_type: Enums.CurrencyType
@export var board_type: Enums.BoardType
@export var description: String = ""
