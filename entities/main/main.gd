extends Node3D

const OptionsDialogScript := preload("res://entities/options_dialog/options_dialog.gd")

@onready var board_manager: BoardManager = $BoardManager
@onready var camera: Camera3D = $Camera3D
@onready var coin_values = $CanvasLayer/CoinValues
@onready var challenge_hud = $CanvasLayer/ChallengeHUD
@onready var game_timer: Label = $CanvasLayer/GameTimer
@onready var options_icon: TextureButton = $CanvasLayer/OptionsIcon

var _options_dialog: CanvasLayer

func _ready() -> void:
	_setup_environment()
	board_manager.setup(camera)
	coin_values.setup(board_manager)
	_setup_gear_button()
	_setup_options_dialog()

	if ChallengeManager.is_active_challenge:
		_setup_challenge()
	else:
		_setup_normal()


func _setup_environment() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = t.background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = t.ambient_light_color
	env.ambient_light_energy = t.ambient_light_energy
	var env_node := WorldEnvironment.new()
	env_node.environment = env
	add_child(env_node)

	if not t.unshaded:
		var light := DirectionalLight3D.new()
		light.light_color = t.directional_light_color
		light.light_energy = t.directional_light_energy
		light.rotation_degrees = t.directional_light_angle
		add_child(light)


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


func _setup_gear_button() -> void:
	options_icon.pressed.connect(_on_gear_pressed)


func _setup_options_dialog() -> void:
	_options_dialog = CanvasLayer.new()
	_options_dialog.layer = 10
	_options_dialog.set_script(OptionsDialogScript)
	add_child(_options_dialog)


func _on_gear_pressed() -> void:
	_options_dialog.show_dialog()


func _process(_delta: float) -> void:
	if not is_instance_valid(game_timer):
		return
	var seconds := Time.get_ticks_msec() / 1000.0
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	game_timer.text = "%d:%02d" % [mins, secs]
