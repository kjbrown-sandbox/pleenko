extends Node3D

const OptionsDialogScript := preload("res://entities/options_dialog/options_dialog.gd")
const ComingSoonOverlayScript := preload("res://entities/coming_soon_overlay/coming_soon_overlay.gd")
const ChallengeCompleteDialogScene := preload("res://entities/challenge_complete_dialog/challenge_complete_dialog.tscn")

## Demo lockdown toggle. When true, the red board and orange/red challenge
## groups are blocked behind a "More coming soon!" overlay. Toggle from the
## Inspector on the Main node to switch between demo and full play.
@export var demo_mode: bool = false

@onready var board_manager: BoardManager = $BoardManager
@onready var challenge_grouping_manager: ChallengeGroupingManager = $ChallengeGroupingManager
@onready var camera: Camera3D = $Camera3D
@onready var coin_values = $CanvasLayer/CoinValues
@onready var challenge_hud = $CanvasLayer/ChallengeHUD
@onready var game_timer: Label = $CanvasLayer/GameTimer
@onready var options_icon: TextureButton = $CanvasLayer/OptionsIcon
@onready var level_section = $CanvasLayer/LevelSection
@onready var challenges_down_icon: TextureButton = $NavIconsLayer/ChallengesDownIcon
@onready var challenges_up_icon: TextureButton = $NavIconsLayer/ChallengesUpIcon
@onready var board_left_icon: TextureButton = $NavIconsLayer/BoardLeftIcon
@onready var board_right_icon: TextureButton = $NavIconsLayer/BoardRightIcon
@onready var challenge_info_panel: ChallengeInfoPanel = $ChallengeInfoPanel
@onready var prestige_animator: PrestigeAnimator = $PrestigeAnimator

var _options_dialog: CanvasLayer
var _coming_soon_overlay: CanvasLayer
var _challenge_complete_dialog: CanvasLayer

# Nav arrow blink state
var _boards_with_unseen_upgrades: Dictionary = {}  # BoardType -> true
var _arrow_blink_tweens: Dictionary = {}  # Control -> Tween
# Suppresses unseen-board marking while replaying board_unlocked signals during
# save load — otherwise every arrow would blink on every startup.
var _loading_from_save: bool = false

func _ready() -> void:
	# Safety net: ensure time_scale is normal when main scene loads
	# (in case prestige animation was interrupted)
	PrestigeManager.reset_time_scale()

	ModeManager.current_mode = ModeManager.Mode.MAIN

	# Reset state BEFORE board setup so challenges start clean
	if ChallengeManager.is_active_challenge:
		SaveManager.reset_state()
		if SaveManager.has_save():
			SaveManager.load_prestige_only()

	board_manager.setup(camera)
	level_section.setup(board_manager, camera)
	challenge_grouping_manager.setup(camera, challenge_info_panel)
	coin_values.setup(board_manager)
	_setup_gear_button()
	_setup_options_dialog()
	_setup_coming_soon_overlay()
	_setup_challenge_complete_dialog()
	_setup_prestige_animator()

	_setup_vignette()
	_setup_nav_icons()
	ModeManager.mode_changed.connect(_on_mode_changed)
	PrestigeManager.prestige_claimed.connect(_on_prestige_claimed)
	PrestigeManager.prestige_phase_changed.connect(_on_prestige_phase_changed)
	board_manager.board_switched.connect(_on_board_switched)
	board_manager.board_unlocked.connect(_on_board_unlocked)
	challenge_grouping_manager.group_switched.connect(_on_group_switched)
	UpgradeManager.upgrade_unlocked.connect(_on_upgrade_unlocked_for_nav)

	if ChallengeManager.is_active_challenge:
		_setup_challenge()
	else:
		_setup_normal()

	# Show down-arrow only after save is loaded (prestige state is available)
	challenges_down_icon.visible = ModeManager.are_challenges_unlocked()
	_update_nav_arrows()
	_update_lockdown_overlay()


