extends Control

@onready var progress_bar: HBoxContainer = $HBoxContainer/ProgressBar
@onready var level_label: Label = $HBoxContainer/LevelLabel

var max_value: int = 0
var value: int = 0

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
		progress_bar.update_text("%d/%d %s" % [balance, threshold, FormatUtils.currency_name(currency)])
