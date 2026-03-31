class_name NeverLessThanXCoins
extends ChallengeConstraint

@export var currency_type: Enums.CurrencyType
@export var amount: int

func get_text() -> String:
	return "Never have less than %d %s" % [amount, FormatUtils.currency_name(currency_type, false)]
