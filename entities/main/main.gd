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
@onready var prestige_animator: PrestigeAnimator = $PrestigeAnimator

var _options_dialog: CanvasLayer

func _ready() -> void:
	# Safety net: ensure time_scale is normal when main scene loads
	# (in case prestige animation was interrupted)
	PrestigeManager.reset_time_scale()

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
	_setup_prestige_animator()

	_setup_vignette()
	_setup_nav_icons()
	ModeManager.mode_changed.connect(_on_mode_changed)
	PrestigeManager.prestige_claimed.connect(_on_prestige_claimed)
	PrestigeManager.prestige_phase_changed.connect(_on_prestige_phase_changed)
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
	elif event is InputEventKey and event.pressed and event.keycode == KEY_P:
		_debug_test_prestige()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_O:
		_debug_setup_prestigeable_state()


func _debug_test_prestige() -> void:
	var board := board_manager.get_active_board()
	# Find an advanced bucket (one whose currency would trigger prestige)
	for bucket in board.buckets_container.get_children():
		if board._will_trigger_prestige(bucket.currency_type):
			# Spawn a coin right above this bucket so it lands there on the next bounce
			var coin: Coin = board.CoinScene.instantiate()
			coin.coin_type = bucket.currency_type
			coin.board = board
			# Position one row above the bucket, aligned with it
			var bucket_local_x: float = bucket.position.x + board.buckets_container.position.x
			coin.position = Vector3(bucket_local_x, board.buckets_container.position.y + board.vertical_spacing + 0.3, 0)
			board.add_child(coin)
			coin.landed.connect(board.on_coin_landed)
			coin.final_bounce_started.connect(board._on_final_bounce_started)
			coin.start(Vector3(bucket_local_x, 0.2, 0))
			print("[DEBUG] Spawned prestige test coin above bucket at x=", bucket_local_x)
			return
	print("[DEBUG] No prestige-triggering bucket found on active board")


func _debug_setup_prestigeable_state() -> void:
	var board := board_manager.get_active_board()
	# Ensure enough rows for advanced buckets to appear (need distance_for_advanced_buckets + 1 buckets from center)
	var min_rows: int = board.distance_for_advanced_buckets * 2 + 2
	if board.num_rows < min_rows:
		board.num_rows = min_rows
	board.should_show_advanced_buckets = true
	board.build_board()
	board_manager._tween_camera_to_active_board()
	print("[DEBUG] Board set to %d rows with advanced buckets visible. Press P to test prestige." % board.num_rows)


func _setup_vignette() -> void:
	var vignette := CanvasLayer.new()
	vignette.set_script(preload("res://entities/vignette/vignette.gd"))
	add_child(vignette)


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


func _setup_prestige_animator() -> void:
	prestige_animator.setup(camera)
	# Connect all existing boards
	for board in board_manager.get_boards():
		prestige_animator.connect_board(board)


func _on_prestige_phase_changed(phase: PrestigeManager.PrestigePhase) -> void:
	if phase == PrestigeManager.PrestigePhase.SLOW_MO:
		# Hide all HUD elements when the coin touches the bucket
		coin_values.visible = false
		level_section.visible = false
		game_timer.visible = false
		options_icon.visible = false
		challenges_down_icon.visible = false
		board_manager.set_active_board_ui_visible(false)


func _on_prestige_claimed(_board_type: Enums.BoardType) -> void:
	challenges_down_icon.visible = true
	challenge_grouping_manager.update_group_visibility()


func _on_board_switched(_board: PlinkoBoard) -> void:
	_update_nav_arrows()


func _on_board_unlocked(_board_type: Enums.BoardType) -> void:
	# Connect the newly unlocked board to the prestige animator
	for board in board_manager.get_boards():
		if board.board_type == _board_type:
			prestige_animator.connect_board(board)
			break
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

	challenges_down_icon.setup(PI / 2.0)
	challenges_up_icon.setup(-PI / 2.0)
	board_left_icon.setup(PI)
	board_right_icon.setup(0.0)

	var m := t.hud_margin
	challenges_down_icon.offset_top -= m
	challenges_down_icon.offset_bottom -= m
	challenges_up_icon.offset_top += m
	challenges_up_icon.offset_bottom += m
	board_left_icon.offset_left += m
	board_left_icon.offset_right += m
	board_right_icon.offset_left -= m
	board_right_icon.offset_right -= m

	challenges_down_icon.pressed.connect(_on_challenges_down_pressed)
	challenges_up_icon.pressed.connect(_on_challenges_up_pressed)
	board_left_icon.pressed.connect(_on_left_arrow_pressed)
	board_right_icon.pressed.connect(_on_right_arrow_pressed)


func _on_challenges_down_pressed() -> void:
	ModeManager.switch_to_challenges()

func _on_challenges_up_pressed() -> void:
	ModeManager.switch_to_main()
