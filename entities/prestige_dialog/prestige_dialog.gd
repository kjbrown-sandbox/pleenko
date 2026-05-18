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

	var tier := TierRegistry.get_tier(board_type)
	var board_name: String = tier.display_name if tier else "Unknown"
	# Multi-drop bonus applies to all tiers below this one
	var multi_drop_target := FormatUtils.lower_tier_names_phrase(board_type)

	message_label.text = "%s\n%s" % [
		FormatUtils.multi_drop_phrase(multi_drop_target),
		FormatUtils.access_board_phrase(board_name),
	]
	show_dialog()


func _on_claim_pressed() -> void:
	hide_dialog()
	PrestigeManager.claim_prestige(_pending_board_type)
	SaveManager.reset_game()


func show_dialog() -> void:
	overlay.visible = true


func hide_dialog() -> void:
	overlay.visible = false
