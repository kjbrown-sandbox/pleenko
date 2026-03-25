extends Node

signal currency_changed(type: Enums.CurrencyType, new_balance: int, new_cap: int)

var balances: Dictionary[Enums.CurrencyType, int] = {}
var caps: Dictionary[Enums.CurrencyType, int] = {}
var _cap_raise_levels: Dictionary[Enums.CurrencyType, int] = {}

func _ready() -> void:
   reset()


func reset() -> void:
   for currency_type in Enums.CurrencyType.values():
      balances[currency_type] = 0
      var tier := TierRegistry.get_tier_for_currency(currency_type)
      if tier:
         if TierRegistry.is_raw_currency(currency_type):
            caps[currency_type] = tier.raw_cap
         else:
            caps[currency_type] = tier.primary_cap
      else:
         caps[currency_type] = 500
      _cap_raise_levels[currency_type] = 0
   # Starting tier gets 1 coin
   var starting := TierRegistry.get_tier_by_index(0)
   if starting:
      balances[starting.primary_currency] = 1

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
## A tier's currencies' caps are raised using the next tier's primary currency.
func cap_raise_currency(type: Enums.CurrencyType) -> int:
   var tier := TierRegistry.get_tier_for_currency(type)
   if not tier:
      return -1
   return TierRegistry.cap_raise_currency(tier.board_type)


## Returns how much the cap increases per raise.
func cap_raise_amount(type: Enums.CurrencyType) -> int:
   var tier := TierRegistry.get_tier_for_currency(type)
   if not tier:
      return 500
   if TierRegistry.is_raw_currency(type):
      return tier.raw_cap  # raw currencies raise by their initial cap amount
   return tier.primary_cap  # primary currencies raise by their initial cap amount


## Returns the board type that gates this currency's cap raise.
## A currency's cap raise is gated by the tier that owns it having a next tier unlocked.
func cap_raise_board(type: Enums.CurrencyType) -> int:
   var tier := TierRegistry.get_tier_for_currency(type)
   if not tier:
      return -1
   # Cap raises are available when this tier's board exists
   # (the cost currency comes from the next tier)
   if TierRegistry.cap_raise_currency(tier.board_type) == -1:
      return -1
   return tier.board_type


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


func serialize() -> Dictionary:
   var data := {}
   for currency_type in Enums.CurrencyType.values():
      var key: String = Enums.CurrencyType.keys()[currency_type]
      data[key] = {
         "balance": balances[currency_type],
         "cap": caps[currency_type],
         "cap_raise_level": _cap_raise_levels[currency_type],
      }
   return data


func deserialize(data: Dictionary) -> void:
   for currency_type in Enums.CurrencyType.values():
      var key: String = Enums.CurrencyType.keys()[currency_type]
      if key in data:
         var entry: Dictionary = data[key]
         balances[currency_type] = entry.get("balance", 0)
         caps[currency_type] = entry.get("cap", 500)
         _cap_raise_levels[currency_type] = entry.get("cap_raise_level", 0)
   # Emit currency_changed for each type so UI updates
   for currency_type in Enums.CurrencyType.values():
      currency_changed.emit(currency_type, balances[currency_type], caps[currency_type])
