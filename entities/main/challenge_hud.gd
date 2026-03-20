extends VBoxContainer

var _time_remaining: float = 0.0
var _is_running: bool = false

@onready var _timer_label: Label = $TimerLabel
@onready var _objective_label: Label = $ObjectiveLabel
@onready var _result_label: Label = $ResultLabel


func start(challenge: ChallengeData) -> void:
	_is_running = true
	_result_label.visible = false
	_objective_label.text = ChallengeManager.get_objective_text()
	_time_remaining = challenge.time_limit_seconds
	_update_timer_display()


func _process(_delta: float) -> void:
	if not _is_running:
		return
	_time_remaining = ChallengeManager.get_time_remaining()
	_update_timer_display()


func _update_timer_display() -> void:
	var minutes := int(_time_remaining) / 60
	var seconds := int(_time_remaining) % 60
	_timer_label.text = "%d:%02d" % [minutes, seconds]


func show_result(text: String) -> void:
	_is_running = false
	_result_label.text = text
	_result_label.visible = true
