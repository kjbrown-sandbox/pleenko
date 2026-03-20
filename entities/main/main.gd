extends Node3D

@onready var board_manager: BoardManager = $BoardManager
@onready var camera: Camera3D = $Camera3D
@onready var coin_values = $CanvasLayer/CoinValues
@onready var challenge_hud = $CanvasLayer/ChallengeHUD

func _ready() -> void:
	board_manager.setup(camera)
	coin_values.setup(board_manager)

	if ChallengeManager.is_active_challenge:
		_setup_challenge()
	else:
		_setup_normal()


func _setup_normal() -> void:
	challenge_hud.visible = false
	SaveManager.setup(board_manager, true)

	if SaveManager.has_save():
		SaveManager.load_game()
		coin_values.refresh_visible_currencies()


func _setup_challenge() -> void:
	challenge_hud.visible = true
	SaveManager.reset_state()

	# Load prestige data from save so it carries into challenges
	if SaveManager.has_save():
		SaveManager.load_prestige_only()

	ChallengeManager.setup(board_manager)
	ChallengeManager.challenge_completed.connect(_on_challenge_completed)
	ChallengeManager.challenge_failed.connect(_on_challenge_failed)
	challenge_hud.start(ChallengeManager.get_challenge())


func _on_challenge_completed() -> void:
	challenge_hud.show_result("Challenge Complete!")
	# Return to main after a brief delay
	await get_tree().create_timer(2.0).timeout
	ChallengeManager.clear_challenge()
	SaveManager.reset_state()
	get_tree().reload_current_scene()


func _on_challenge_failed(reason: String) -> void:
	challenge_hud.show_result("Failed: %s" % reason)
	await get_tree().create_timer(2.0).timeout
	ChallengeManager.clear_challenge()
	SaveManager.reset_state()
	get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	if ChallengeManager.is_active_challenge:
		return
	if event.is_action_pressed("quicksave"):
		SaveManager.save_game()
	elif event.is_action_pressed("reset_game"):
		SaveManager.reset_game()
