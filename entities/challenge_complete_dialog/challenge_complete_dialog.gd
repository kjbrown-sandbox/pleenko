extends CanvasLayer

signal closed

@onready var overlay: ColorRect = $Overlay
@onready var title_label: Label = $Overlay/Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var stats_label: Label = $Overlay/Panel/MarginContainer/VBoxContainer/StatsLabel
@onready var rewards_label: Label = $Overlay/Panel/MarginContainer/VBoxContainer/RewardsLabel
@onready var ok_button: Button = $Overlay/Panel/MarginContainer/VBoxContainer/OkButton


func _ready() -> void:
	ok_button.pressed.connect(_on_ok_pressed)
	hide_dialog()
	_apply_theme()


func _apply_theme() -> void:
	var t: VisualTheme = ThemeProvider.theme
	title_label.add_theme_color_override("font_color", t.normal_text_color)
	title_label.add_theme_font_size_override("font_size", 32)
	stats_label.add_theme_color_override("font_color", t.body_text_color)
	rewards_label.add_theme_color_override("font_color", t.body_text_color)
	$Overlay/Panel/MarginContainer/VBoxContainer/RewardsHeader.add_theme_color_override("font_color", t.normal_text_color)
	t.apply_button_theme(ok_button)


## Show the dialog with stats and reward diff strings.
func show_with_results(stats: Dictionary, reward_lines: Array[String]) -> void:
	_apply_theme()
	stats_label.text = _format_stats(stats)
	if reward_lines.is_empty():
		rewards_label.text = "(no new rewards)"
	else:
		rewards_label.text = "\n".join(reward_lines)
	overlay.visible = true


func hide_dialog() -> void:
	overlay.visible = false


func _on_ok_pressed() -> void:
	hide_dialog()
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
