class_name DropButton
extends Button

class CurrencyNeeded:
   var type: Enums.CurrencyType
   var amount: int
   func _init(_type: Enums.CurrencyType, _amount: int) -> void:
      type = _type
      amount = _amount

var currencies_needed: Array[CurrencyNeeded] = []

func _ready():
   CurrencyManager.currency_changed.connect(_on_currency_changed)

func setup(_currencies_needed: Array[CurrencyNeeded], _label: String) -> void:
   currencies_needed = _currencies_needed
   text = _label

func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
   for currency in currencies_needed:
      if currency.type == _type:
         disabled = not CurrencyManager.can_afford(currency.type, currency.amount)
         return
   disabled = false