func _setup_normal() -> void:
	challenge_hud.visible = false
	SaveManager.setup(board_manager, true)

	if SaveManager.has_save():
		_loading_from_save = true
		SaveManager.load_game()
		_loading_from_save = false
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

	# Capture stats from the tracker BEFORE clearing it
	var stats := {
		"time_taken": ChallengeManager.get_time_taken(),
		"coins_dropped": ChallengeManager.get_total_drops(),
	}

	ChallengeProgressManager.complete_challenge(challenge.id, next_ids, challenge.rewards)
	SaveManager.save_challenge_progress()

	# Build reward summary lines from the rewards list
	var reward_lines: Array[String] = []
	for reward in challenge.rewards:
		reward_lines.append(_format_reward(reward))

	# Refresh the HUD progress label one more time so the final n/n shows before
	# clear_challenge() nulls the tracker.
	challenge_hud.refresh_progress()
	ChallengeManager.clear_challenge()
	challenge_hud.show_result("Challenge Complete!")
	await get_tree().create_timer(2.0).timeout

	_challenge_complete_dialog.show_with_results(stats, reward_lines)
	await _challenge_complete_dialog.closed

	SaveManager.reset_state()
	ThemeProvider.set_theme(ThemeProvider.Kind.NORMAL)
	get_tree().reload_current_scene()


func _format_reward(reward: ChallengeRewardData) -> String:
	match reward.type:
		ChallengeRewardData.RewardType.UNLOCK:
			return "Unlocked: %s" % ChallengeRewardData.UnlockType.keys()[reward.unlock_type].capitalize().replace("_", " ")
		ChallengeRewardData.RewardType.STARTING_MODIFIER:
			return _format_starting_modifier(reward)
		ChallengeRewardData.RewardType.PERMANENT_UPGRADE:
			var board_name: String = Enums.BoardType.keys()[reward.board_type].capitalize()
			var upgrade_name: String = Enums.UpgradeType.keys()[reward.upgrade_type].capitalize().replace("_", " ")
			return "+%d %s level (%s)" % [int(reward.modifier_amount), upgrade_name, board_name]
	return ""


func _format_starting_modifier(reward: ChallengeRewardData) -> String:
	var board_name: String = Enums.BoardType.keys()[reward.board_type].capitalize()
	match reward.modifier_type:
		ChallengeRewardData.ModifierType.STARTING_COINS:
			var currency_name: String = FormatUtils.currency_name(reward.currency_type, false)
			return "+%d starting %s" % [int(reward.modifier_amount), currency_name]
		ChallengeRewardData.ModifierType.MULTI_DROP:
			return "+%d multi-drop (%s)" % [int(reward.modifier_amount), board_name]
		ChallengeRewardData.ModifierType.ADVANCED_COIN_MULTIPLIER:
			return "+%.1fx advanced multiplier (%s)" % [reward.modifier_amount, board_name]
		ChallengeRewardData.ModifierType.BUCKET_VALUE_PERCENT:
			return "+%d%% bucket value (%s)" % [int(reward.modifier_amount * 100), board_name]
		ChallengeRewardData.ModifierType.STARTING_AUTODROPPERS:
			return "+%d starting autodroppers (%s)" % [int(reward.modifier_amount), board_name]
	return ""


func _on_challenge_failed(reason: String) -> void:
	challenge_hud.show_result("Failed: %s" % reason)
	await get_tree().create_timer(2.0).timeout
	ChallengeManager.clear_challenge()
	SaveManager.reset_state()
	ThemeProvider.set_theme(ThemeProvider.Kind.NORMAL)
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
	elif event is InputEventKey and event.pressed and event.keycode == KEY_U:
		CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 1)


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


func _setup_coming_soon_overlay() -> void:
	_coming_soon_overlay = CanvasLayer.new()
	_coming_soon_overlay.set_script(ComingSoonOverlayScript)
	add_child(_coming_soon_overlay)


func _setup_challenge_complete_dialog() -> void:
	_challenge_complete_dialog = ChallengeCompleteDialogScene.instantiate()
	add_child(_challenge_complete_dialog)


