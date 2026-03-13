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