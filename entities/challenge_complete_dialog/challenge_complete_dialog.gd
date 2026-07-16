extends CanvasLayer

signal closed

@onready var overlay: FrostedOverlay = $Overlay
@onready var title_label: Label = $Overlay/CenterContainer/VBoxContainer/TitleLabel
@onready var stats_label: Label = $Overlay/CenterContainer/VBoxContainer/StatsLabel
@onready var rewards_label: Label = $Overlay/CenterContainer/VBoxContainer/RewardsLabel
@onready var ok_button: RefinedBaselineButton = $Overlay/CenterContainer/VBoxContainer/OkButton


func _ready() -> void:
	ok_button.main_pressed.connect(_on_ok_pressed)
	hide_dialog()
	_apply_theme()


func _apply_theme() -> void:
	var t: VisualTheme = ThemeProvider.theme
	title_label.add_theme_color_override("font_color", t.normal_text_color)
	title_label.add_theme_font_size_override("font_size", 44)
	stats_label.add_theme_color_override("font_color", t.body_text_color)
	stats_label.add_theme_font_size_override("font_size", 26)
	rewards_label.add_theme_color_override("font_color", t.body_text_color)
	rewards_label.add_theme_font_size_override("font_size", 26)
	var rewards_header: Label = $Overlay/CenterContainer/VBoxContainer/RewardsHeader
	rewards_header.add_theme_color_override("font_color", t.normal_text_color)
	rewards_header.add_theme_font_size_override("font_size", 30)


## Show the dialog with stats and reward diff strings. On a first clear the OK
## button reads "Claim rewards"; on a replay (already completed) it reads
## "Continue" since no new rewards are granted.
func show_with_results(stats: Dictionary, reward_lines: Array[String], is_first_completion: bool = true) -> void:
	_apply_theme()
	ok_button.title_text = "Claim rewards" if is_first_completion else "Continue"
	stats_label.text = _format_stats(stats)
	if reward_lines.is_empty():
		rewards_label.text = "(no new rewards)"
	else:
		rewards_label.text = "\n".join(reward_lines)
	overlay.fade_in()


func hide_dialog() -> void:
	overlay.visible = false


func _on_ok_pressed() -> void:
	overlay.fade_out(func(): overlay.visible = false)
	closed.emit()


func _format_stats(stats: Dictionary) -> String:
	var parts: PackedStringArray = []
	if stats.has("time_taken"):
		var t: float = stats["time_taken"]
		var mins: int = int(t) / 60
		var secs: int = int(t) % 60
		parts.append("Time: %d:%02d" % [mins, secs])
	if stats.has("coins_dropped"):
		parts.append("Coins dropped: %d" % stats["coins_dropped"])
	return "\n".join(parts)
