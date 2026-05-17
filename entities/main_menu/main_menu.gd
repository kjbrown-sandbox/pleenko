class_name MainMenu
extends Node3D

const MainScene := preload("res://entities/main/main.tscn")

@onready var play_button: Button = $CanvasLayer/HBoxContainer/PlayButton
@onready var reset_button: Button = $CanvasLayer/HBoxContainer/ResetButton
@onready var confirm_overlay: ColorRect = $ConfirmLayer/Overlay
@onready var confirm_panel: PanelContainer = $ConfirmLayer/Overlay/Panel
@onready var confirm_label: Label = $ConfirmLayer/Overlay/Panel/VBox/ConfirmLabel
@onready var cancel_button: Button = $ConfirmLayer/Overlay/Panel/VBox/ButtonRow/CancelButton
@onready var confirm_reset_button: Button = $ConfirmLayer/Overlay/Panel/VBox/ButtonRow/ConfirmResetButton


func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	t.apply_button_theme(play_button)
	t.apply_button_theme(reset_button)
	t.apply_button_theme(cancel_button)
	t.apply_button_theme(confirm_reset_button)

	confirm_overlay.color = t.overlay_color
	# The default PanelContainer stylebox is a dark engine grey, which kills the
	# dark themed text. Give it an intentional light card from the palette so the
	# dark text reads — same dark-on-light contrast as the rest of the menu UI.
	# Colors come from the palette; border width / padding are plain layout
	# constants (not part of the button theme), matching options_dialog.gd.
	var card := StyleBoxFlat.new()
	card.bg_color = t.bg_shade_6
	card.border_color = t.button_border_color
	card.set_border_width_all(2)
	card.set_corner_radius_all(t.button_border_radius)
	card.set_content_margin_all(28.0)
	confirm_panel.add_theme_stylebox_override("panel", card)
	confirm_label.add_theme_color_override("font_color", t.normal_text_color)

	play_button.pressed.connect(_on_play_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	confirm_reset_button.pressed.connect(_on_confirm_reset_pressed)

	confirm_overlay.visible = false


func _on_play_pressed() -> void:
	SceneManager.set_new_scene(MainScene)


func _on_reset_pressed() -> void:
	confirm_overlay.visible = true


func _on_cancel_pressed() -> void:
	confirm_overlay.visible = false


func _on_confirm_reset_pressed() -> void:
	# full_reset() clears all autoload state in memory and wipes the save, so
	# no scene reload is needed — the menu shows no save-derived state.
	SaveManager.full_reset()
	confirm_overlay.visible = false
