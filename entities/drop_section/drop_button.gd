class_name DropButton
extends VBoxContainer

class CurrencyNeeded:
   var type: Enums.CurrencyType
   var amount: int
   func _init(_type: Enums.CurrencyType, _amount: int) -> void:
      type = _type
      amount = _amount

signal drop_pressed
signal autodropper_adjust_requested(button_id: StringName, delta: int)

var currencies_needed: Array[CurrencyNeeded] = []
var button_id: StringName
var assigned_count: int = 0

@onready var _minus_button: Button = $HBoxContainer/MinusButton
@onready var _main_button: Button = $HBoxContainer/MainButton
@onready var _plus_button: Button = $HBoxContainer/PlusButton
@onready var _rate_label: Label = $RateLabel

var _autodropper_controls_visible: bool = false


func _ready():
   CurrencyManager.currency_changed.connect(_on_currency_changed)
   _main_button.pressed.connect(func(): drop_pressed.emit())
   _minus_button.pressed.connect(func(): autodropper_adjust_requested.emit(button_id, -1))
   _plus_button.pressed.connect(func(): autodropper_adjust_requested.emit(button_id, 1))
   _minus_button.focus_mode = Control.FOCUS_NONE
   _plus_button.focus_mode = Control.FOCUS_NONE
   # Hide autodropper controls by default
   _minus_button.visible = false
   _plus_button.visible = false
   _rate_label.visible = false


func setup(_currencies_needed: Array[CurrencyNeeded], _label: String, _button_id: StringName = &"") -> void:
   currencies_needed = _currencies_needed
   button_id = _button_id
   # Defer setting text until the node is ready
   if is_node_ready():
      _main_button.text = _label
   else:
      ready.connect(func(): _main_button.text = _label, CONNECT_ONE_SHOT)


func set_shortcut(shortcut: Shortcut) -> void:
   if is_node_ready():
      _main_button.shortcut = shortcut
   else:
      ready.connect(func(): _main_button.shortcut = shortcut, CONNECT_ONE_SHOT)


func show_autodropper_controls(vis: bool) -> void:
   _autodropper_controls_visible = vis
   if is_node_ready():
      _minus_button.visible = vis
      _plus_button.visible = vis
      _update_rate_label()
   else:
      ready.connect(func():
         _minus_button.visible = vis
         _plus_button.visible = vis
         _update_rate_label()
      , CONNECT_ONE_SHOT)


func update_autodropper_state(assigned: int, free_autodroppers: int) -> void:
   assigned_count = assigned
   if is_node_ready():
      _minus_button.disabled = assigned_count <= 0
      _plus_button.disabled = free_autodroppers <= 0
      _update_rate_label()


func _update_rate_label() -> void:
   if assigned_count > 0 and _autodropper_controls_visible:
      _rate_label.visible = true
      _rate_label.text = "Dropping %d/s" % assigned_count
   else:
      _rate_label.visible = false


func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
   if not is_node_ready():
      return
   # Check ALL required currencies, not just the one that changed
   for currency in currencies_needed:
      if not CurrencyManager.can_afford(currency.type, currency.amount):
         _main_button.disabled = true
         return
   _main_button.disabled = false
