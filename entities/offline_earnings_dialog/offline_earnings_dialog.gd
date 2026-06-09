extends CanvasLayer

signal closed

@onready var overlay: FrostedOverlay = $Overlay
@onready var title_label: Label = $Overlay/CenterContainer/VBoxContainer/TitleLabel
@onready var earnings_label: Label = $Overlay/CenterContainer/VBoxContainer/EarningsLabel
@onready var nice_button: RefinedBaselineButton = $Overlay/CenterContainer/VBoxContainer/NiceButton


func _ready() -> void:
	nice_button.main_pressed.connect(_on_nice_pressed)
	hide_dialog()
	_apply_theme()


func _apply_theme() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var white: Color = t.bg_shade_6
	title_label.add_theme_color_override("font_color", white)
	title_label.add_theme_font_size_override("font_size", 28)
	earnings_label.add_theme_color_override("font_color", white)


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
	overlay.fade_in()


func hide_dialog() -> void:
	overlay.visible = false


func _on_nice_pressed() -> void:
	overlay.fade_out(func(): overlay.visible = false)
	closed.emit()
