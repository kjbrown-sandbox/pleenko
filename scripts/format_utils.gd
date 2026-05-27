class_name FormatUtils

## Human-readable name for a currency type (e.g. "Gold", "Raw orange").
## Strips "_coin" suffix so GOLD_COIN → "gold", ORANGE_COIN → "orange".
## Capital uses sentence case (first letter only), not Title Case.
static func currency_name(type: Enums.CurrencyType, capital: bool = true) -> String:
	var n: String = Enums.CurrencyType.keys()[type].to_lower().replace("_", " ").replace(" coin", "")
	return _sentence_case(n) if capital else n


## Human-readable name for a board type (e.g. "Gold", "orange").
static func board_name(type: Enums.BoardType, capital: bool = true) -> String:
	var n: String = Enums.BoardType.keys()[type].to_lower()
	return _sentence_case(n) if capital else n


## Sentence case: cap the first character only, leave the rest as-is.
## Distinct from String.capitalize() which Title-Cases every word.
static func _sentence_case(s: String) -> String:
	if s.is_empty():
		return s
	return s[0].to_upper() + s.substr(1)


## Human-readable name for an upgrade type (e.g. "add row", "drop rate").
static func upgrade_name(type: Enums.UpgradeType) -> String:
	return Enums.UpgradeType.keys()[type].to_lower().replace("_", " ")


## Shared prestige-reward phrasing. The prestige screen and the prestige dialog
## both describe the same rewards; routing the overlapping lines through these
## helpers keeps their wording identical and removes the duplicated tier loop.

## "gold", "gold and orange", ... — lower-tier display names for the multi-drop
## bonus, which applies to every tier below the prestiged one. "lower" if none.
static func lower_tier_names_phrase(board_type: Enums.BoardType) -> String:
	var idx := TierRegistry.get_tier_index(board_type)
	var lower_names: Array[String] = []
	for i in range(0, idx):
		lower_names.append(TierRegistry.get_tier_by_index(i).display_name.to_lower())
	return " and ".join(lower_names) if lower_names.size() > 0 else "lower"


static func multi_drop_phrase(target: String) -> String:
	return "+1 multi-drop for the %s board" % target


static func access_board_phrase(board_display_name: String) -> String:
	return "Access to the %s board" % board_display_name.to_lower()


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
