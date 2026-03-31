class_name Enums

enum BoardType {
	GOLD,
	ORANGE,
	RED
}

enum CurrencyType {
	GOLD_COIN,
	RAW_ORANGE,
	ORANGE_COIN,
	RAW_RED,
	RED_COIN
}

enum UpgradeType {
	ADD_ROW,
	BUCKET_VALUE,
	DROP_RATE,
	QUEUE,
	AUTODROPPER,
}

static func currency_for_board(board_type: BoardType) -> CurrencyType:
	return TierRegistry.primary_currency(board_type)


## Returns the currency used to raise caps on a board's upgrades.
## Returns -1 if no cap-raise currency exists (last tier).
static func cap_raise_currency_for_board(board_type: BoardType) -> CurrencyType:
	return TierRegistry.cap_raise_currency(board_type)


static func currency_name(type: CurrencyType, capital: bool = true) -> String:
	var name: String = CurrencyType.keys()[type].to_lower().replace("_", " ").replace(" coin", "")
	return name.capitalize() if capital else name


static func board_name(type: BoardType, capital: bool = true) -> String:
	var name: String = BoardType.keys()[type].to_lower()
	return name.capitalize() if capital else name


static func upgrade_name(type: UpgradeType) -> String:
	return UpgradeType.keys()[type].to_lower().replace("_", " ")
