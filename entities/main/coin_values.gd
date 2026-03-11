extends VBoxContainer

func _ready() -> void:
   for currency_type in Enums.CurrencyType.values():
      var label = Label.new()
      label.name = str(currency_type)
      var amount = CurrencyManager.get_balance(currency_type)
      var cap = CurrencyManager.get_cap(currency_type)
      var coin_name = Enums.CurrencyType.keys()[currency_type]
      label.text = "%s: %d / %d" % [coin_name, amount, cap]
      add_child(label)
   
   CurrencyManager.currency_changed.connect(_on_currency_changed)
   

func _on_currency_changed(type: Enums.CurrencyType, new_balance: int, cap: int) -> void:
   var label = get_node(str(type)) as Label
   var coin_name = Enums.CurrencyType.keys()[type]
   label.text = "%s: %d / %d" % [coin_name, new_balance, cap]