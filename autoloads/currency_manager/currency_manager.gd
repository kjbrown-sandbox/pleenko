extends Node

signal currency_changed(type: Enums.CurrencyType, new_balance: int, new_cap: int)

var balances: Dictionary[Enums.CurrencyType, int] = {}
var caps: Dictionary[Enums.CurrencyType, int] = {}

func _ready() -> void:
   # Initialize balances and caps for each currency type
   for currency_type in Enums.CurrencyType.values():
      balances[currency_type] = 0
      caps[currency_type] = 50 if currency_type in [Enums.CurrencyType.RAW_ORANGE, Enums.CurrencyType.RAW_RED] else 500
   balances[Enums.CurrencyType.GOLD_COIN] = 5 

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