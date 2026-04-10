class_name ChallengeGroupingManager
extends Node3D

signal group_switched(group: ChallengeGrouping)

const GroupScenes: Array[PackedScene] = [
	preload("res://entities/challenge_grouping/challenge_group_gold.tscn"),
	preload("res://entities/challenge_grouping/challenge_group_orange.tscn"),
	preload("res://entities/challenge_grouping/challenge_group_red.tscn"),
	preload("res://entities/challenge_grouping/challenge_group_violet.tscn"),
	preload("res://entities/challenge_grouping/challenge_group_blue.tscn"),
	preload("res://entities/challenge_grouping/challenge_group_green.tscn"),
]

@export var group_spacing: float = 15.0
@export var challenge_y_offset: float = -20.0

var camera_tween_duration: float
var _groups: Array[ChallengeGrouping] = []
var _active_index: int = 0
var _camera: Camera3D
var _challenge_info_panel: ChallengeInfoPanel


func setup(camera: Camera3D, info_panel: ChallengeInfoPanel) -> void:
	_camera = camera
	_challenge_info_panel = info_panel
	camera_tween_duration = ThemeProvider.theme.camera_tween_duration

	for i in GroupScenes.size():
		var group: ChallengeGrouping = GroupScenes[i].instantiate()
		group.position = Vector3(i * group_spacing, challenge_y_offset, 0)
		add_child(group)
		group.setup()
		group.initialize_progress()
		group.connect_signals(_on_challenge_hovered, _on_challenge_pressed)
		group.visible = _is_group_unlocked(i)
		_groups.append(group)


func _input(event: InputEvent) -> void:
	if not ModeManager.is_challenges():
		return
	if event.is_action_pressed("board_left"):
		switch_to_prev_group()
	elif event.is_action_pressed("board_right"):
		switch_to_next_group()


func get_active_group() -> ChallengeGrouping:
	if _groups.is_empty():
		return null
	return _groups[_active_index]


func get_all_challenge_buttons() -> Array[ChallengeButton]:
	var all: Array[ChallengeButton] = []
	for group in _groups:
		all.append_array(group.get_challenge_buttons())
	return all


func switch_group(index: int) -> void:
	if index < 0 or index >= _groups.size():
		return
	if not _is_group_unlocked(index):
		return
	_active_index = index
	go_to_default_challenge()
	group_switched.emit(_groups[_active_index])


func switch_to_next_group() -> void:
	for i in range(_active_index + 1, _groups.size()):
		if _is_group_unlocked(i):
			switch_group(i)
			return


func switch_to_prev_group() -> void:
	for i in range(_active_index - 1, -1, -1):
		if _is_group_unlocked(i):
			switch_group(i)
			return


func has_next_group() -> bool:
	for i in range(_active_index + 1, _groups.size()):
		if _is_group_unlocked(i):
			return true
	return false


func has_prev_group() -> bool:
	for i in range(_active_index - 1, -1, -1):
		if _is_group_unlocked(i):
			return true
	return false


@export var challenge_camera_size: float = 9.0

func go_to_default_challenge() -> void:
	var group := get_active_group()
	if not group:
		return
	_tween_camera_to_group(group)
	var btn := group.get_earliest_incomplete()
	if btn and _challenge_info_panel and btn.challenge:
		_challenge_info_panel.show_challenge(btn.challenge)


func enter_challenges_mode() -> void:
	# Find first unlocked group
	for i in _groups.size():
		if _is_group_unlocked(i):
			_active_index = i
			break
	go_to_default_challenge()


func _tween_camera_to_group(group: ChallengeGrouping) -> void:
	var target := Vector3(group.global_position.x, group.global_position.y, _camera.position.z)
	var tween := create_tween()
	tween.tween_property(_camera, "position", target, camera_tween_duration) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(_camera, "size", challenge_camera_size, camera_tween_duration) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)


func _is_group_unlocked(index: int) -> bool:
	if index < 0 or index >= _groups.size():
		return false
	var group := _groups[index]
	if group.board_type == Enums.BoardType.GOLD:
		return ModeManager.are_challenges_unlocked()
	return PrestigeManager.is_board_unlocked_permanently(group.board_type)


func _on_challenge_hovered(btn: ChallengeButton) -> void:
	if btn.challenge and _challenge_info_panel:
		_challenge_info_panel.show_challenge(btn.challenge)


func _on_challenge_pressed(btn: ChallengeButton) -> void:
	if not btn.challenge:
		return
	var state := ChallengeProgressManager.get_state(btn.challenge_ui_name)
	if state == ChallengeProgressManager.ChallengeState.LOCKED:
		return
	ChallengeManager.set_challenge(btn.challenge)
	get_tree().reload_current_scene.call_deferred()


func refresh_challenge_progress() -> void:
	for group in _groups:
		group.initialize_progress()


func update_group_visibility() -> void:
	for i in _groups.size():
		_groups[i].visible = _is_group_unlocked(i)
