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


## Formats a number with K/M/B suffixes for readability.
## Under 10: one decimal (1.5K). 10+: whole number (10K, 200M).
## Examples: 1500 → "1.5K", 15000 → "15K", 2300000 → "2.3M"
static func format_number(value: int) -> String:
	if value < 1000:
		return str(value)
	elif value < 1_000_000:
		var k := value / 1000.0
		return _format_suffix(k, "K")
	elif value < 1_000_000_000:
		var m := value / 1_000_000.0
		return _format_suffix(m, "M")
	else:
		var b := value / 1_000_000_000.0
		return _format_suffix(b, "B")


## Formats a value with a suffix. Shows one decimal for < 10, whole numbers otherwise.
static func _format_suffix(val: float, suffix: String) -> String:
	if val < 10.0:
		var s := "%.1f" % val
		if s.ends_with(".0"):
			s = s.substr(0, s.length() - 2)
		return s + suffix
	return "%d%s" % [int(val), suffix]
