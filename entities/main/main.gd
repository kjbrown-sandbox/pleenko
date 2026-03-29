extends Node3D

const OptionsDialogScript := preload("res://entities/options_dialog/options_dialog.gd")

@onready var board_manager: BoardManager = $BoardManager
@onready var camera: Camera3D = $Camera3D
@onready var coin_values = $CanvasLayer/CoinValues
@onready var challenge_hud = $CanvasLayer/ChallengeHUD
@onready var game_timer: Label = $CanvasLayer/GameTimer
@onready var options_icon: TextureButton = $CanvasLayer/OptionsIcon
@onready var level_section = $CanvasLayer/LevelSection
@onready var challenges_down_icon: TextureButton = $CanvasLayer/ChallengesDownIcon
@onready var challenges_up_icon: TextureButton = $CanvasLayer/ChallengesUpIcon

var ChallengeConnector: PackedScene = preload("res://entities/challenges_menu/challenge_connector.tscn")

var _options_dialog: CanvasLayer
var _challenge_buttons: Array[ChallengeButton] = []
var _down_tooltip: Label
var _up_tooltip: Label

func _ready() -> void:
	_setup_environment()
	board_manager.setup(camera)
	coin_values.setup(board_manager)
	_setup_gear_button()
	_setup_options_dialog()
	_collect_challenge_buttons()

	for challenge in _challenge_buttons:
		for challenge_id in challenge.next_challenges:
			var end: ChallengeButton = null
			for c in _challenge_buttons:
				if c.challenge_ui_name == challenge_id:
					end = c
					break
			if not end:
				continue
			var connector = ChallengeConnector.instantiate()
			connector.setup(challenge, end)
			add_child(connector)



	_setup_nav_icons()
	ModeManager.mode_changed.connect(_on_mode_changed)
	PrestigeManager.prestige_claimed.connect(_on_prestige_claimed)

	if ChallengeManager.is_active_challenge:
		_setup_challenge()
	else:
		_setup_normal()

	# Show down-arrow only after save is loaded (prestige state is available)
	challenges_down_icon.visible = ModeManager.are_challenges_unlocked()


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
	if event.is_action_pressed("challenges_down") and ModeManager.is_main():
		ModeManager.switch_to_challenges()
	elif event.is_action_pressed("challenges_up") and ModeManager.is_challenges():
		ModeManager.switch_to_main()
	elif event.is_action_pressed("quicksave"):
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


func _collect_challenge_buttons() -> void:
	for child in get_children():
		if child is ChallengeButton:
			_challenge_buttons.append(child)


func _go_to_random_challenge() -> void:
	if _challenge_buttons.is_empty():
		return
	var button: ChallengeButton = _challenge_buttons.pick_random()
	var target := Vector3(button.position.x, button.position.y, camera.position.z)
	var tween := create_tween()
	tween.tween_property(camera, "position", target, board_manager.camera_tween_duration) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)


func _go_back_to_board() -> void:
	board_manager._tween_camera_to_active_board()


func _on_mode_changed(new_mode: ModeManager.Mode) -> void:
	if new_mode == ModeManager.Mode.CHALLENGES:
		coin_values.visible = false
		level_section.visible = false
		game_timer.visible = false
		challenges_down_icon.visible = false
		board_manager.set_active_board_ui_visible(false)
		challenges_up_icon.visible = true
		_go_to_random_challenge()
	else:
		coin_values.visible = true
		level_section.visible = true
		game_timer.visible = true
		challenges_down_icon.visible = ModeManager.are_challenges_unlocked()
		board_manager.set_active_board_ui_visible(true)
		challenges_up_icon.visible = false
		_go_back_to_board()


func _on_prestige_claimed(_board_type: Enums.BoardType) -> void:
	challenges_down_icon.visible = true


func _setup_nav_icons() -> void:
	challenges_down_icon.pressed.connect(func(): ModeManager.switch_to_challenges())
	challenges_up_icon.pressed.connect(func(): ModeManager.switch_to_main())

	var t: VisualTheme = ThemeProvider.theme
	_down_tooltip = _create_tooltip("Hotkey: Down arrow")
	_up_tooltip = _create_tooltip("Hotkey: Up arrow")

	# Position tooltips to the right of each icon
	challenges_down_icon.mouse_entered.connect(func(): _show_tooltip(_down_tooltip, challenges_down_icon))
	challenges_down_icon.mouse_exited.connect(func(): _down_tooltip.visible = false)
	challenges_up_icon.mouse_entered.connect(func(): _show_tooltip(_up_tooltip, challenges_up_icon))
	challenges_up_icon.mouse_exited.connect(func(): _up_tooltip.visible = false)


func _create_tooltip(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.visible = false
	var t: VisualTheme = ThemeProvider.theme
	label.add_theme_font_size_override("font_size", int(t.button_font_size))
	label.add_theme_color_override("font_color", t.resolve(VisualTheme.Palette.BG_5))
	var font: Font = t.button_font if t.button_font else t.label_font
	if font:
		label.add_theme_font_override("font", font)
	$CanvasLayer.add_child(label)
	return label


func _show_tooltip(tooltip: Label, icon: TextureButton) -> void:
	tooltip.visible = true
	tooltip.size = Vector2.ZERO
	_position_tooltip.call_deferred(tooltip, icon)


func _position_tooltip(tooltip: Label, icon: TextureButton) -> void:
	var icon_pos: Vector2 = icon.global_position
	var icon_size: Vector2 = icon.size
	tooltip.global_position = Vector2(
		icon_pos.x + icon_size.x + 8.0,
		icon_pos.y + (icon_size.y - tooltip.size.y) / 2.0
	)
