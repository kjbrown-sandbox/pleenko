extends VBoxContainer

var _cap_buttons: Dictionary = {}  # CurrencyType -> Button

func _ready() -> void:
   for currency_type in Enums.CurrencyType.values():
      var row := HBoxContainer.new()
      row.name = str(currency_type)

      var label := Label.new()
      label.name = "Label"
      var amount = CurrencyManager.get_balance(currency_type)
      var cap = CurrencyManager.get_cap(currency_type)
      var coin_name = Enums.CurrencyType.keys()[currency_type]
      label.text = "%s: %d / %d" % [coin_name, amount, cap]
      row.add_child(label)

      # Add cap raise button (hidden until next board is unlocked)
      if CurrencyManager.cap_raise_currency(currency_type) != -1:
         var button := Button.new()
         button.name = "CapButton"
         button.focus_mode = Control.FOCUS_NONE
         button.visible = false
         button.pressed.connect(_on_cap_raise_pressed.bind(currency_type))
         row.add_child(button)
         _cap_buttons[currency_type] = button

      add_child(row)

   CurrencyManager.currency_changed.connect(_on_currency_changed)
   UpgradeManager.cap_raise_unlocked.connect(_on_cap_raise_unlocked)

   # Check if any cap raises are already available
   _update_all_cap_buttons()


func _on_currency_changed(type: Enums.CurrencyType, new_balance: int, cap: int) -> void:
   var row = get_node(str(type))
   var label = row.get_node("Label") as Label
   var coin_name = Enums.CurrencyType.keys()[type]
   label.text = "%s: %d / %d" % [coin_name, new_balance, cap]
   _update_all_cap_buttons()


func _on_cap_raise_unlocked(_board_type: Enums.BoardType) -> void:
   _update_all_cap_buttons()


func _on_cap_raise_pressed(type: Enums.CurrencyType) -> void:
   CurrencyManager.buy_cap_raise(type)


func _update_all_cap_buttons() -> void:
   for currency_type in _cap_buttons:
      var button: Button = _cap_buttons[currency_type]
      var board: int = CurrencyManager.cap_raise_board(currency_type)
      button.visible = board != -1 and UpgradeManager.is_cap_raise_available(board)
      if button.visible:
         var cost := CurrencyManager.get_cap_raise_cost(currency_type)
         var raise_amount := CurrencyManager.cap_raise_amount(currency_type)
         button.text = "+%d (%d)" % [raise_amount, cost]
         button.disabled = not CurrencyManager.can_buy_cap_raise(currency_type)
