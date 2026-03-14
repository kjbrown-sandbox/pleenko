extends HBoxContainer

var level_label: Label
var progress_bar: ProgressBar
var progress_label: Label


func _ready() -> void:
	# Anchor to bottom of screen, full width
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_top = -30
	offset_bottom = 0
	offset_left = 10
	offset_right = -10

	# Level label: "LVL 0"
	level_label = Label.new()
	level_label.text = "LVL 0"
	level_label.custom_minimum_size.x = 60
	add_child(level_label)

	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.show_percentage = false
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.value = 0.0
	progress_bar.custom_minimum_size.y = 20
	add_child(progress_bar)

	# Progress text: "0/10"
	progress_label = Label.new()
	progress_label.custom_minimum_size.x = 80
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(progress_label)

	LevelManager.level_changed.connect(_on_level_changed)
	CurrencyManager.currency_changed.connect(_on_currency_changed)

	_update_display()


func _on_level_changed(_new_level: int) -> void:
	_update_display()


func _on_currency_changed(type: Enums.CurrencyType, _new_balance: int, _cap: int) -> void:
	if type == Enums.CurrencyType.GOLD_COIN:
		_update_display()


func _update_display() -> void:
	level_label.text = "LVL %d" % LevelManager.current_level

	var threshold := LevelManager.get_next_threshold()
	if threshold <= 0:
		progress_bar.value = 1.0
		progress_label.text = "MAX"
	else:
		var gold := CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN)
		progress_bar.max_value = threshold
		progress_bar.value = mini(gold, threshold)
		progress_label.text = "%d/%d" % [gold, threshold]
