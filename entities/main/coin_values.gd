extends VBoxContainer

func _ready() -> void:
   for currency_type in Enums.CurrencyType.values():
      var label = Label.new()
      label.name = str(currency_type)
      var amount = CurrencyManager.get_balance(currency_type)
      var cap = CurrencyManager.get_cap(currency_type)
      var name = Enums.CurrencyType.keys()[currency_type]
      label.text = "%s: %d / %d" % [name, amount, cap]
      add_child(label)