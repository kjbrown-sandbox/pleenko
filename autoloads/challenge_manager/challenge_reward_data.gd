class_name ChallengeRewardData
extends Resource

enum RewardType {
	UNLOCK,
	STARTING_MODIFIER,
	PERMANENT_UPGRADE,
}

enum UnlockType {
	HOLD_TO_DROP,
}

enum ModifierType {
	STARTING_AUTODROPPERS,
	STARTING_COINS,
	MULTI_DROP,
	ADVANCED_COIN_MULTIPLIER,
	BUCKET_VALUE_PERCENT,
}

@export var type: RewardType
@export var unlock_type: UnlockType
@export var modifier_type: ModifierType
@export var modifier_amount: float = 1.0
@export var currency_type: Enums.CurrencyType
@export var board_type: Enums.BoardType
@export var upgrade_type: Enums.UpgradeType
@export var description: String = ""
