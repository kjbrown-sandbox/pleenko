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
}

static func currency_for_board(board_type: BoardType) -> CurrencyType:
   match board_type:
      BoardType.GOLD:
         return CurrencyType.GOLD_COIN
      BoardType.ORANGE:
         return CurrencyType.ORANGE_COIN
      BoardType.RED:
         return CurrencyType.RED_COIN
      _:
         return CurrencyType.GOLD_COIN


## Returns the currency used to raise caps on a board's upgrades.
## Gold upgrades cost orange, orange upgrades cost red.
## Returns -1 if no cap-raise currency exists (e.g. red has no next tier yet).
static func cap_raise_currency_for_board(board_type: BoardType) -> CurrencyType:
   match board_type:
      BoardType.GOLD:
         return CurrencyType.ORANGE_COIN
      BoardType.ORANGE:
         return CurrencyType.RED_COIN
      _:
         return -1