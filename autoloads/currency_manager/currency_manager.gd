extends Node

signal currency_changed(type: Enums.CurrencyType, new_balance: int, new_cap: int)

var balances: Dictionary[Enums.CurrencyType, int] = {}
var caps: Dictionary[Enums.CurrencyType, int] = {}
var _cap_raise_levels: Dictionary[Enums.CurrencyType, int] = {}

func _ready() -> void:
   # Initialize balances and caps for each currency type
   for currency_type in Enums.CurrencyType.values():
      balances[currency_type] = 0
      caps[currency_type] = 50 if currency_type in [Enums.CurrencyType.RAW_ORANGE, Enums.CurrencyType.RAW_RED] else 500
      _cap_raise_levels[currency_type] = 0
   balances[Enums.CurrencyType.GOLD_COIN] = 1

func can_afford(type: Enums.CurrencyType, amount: int) -> bool:
   return amount <= balances[type]

func get_balance(type: Enums.CurrencyType) -> int:
   return balances[type]

func get_cap(type: Enums.CurrencyType) -> int:
   return caps[type]

func add(type: Enums.CurrencyType, amount: int) -> void:
   var cap = caps[type]
   balances[type] = min(cap, balances[type] + amount)
   currency_changed.emit(type, balances[type], cap)

func spend(type: Enums.CurrencyType, amount: int) -> bool:
   if !can_afford(type, amount): return false

   balances[type] -= amount
   currency_changed.emit(type, balances[type], caps[type])
   return true


## Returns the currency used to raise this currency's cap, or -1 if none.
func cap_raise_currency(type: Enums.CurrencyType) -> int:
   match type:
      Enums.CurrencyType.GOLD_COIN:
         return Enums.CurrencyType.ORANGE_COIN
      Enums.CurrencyType.RAW_ORANGE, Enums.CurrencyType.ORANGE_COIN:
         return Enums.CurrencyType.RED_COIN
      _:
         return -1


## Returns how much the cap increases per raise: +500 for coins, +50 for raw.
func cap_raise_amount(type: Enums.CurrencyType) -> int:
   match type:
      Enums.CurrencyType.RAW_ORANGE, Enums.CurrencyType.RAW_RED:
         return 50
      _:
         return 500


## Returns the board type whose unlock gates this currency's cap raise.
## GOLD_COIN -> GOLD (needs orange board), RAW_ORANGE/ORANGE_COIN -> ORANGE (needs red board).
func cap_raise_board(type: Enums.CurrencyType) -> int:
   match type:
      Enums.CurrencyType.GOLD_COIN:
         return Enums.BoardType.GOLD
      Enums.CurrencyType.RAW_ORANGE, Enums.CurrencyType.ORANGE_COIN:
         return Enums.BoardType.ORANGE
      _:
         return -1


func get_cap_raise_cost(type: Enums.CurrencyType) -> int:
   return 1 + 2 * _cap_raise_levels[type]


func can_buy_cap_raise(type: Enums.CurrencyType) -> bool:
   var cost_currency: int = cap_raise_currency(type)
   if cost_currency == -1:
      return false
   var board: int = cap_raise_board(type)
   if board == -1 or not UpgradeManager.is_cap_raise_available(board):
      return false
   return can_afford(cost_currency, get_cap_raise_cost(type))


func buy_cap_raise(type: Enums.CurrencyType) -> bool:
   if not can_buy_cap_raise(type):
      return false
   var cost_currency: int = cap_raise_currency(type)
   spend(cost_currency, get_cap_raise_cost(type))
   _cap_raise_levels[type] += 1
   caps[type] += cap_raise_amount(type)
   currency_changed.emit(type, balances[type], caps[type])
   return true