## Demo lockdown: shows the "More coming soon!" overlay when the active board
## or challenge group is one of the locked tiers. No-op when demo_mode is off.
func _update_lockdown_overlay() -> void:
	if not demo_mode:
		_coming_soon_overlay.visible = false
		return
	var should_show := false
	if ModeManager.is_main():
		var board := board_manager.get_active_board()
		if board and board.board_type == Enums.BoardType.RED:
			should_show = true
	elif ModeManager.is_challenges():
		var group := challenge_grouping_manager.get_active_group()
		if group and (group.board_type == Enums.BoardType.ORANGE or group.board_type == Enums.BoardType.RED):
			should_show = true
	_coming_soon_overlay.visible = should_show


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
		ChallengeProgressManager.challenges_ever_visited = true
		coin_values.visible = false
		level_section.visible = false
		game_timer.visible = false
		challenges_down_icon.visible = false
		board_manager.set_active_board_ui_visible(false)
		challenges_up_icon.visible = true
		challenge_info_panel.visible = true
		challenge_grouping_manager.enter_challenges_mode()
		_update_nav_arrows()
		_update_lockdown_overlay()
	else:
		coin_values.visible = true
		level_section.visible = true
		game_timer.visible = true
		challenges_down_icon.visible = ModeManager.are_challenges_unlocked()
		board_manager.set_active_board_ui_visible(true)
		challenges_up_icon.visible = false
		challenge_info_panel.visible = false
		_update_nav_arrows()
		_update_lockdown_overlay()
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
	_update_nav_arrow_blinks()


func _on_board_switched(board: PlinkoBoard) -> void:
	# Clear unseen flag for the board we just navigated to
	_boards_with_unseen_upgrades.erase(board.board_type)
	_update_nav_arrows()
	_update_lockdown_overlay()


func _on_board_unlocked(board_type: Enums.BoardType) -> void:
	# Connect the newly unlocked board to the prestige animator
	for board in board_manager.get_boards():
		if board.board_type == board_type:
			prestige_animator.connect_board(board)
			break
	if not _loading_from_save:
		_boards_with_unseen_upgrades[board_type] = true
	_update_nav_arrows()


func _on_group_switched(_group: ChallengeGrouping) -> void:
	_update_nav_arrows()
	_update_lockdown_overlay()


func _on_upgrade_unlocked_for_nav(_upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType) -> void:
	# If the upgrade is on a board that isn't currently active, mark it unseen
	var active_board := board_manager.get_active_board()
	if active_board.board_type != board_type:
		_boards_with_unseen_upgrades[board_type] = true
	_update_nav_arrow_blinks()


func _update_nav_arrows() -> void:
	if ModeManager.is_main():
		board_left_icon.visible = board_manager._active_index > 0
		board_right_icon.visible = board_manager._active_index + 1 < board_manager._boards.size()
	elif ModeManager.is_challenges():
		board_left_icon.visible = challenge_grouping_manager.has_prev_group()
		board_right_icon.visible = challenge_grouping_manager.has_next_group()
	_update_nav_arrow_blinks()


func _update_nav_arrow_blinks() -> void:
	# Challenges down arrow: blink if challenges are unlocked but never visited
	var should_blink_down := challenges_down_icon.visible and not ChallengeProgressManager.challenges_ever_visited
	_set_arrow_blink(challenges_down_icon, should_blink_down)

	# Right arrow: blink if any board to the right has unseen upgrades
	var should_blink_right := false
	if board_right_icon.visible and ModeManager.is_main():
		var boards := board_manager.get_boards()
		for i in range(board_manager._active_index + 1, boards.size()):
			if boards[i].board_type in _boards_with_unseen_upgrades:
				should_blink_right = true
				break
	_set_arrow_blink(board_right_icon, should_blink_right)

	# Left arrow: blink if any board to the left has unseen upgrades
	var should_blink_left := false
	if board_left_icon.visible and ModeManager.is_main():
		var boards := board_manager.get_boards()
		for i in range(0, board_manager._active_index):
			if boards[i].board_type in _boards_with_unseen_upgrades:
				should_blink_left = true
				break
	_set_arrow_blink(board_left_icon, should_blink_left)


func _set_arrow_blink(arrow: Control, should_blink: bool) -> void:
	var is_blinking := arrow in _arrow_blink_tweens
	if should_blink and not is_blinking:
		_arrow_blink_tweens[arrow] = ThemeProvider.theme.blink_scale_fade(arrow)
	elif not should_blink and is_blinking:
		_arrow_blink_tweens[arrow].kill()
		_arrow_blink_tweens.erase(arrow)
		arrow.scale = Vector2.ONE
		arrow.modulate.a = 1.0


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
