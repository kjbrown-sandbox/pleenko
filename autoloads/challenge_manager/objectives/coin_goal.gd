class_name CoinGoal
extends ChallengeObjective

@export var currency_type: Enums.CurrencyType
@export var amount: int
@export var exact: bool = false

func get_text() -> String:
	var cn := FormatUtils.currency_name(currency_type, false)
	if exact:
		return "Get exactly %d %s" % [amount, cn]
	return "Earn %d %s" % [amount, cn]
