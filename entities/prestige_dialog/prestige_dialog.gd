extends CanvasLayer

@onready var overlay: ColorRect = $Overlay
@onready var message_label: Label = $Overlay/Panel/VBoxContainer/MessageLabel
@onready var claim_button: Button = $Overlay/Panel/VBoxContainer/ClaimButton

var _pending_board_type: Enums.BoardType


func _ready() -> void:
	claim_button.pressed.connect(_on_claim_pressed)
	PrestigeManager.prestige_triggered.connect(_on_prestige_triggered)
	hide_dialog()


func _on_prestige_triggered(board_type: Enums.BoardType) -> void:
	_pending_board_type = board_type

	var board_name: String = Enums.BoardType.keys()[board_type].to_lower().capitalize()
	# Multi-drop bonus applies to all boards below the prestige tier
	var multi_drop_target: String
	match board_type:
		Enums.BoardType.ORANGE:
			multi_drop_target = "gold"
		Enums.BoardType.RED:
			multi_drop_target = "gold and orange"
		_:
			multi_drop_target = "lower"

	message_label.text = "+1 multi-drop for the %s board\nAccess to the %s board" % [multi_drop_target, board_name]
	show_dialog()


func _on_claim_pressed() -> void:
	hide_dialog()
	PrestigeManager.claim_prestige(_pending_board_type)
	SaveManager.reset_game()


func show_dialog() -> void:
	overlay.visible = true


func hide_dialog() -> void:
	overlay.visible = false
