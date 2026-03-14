extends CanvasLayer

@onready var panel: PanelContainer = $Overlay/Panel
@onready var level_label: Label = $Overlay/Panel/VBoxContainer/LevelLabel
@onready var message_label: Label = $Overlay/Panel/VBoxContainer/MessageLabel
@onready var claim_button: Button = $Overlay/Panel/VBoxContainer/ClaimButton
@onready var overlay: ColorRect = $Overlay


func _ready() -> void:
	claim_button.pressed.connect(_on_claim_pressed)
	LevelManager.level_up_ready.connect(_on_level_up_ready)
	hide_dialog()


func _on_level_up_ready(level: int, level_data: LevelData) -> void:
	level_label.text = "Level %d!" % level
	message_label.text = level_data.message
	show_dialog()


func _on_claim_pressed() -> void:
	hide_dialog()
	LevelManager.claim_rewards()


func show_dialog() -> void:
	overlay.visible = true
	get_tree().paused = true


func hide_dialog() -> void:
	overlay.visible = false
	get_tree().paused = false
