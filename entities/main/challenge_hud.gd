extends VBoxContainer

var _time_remaining: float = 0.0
var _is_running: bool = false

@onready var _timer_label: Label = $TimerLabel
@onready var _objective_label: Label = $ObjectiveLabel
@onready var _result_label: Label = $ResultLabel
var _progress_label: Label


func start(challenge: ChallengeData) -> void:
	_is_running = true
	_result_label.visible = false
	_objective_label.text = ChallengeManager.get_objective_text()
	_time_remaining = challenge.time_limit_seconds

	_apply_theme()

	# Survive challenges have their own two-phase countdown rendered into the
	# progress label, so the regular timer label is hidden to avoid duplication.
	_timer_label.visible = not _challenge_has_survive(challenge)

	# Create progress label between objective and result
	if not _progress_label:
		_progress_label = Label.new()
		_progress_label.name = "ProgressLabel"
		_progress_label.add_theme_font_size_override("font_size", 24)
		_progress_label.add_theme_color_override("font_color", ThemeProvider.theme.body_text_color)
		_progress_label.visible = false
		add_child(_progress_label)
		move_child(_progress_label, _objective_label.get_index() + 1)

	_update_timer_display()
	_update_progress()


func _challenge_has_survive(challenge: ChallengeData) -> bool:
	for objective in challenge.objectives:
		if objective is Survive:
			return true
	return false


func _process(_delta: float) -> void:
	if not _is_running:
		return
	_time_remaining = ChallengeManager.get_time_remaining()
	_update_timer_display()
	_update_progress()


func _update_timer_display() -> void:
	var minutes := int(_time_remaining) / 60
	var seconds := int(_time_remaining) % 60
	_timer_label.text = "%d:%02d" % [minutes, seconds]


func _update_progress() -> void:
	var progress := ChallengeManager.get_objective_progress()
	_progress_label.text = progress
	_progress_label.visible = progress != ""


func refresh_progress() -> void:
	_update_progress()


func show_result(text: String) -> void:
	_is_running = false
	_result_label.text = text
	_result_label.visible = true


func _apply_theme() -> void:
	var t: VisualTheme = ThemeProvider.theme
	_timer_label.add_theme_color_override("font_color", t.normal_text_color)
	_objective_label.add_theme_color_override("font_color", t.body_text_color)
	_result_label.add_theme_color_override("font_color", t.normal_text_color)
