class_name EarnWithinXDrops
extends ChallengeObjective

@export var currency_type: Enums.CurrencyType
@export var amount: int
@export var max_drops: int

func get_text() -> String:
	var cn := FormatUtils.currency_name(currency_type, false)
	return "Earn %d %s in %d drops" % [amount, cn, max_drops]
