extends Control

@onready var progress_bar: HBoxContainer = $HBoxContainer/ProgressBar
@onready var level_label: Label = $HBoxContainer/LevelLabel

var max_value: int = 0
var value: int = 0

# func update_text(new_text: String) -> void:
# 	main_button.text = new_text
# 	if _base_label:
# 		_base_label.text = new_text
# 	if _fill_label:
# 		_fill_label.text = new_text


# func set_fill(percent: float) -> void:
# 	if not _fill_clip:
# 		return
# 	percent = clampf(percent, 0.0, 1.0)
# 	_fill_clip.anchor_right = percent
# 	var fill_inset: float = ThemeProvider.theme.button_border_width - 0.5
# 	_fill_clip.offset_right = -fill_inset if percent > 0.99 else 0.0


# func set_main_disabled(is_disabled: bool) -> void:
# 	main_button.disabled = is_disabled


# func apply_fill_colors(is_disabled: bool, at_max: bool = false) -> void:
# 	if not _fill_rect:
# 		return
# 	var t: VisualTheme = ThemeProvider.theme
# 	var text_color: Color
# 	if is_disabled or at_max:
# 		text_color = t._resolve(VisualTheme.Palette.BG_5)
# 		_fill_rect.color = _disabled_color
# 	else:
# 		text_color = t.normal_text_color
# 		_fill_rect.color = _fill_color
# 	_base_label.add_theme_color_override("font_color", text_color)
# 	_fill_label.add_theme_color_override("font_color", text_color)

func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	progress_bar.setup(t.button_enabled_color, t.button_disabled_color)
	progress_bar.main_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.apply_fill_colors(false)

	LevelManager.level_changed.connect(_on_level_changed)
	CurrencyManager.currency_changed.connect(_on_currency_changed)

	_update_display()


func _on_level_changed(_new_level: int) -> void:
	_update_display()


func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _cap: int) -> void:
	_update_display()

func _update_display() -> void:
	var total := LevelManager.get_total_levels()
	level_label.text = "LVL %d/%d" % [LevelManager.current_level + 1, total + 1]

	var threshold: int = LevelManager.get_next_threshold()
	if threshold <= 0:
		progress_bar.set_fill(1.0)
		progress_bar.update_text("MAX")
	else:
		var currency := LevelManager.get_active_currency()
		var balance := CurrencyManager.get_balance(currency)
		max_value = threshold
		value = mini(balance, threshold)
		progress_bar.set_fill(float(value) / float(threshold))
		progress_bar.update_text("%d/%d %s" % [balance, threshold, Enums.currency_name(currency)])
