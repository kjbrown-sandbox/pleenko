extends Node3D

const OptionsDialogScript := preload("res://entities/options_dialog/options_dialog.gd")

@onready var board_manager: BoardManager = $BoardManager
@onready var challenge_grouping_manager: ChallengeGroupingManager = $ChallengeGroupingManager
@onready var camera: Camera3D = $Camera3D
@onready var coin_values = $CanvasLayer/CoinValues
@onready var challenge_hud = $CanvasLayer/ChallengeHUD
@onready var game_timer: Label = $CanvasLayer/GameTimer
@onready var options_icon: TextureButton = $CanvasLayer/OptionsIcon
@onready var level_section = $CanvasLayer/LevelSection
@onready var challenges_down_icon: TextureButton = $CanvasLayer/ChallengesDownIcon
@onready var challenges_up_icon: TextureButton = $CanvasLayer/ChallengesUpIcon
@onready var board_left_icon: TextureButton = $CanvasLayer/BoardLeftIcon
@onready var board_right_icon: TextureButton = $CanvasLayer/BoardRightIcon
@onready var challenge_info_panel: ChallengeInfoPanel = $ChallengeInfoPanel

var _options_dialog: CanvasLayer
var _down_tooltip: Label
var _up_tooltip: Label
var _left_tooltip: Label
var _right_tooltip: Label

func _ready() -> void:
	_setup_environment()
	ModeManager.current_mode = ModeManager.Mode.MAIN

	# Reset state BEFORE board setup so challenges start clean
	if ChallengeManager.is_active_challenge:
		SaveManager.reset_state()
		if SaveManager.has_save():
			SaveManager.load_prestige_only()

	board_manager.setup(camera)
	challenge_grouping_manager.setup(camera, challenge_info_panel)
	coin_values.setup(board_manager)
	_setup_gear_button()
	_setup_options_dialog()

	_setup_nav_icons()
	ModeManager.mode_changed.connect(_on_mode_changed)
	PrestigeManager.prestige_claimed.connect(_on_prestige_claimed)
	board_manager.board_switched.connect(_on_board_switched)
	board_manager.board_unlocked.connect(_on_board_unlocked)
	challenge_grouping_manager.group_switched.connect(_on_group_switched)

	if ChallengeManager.is_active_challenge:
		_setup_challenge()
	else:
		_setup_normal()

	# Show down-arrow only after save is loaded (prestige state is available)
	challenges_down_icon.visible = ModeManager.are_challenges_unlocked()
	_update_nav_arrows()


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
		challenge_grouping_manager.refresh_challenge_progress()

	challenge_grouping_manager.update_group_visibility()


func _setup_challenge() -> void:
	challenge_hud.visible = true
	ChallengeManager.setup(board_manager)
	ChallengeManager.challenge_completed.connect(_on_challenge_completed)
	ChallengeManager.challenge_failed.connect(_on_challenge_failed)
	challenge_hud.start(ChallengeManager.get_challenge())


func _on_challenge_completed() -> void:
	var challenge := ChallengeManager.get_challenge()
	# Find the button to get next_challenges
	var next_ids: Array[String] = []
	for btn in challenge_grouping_manager.get_all_challenge_buttons():
		if btn.challenge == challenge:
			next_ids = btn.next_challenges
			break
	ChallengeProgressManager.complete_challenge(challenge.id, next_ids, challenge.rewards)
	SaveManager.save_challenge_progress()
	ChallengeManager.clear_challenge()
	challenge_hud.show_result("Challenge Complete!")
	await get_tree().create_timer(2.0).timeout
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
		challenge_info_panel.visible = true
		challenge_grouping_manager.enter_challenges_mode()
		_update_nav_arrows()
	else:
		coin_values.visible = true
		level_section.visible = true
		game_timer.visible = true
		challenges_down_icon.visible = ModeManager.are_challenges_unlocked()
		board_manager.set_active_board_ui_visible(true)
		challenges_up_icon.visible = false
		challenge_info_panel.visible = false
		_update_nav_arrows()
		_go_back_to_board()


func _on_prestige_claimed(_board_type: Enums.BoardType) -> void:
	challenges_down_icon.visible = true
	challenge_grouping_manager.update_group_visibility()


func _on_board_switched(_board: PlinkoBoard) -> void:
	_update_nav_arrows()


func _on_board_unlocked(_board_type: Enums.BoardType) -> void:
	_update_nav_arrows()


func _on_group_switched(_group: ChallengeGrouping) -> void:
	_update_nav_arrows()


func _update_nav_arrows() -> void:
	if ModeManager.is_main():
		board_left_icon.visible = board_manager._active_index > 0
		board_right_icon.visible = board_manager._active_index + 1 < board_manager._boards.size()
	elif ModeManager.is_challenges():
		board_left_icon.visible = challenge_grouping_manager.has_prev_group()
		board_right_icon.visible = challenge_grouping_manager.has_next_group()


func _on_left_arrow_pressed() -> void:
	if ModeManager.is_main():
		board_manager.switch_board(board_manager._active_index - 1)
	elif ModeManager.is_challenges():
		challenge_grouping_manager.switch_to_prev_group()


func _on_right_arrow_pressed() -> void:
	if ModeManager.is_main():
		board_manager.switch_board(board_manager._active_index + 1)
	elif ModeManager.is_challenges():
		challenge_grouping_manager.switch_to_next_group()


func _setup_nav_icons() -> void:
	var t: VisualTheme = ThemeProvider.theme
	_down_tooltip = _create_tooltip("Hotkey: Down arrow")
	_up_tooltip = _create_tooltip("Hotkey: Up arrow")
	_left_tooltip = _create_tooltip("Hotkey: Left arrow")
	_right_tooltip = _create_tooltip("Hotkey: Right arrow")

	challenges_down_icon.setup(PI / 2.0)
	challenges_up_icon.setup(-PI / 2.0)
	board_left_icon.setup(PI)
	board_right_icon.setup(0.0)

	challenges_down_icon.pressed.connect(func(): ModeManager.switch_to_challenges())
	challenges_down_icon.mouse_entered.connect(func(): _show_tooltip(_down_tooltip, challenges_down_icon))
	challenges_down_icon.mouse_exited.connect(func(): _down_tooltip.visible = false)

	challenges_up_icon.pressed.connect(func(): ModeManager.switch_to_main())
	challenges_up_icon.mouse_entered.connect(func(): _show_tooltip(_up_tooltip, challenges_up_icon))
	challenges_up_icon.mouse_exited.connect(func(): _up_tooltip.visible = false)

	board_left_icon.pressed.connect(_on_left_arrow_pressed)
	board_left_icon.mouse_entered.connect(func(): _show_tooltip(_left_tooltip, board_left_icon))
	board_left_icon.mouse_exited.connect(func(): _left_tooltip.visible = false)

	board_right_icon.pressed.connect(_on_right_arrow_pressed)
	board_right_icon.mouse_entered.connect(func(): _show_tooltip(_right_tooltip, board_right_icon))
	board_right_icon.mouse_exited.connect(func(): _right_tooltip.visible = false)


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
