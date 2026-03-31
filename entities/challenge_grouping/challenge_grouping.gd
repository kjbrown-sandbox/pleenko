class_name ChallengeGrouping
extends Node3D

@export var board_type: Enums.BoardType = Enums.BoardType.GOLD

var ChallengeConnectorScene: PackedScene = preload("res://entities/challenges_menu/challenge_connector.tscn")

var _challenge_buttons: Array[ChallengeButton] = []


func setup() -> void:
	_collect_buttons()
	_create_connectors()


func _collect_buttons() -> void:
	for child in get_children():
		if child is ChallengeButton:
			_challenge_buttons.append(child)


func _create_connectors() -> void:
	for btn in _challenge_buttons:
		for challenge_id in btn.next_challenges:
			var end: ChallengeButton = null
			for c in _challenge_buttons:
				if c.challenge_ui_name == challenge_id:
					end = c
					break
			if not end:
				continue
			var connector = ChallengeConnectorScene.instantiate()
			connector.setup(btn, end)
			add_child(connector)


func initialize_progress() -> void:
	ChallengeProgressManager.initialize(_challenge_buttons)


func connect_signals(on_hovered: Callable, on_pressed: Callable) -> void:
	for btn in _challenge_buttons:
		btn.hovered.connect(on_hovered)
		btn.pressed.connect(on_pressed.bind(btn))


func get_challenge_buttons() -> Array[ChallengeButton]:
	return _challenge_buttons


func get_earliest_incomplete() -> ChallengeButton:
	return ChallengeProgressManager.get_earliest_incomplete(_challenge_buttons)
