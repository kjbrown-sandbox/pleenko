class_name FormatUtils

## Human-readable name for a currency type (e.g. "gold", "raw orange").
## Strips "_coin" suffix so GOLD_COIN → "gold", ORANGE_COIN → "orange".
static func currency_name(type: Enums.CurrencyType, capital: bool = true) -> String:
	var n: String = Enums.CurrencyType.keys()[type].to_lower().replace("_", " ").replace(" coin", "")
	return n.capitalize() if capital else n


## Human-readable name for a board type (e.g. "Gold", "orange").
static func board_name(type: Enums.BoardType, capital: bool = true) -> String:
	var n: String = Enums.BoardType.keys()[type].to_lower()
	return n.capitalize() if capital else n


## Human-readable name for an upgrade type (e.g. "add row", "drop rate").
static func upgrade_name(type: Enums.UpgradeType) -> String:
	return Enums.UpgradeType.keys()[type].to_lower().replace("_", " ")
