extends CanvasLayer

signal closed

@onready var overlay: ColorRect = $Overlay
@onready var title_label: Label = $Overlay/Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var earnings_label: Label = $Overlay/Panel/MarginContainer/VBoxContainer/EarningsLabel
@onready var nice_button: Button = $Overlay/Panel/MarginContainer/VBoxContainer/NiceButton


func _ready() -> void:
	nice_button.pressed.connect(_on_nice_pressed)
	hide_dialog()
	_apply_theme()


func _apply_theme() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var white: Color = t.bg_shade_6
	title_label.add_theme_color_override("font_color", white)
	title_label.add_theme_font_size_override("font_size", 28)
	earnings_label.add_theme_color_override("font_color", white)
	t.apply_button_theme(nice_button)


## Show the dialog with offline earnings. earnings is a Dictionary of
## currency key (string) -> amount earned (int).
func show_earnings(earnings: Dictionary) -> void:
	_apply_theme()
	var lines: PackedStringArray = []
	for key in earnings:
		var amount: int = earnings[key]
		var display_name: String = key.to_lower().replace("_", " ")
		lines.append("+%d %s" % [amount, display_name])
	earnings_label.text = "\n".join(lines)
	overlay.visible = true


func hide_dialog() -> void:
	overlay.visible = false


func _on_nice_pressed() -> void:
	hide_dialog()
	closed.emit()
