class_name LevelData
extends Resource

@export var threshold: int
@export var message: String
@export var currency_type: Enums.CurrencyType = Enums.CurrencyType.GOLD_COIN
@export var rewards: Array[RewardData] = []
