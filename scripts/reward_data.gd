class_name RewardData
extends Resource

enum RewardType {
	UNLOCK_UPGRADE,
	DROP_COINS,
	UNLOCK_BOARD,
	UNLOCK_ADVANCED_BUCKET,
	UNLOCK_AUTODROPPER,
	UNLOCK_ADVANCED_AUTODROPPER,
}

@export var type: RewardType
## For UNLOCK_UPGRADE and UNLOCK_BOARD:
@export var board_type: Enums.BoardType
## For UNLOCK_UPGRADE:
@export var upgrade_type: Enums.UpgradeType
## For DROP_COINS:
@export var coin_count: int = 0
@export var coin_type: Enums.CurrencyType = Enums.CurrencyType.GOLD_COIN
@export var target_board: Enums.BoardType = Enums.BoardType.GOLD
