class_name NeverMoreThanXCoins
extends ChallengeConstraint

@export var currency_type: Enums.CurrencyType
@export var amount: int

func get_text() -> String:
	return "Never have more than %d %s" % [amount, FormatUtils.currency_name(currency_type, false)]
