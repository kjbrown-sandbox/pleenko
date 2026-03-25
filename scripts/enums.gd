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