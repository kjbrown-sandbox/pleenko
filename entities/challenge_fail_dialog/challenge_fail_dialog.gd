extends CanvasLayer

## Failure screen shown when a challenge fails. Mirrors ChallengeCompleteDialog
## (the victory screen) but states the failure reason + an optional per-challenge
## hint, and offers Retry / Return to Main instead of a single Continue button.
signal retry_pressed
signal return_pressed

@onready var overlay: FrostedOverlay = $Overlay
@onready var title_label: Label = $Overlay/CenterContainer/VBoxContainer/TitleLabel
@onready var reason_label: Label = $Overlay/CenterContainer/VBoxContainer/ReasonLabel
@onready var hint_label: Label = $Overlay/CenterContainer/VBoxContainer/HintLabel
@onready var retry_button: RefinedBaselineButton = $Overlay/CenterContainer/VBoxContainer/ButtonRow/RetryButton
@onready var return_button: RefinedBaselineButton = $Overlay/CenterContainer/VBoxContainer/ButtonRow/ReturnButton


func _ready() -> void:
	retry_button.main_pressed.connect(_on_retry_pressed)
	return_button.main_pressed.connect(_on_return_pressed)
	hide_dialog()
	_apply_theme()


func _apply_theme() -> void:
	var t: VisualTheme = ThemeProvider.theme
	title_label.add_theme_color_override("font_color", t.red_main)
	title_label.add_theme_font_size_override("font_size", 32)
	reason_label.add_theme_color_override("font_color", t.body_text_color)
	hint_label.add_theme_color_override("font_color", t.body_text_color)


## Show the failure screen with the reason string and an optional hint (the hint
## row stays hidden when empty so challenges without an authored hint show none).
func show_with_failure(reason: String, hint: String) -> void:
	_apply_theme()
	reason_label.text = reason
	hint_label.text = hint
	hint_label.visible = not hint.is_empty()
	overlay.fade_in()


func hide_dialog() -> void:
	overlay.visible = false


func _on_retry_pressed() -> void:
	retry_pressed.emit()


func _on_return_pressed() -> void:
	return_pressed.emit()
