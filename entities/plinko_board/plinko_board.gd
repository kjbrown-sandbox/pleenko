class_name PlinkoBoard
extends Node3D

@export var num_rows: int = 2
var space_between_pegs: float
var vertical_spacing: float
@export var drop_delay: float = 2.0
@export var drop_delay_reduction_factor: float = 0.75
@export var distance_for_advanced_buckets: int = 3 # Before you modify this, know I've tested it and 4 feel awful

const PegScene := preload("res://entities/peg/peg.tscn")
const BucketScene: PackedScene = preload("res://entities/bucket/bucket.tscn")
const CoinScene := preload("res://entities/coin/coin.tscn")

@onready var pegs_container: Node3D = $Pegs
@onready var buckets_container: Node3D = $Buckets
@onready var upgrade_section = $UpgradeSection
@onready var drop_section = $DropSection
@onready var coin_queue: CoinQueue = $CoinQueue
@onready var _drop_main = $DropSection/DropButtons/DropMain
@onready var _drop_advanced = $DropSection/DropButtons/DropAdvanced
@onready var _drop_buttons_container = $DropSection/DropButtons

var board_type: Enums.BoardType
var advanced_bucket_type: Enums.CurrencyType
var is_waiting: bool = false
var bucket_value_multiplier: int = 1
var should_show_advanced_buckets: bool = false
var _has_advanced_drop: bool = false
var _autodroppers_visible: bool = false
var _drop_buttons: Dictionary = {}  # StringName -> node (for autodropper lookup)
var _drop_hover_label: Label
var multi_drop_count: int = -1

signal board_rebuilt
signal autodropper_adjust_requested(button_id: StringName, delta: int)
signal coin_landed(board_type: Enums.BoardType, bucket_index: int, currency_type: Enums.CurrencyType, amount: int)
signal autodrop_failed(board_type: Enums.BoardType)

var _drop_timer_remaining: float = 0.0

func _ready() -> void:
	space_between_pegs = ThemeProvider.theme.space_between_pegs
	vertical_spacing = space_between_pegs * sqrt(3) / 2 # sqrt because of the 30/60/90 triangle babyyyy
	multi_drop_count = PrestigeManager.get_multi_drop(board_type) + ChallengeProgressManager.get_bonus_multi_drop(board_type)


func setup(type: Enums.BoardType) -> void:
	board_type = type

	drop_delay = TierRegistry.get_base_drop_delay(board_type)
	var adv: int = TierRegistry.advanced_bucket_currency(board_type)
	if adv >= 0:
		advanced_bucket_type = adv

	_setup_drop_bars()
	_update_drop_fill()
	upgrade_section.setup(self, type)
	build_board()
	coin_queue.setup(Vector3(0, vertical_spacing + 0.2, 0))
	LevelManager.rewards_claimed.connect(_on_rewards_claimed)
	CurrencyManager.currency_changed.connect(_on_currency_changed)


func _setup_drop_bars() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var currency_type: Enums.CurrencyType = Enums.currency_for_board(board_type)
	var coin_color: Color = t.get_coin_color(currency_type)
	var coin_color_dark: Color = t.get_coin_color_dark(currency_type)

	# Main drop bar
	_drop_main.setup(coin_color, coin_color_dark)
	_drop_main.update_text("Drop %s" % Enums.currency_name(currency_type))
	_drop_main.main_pressed.connect(func(): request_drop())
	_drop_main.main_mouse_entered.connect(_on_drop_main_hover)
	_drop_main.main_mouse_exited.connect(_on_drop_hover_exit)
	_drop_main.side_button_hover.connect(_on_drop_side_hover)

	# Spacebar shortcut
	var shortcut := Shortcut.new()
	var key_event := InputEventAction.new()
	key_event.action = "drop_coin"
	shortcut.events = [key_event]
	_drop_main.main_button.shortcut = shortcut
	_drop_main.main_button.shortcut_in_tooltip = false

	var normal_id := StringName("%s_NORMAL" % Enums.BoardType.keys()[board_type])
	_drop_buttons[normal_id] = _drop_main

	# Advanced drop bar — hidden until earned
	_drop_advanced.visible = false

	# Hover label — positioned above the drop buttons, outside the VBox so it
	# doesn't affect button sizing.
	_drop_hover_label = Label.new()
	_drop_hover_label.visible = false
	_drop_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drop_hover_label.add_theme_font_size_override("font_size", int(t.button_font_size))
	_drop_hover_label.add_theme_constant_override("line_spacing", -int(t.button_font_size) / 3)
	_drop_hover_label.add_theme_color_override("font_color", t.resolve(VisualTheme.Palette.BG_5))
	var font: Font = t.button_font if t.button_font else t.label_font
	if font:
		_drop_hover_label.add_theme_font_override("font", font)
	drop_section.add_child(_drop_hover_label)


func _format_cost_text(costs: Array) -> String:
	var parts: PackedStringArray = []
	for cost in costs:
		parts.append("%d %s" % [cost[1], Enums.currency_name(cost[0], false)])
	return ", ".join(parts)


func _on_drop_main_hover() -> void:
	_drop_main.pulse_main(1.005)
	_show_drop_hover("Cost: %s\nHotkey: SPACE" % _format_cost_text(_get_drop_costs()))


func _on_drop_advanced_hover() -> void:
	_drop_advanced.pulse_main(1.005)
	_show_drop_hover("Cost: %s" % _format_cost_text(_get_advanced_drop_costs()))


func _on_drop_hover_exit() -> void:
	_drop_hover_label.visible = false


func _show_drop_hover(text: String) -> void:
	_drop_hover_label.text = text
	_drop_hover_label.size = Vector2.ZERO  # Reset so it auto-sizes to text
	_drop_hover_label.visible = true
	# Position centered above the drop buttons container (deferred so size is computed)
	_position_drop_hover.call_deferred()


func _position_drop_hover() -> void:
	var container_pos: Vector2 = _drop_buttons_container.global_position
	var container_size: Vector2 = _drop_buttons_container.size
	var label_size: Vector2 = _drop_hover_label.size
	_drop_hover_label.global_position = Vector2(
		container_pos.x + (container_size.x - label_size.x) / 2.0,
		container_pos.y - label_size.y - 10.0
	)


func _on_drop_side_hover(text: String) -> void:
	if text.is_empty():
		_drop_hover_label.visible = false
	else:
		_show_drop_hover(text)


func _process(delta: float) -> void:
	if is_waiting:
		_drop_timer_remaining = maxf(0.0, _drop_timer_remaining - delta)
		_update_drop_fill()


func request_drop(costs: Array = [], coin_type: int = -1) -> void:
	if costs.is_empty():
		costs = _get_drop_costs()
	var drop_coin_type: Enums.CurrencyType = (coin_type as Enums.CurrencyType) if coin_type != -1 else Enums.currency_for_board(board_type)

	if not _can_afford(costs):
		return

	multi_drop_count = PrestigeManager.get_multi_drop(board_type) + ChallengeProgressManager.get_bonus_multi_drop(board_type)

	# First coin — normal queue/immediate path (pays cost once)
	var coin: Coin = CoinScene.instantiate()
	coin.coin_type = drop_coin_type
	if drop_coin_type == advanced_bucket_type:
		coin.multiplier = 3

	if coin_queue.has_queue() and not coin_queue.is_full():
		_spend(costs)
		coin_queue.enqueue(coin)
		if not is_waiting:
			_drop_from_queue()
	elif not is_waiting:
		_spend(costs)
		_drop_immediate_coin(coin)
	else:
		return  # Can't drop right now

	# Extra coins — staggered, bypass queue and cost
	var mult := 3 if drop_coin_type == advanced_bucket_type else 1
	for i in range(1, multi_drop_count):
		get_tree().create_timer(i * 0.15).timeout.connect(
			force_drop_coin.bind(drop_coin_type, mult)
		)

	if multi_drop_count > 1:
		_show_multi_drop_label(multi_drop_count)


## Returns the costs to drop a normal coin on this board.
func _get_drop_costs() -> Array:
	return TierRegistry.get_drop_costs(board_type)


## Returns the cost to drop an advanced coin (1 raw currency of the next tier).
func _get_advanced_drop_costs() -> Array:
	return [[advanced_bucket_type, 1]]


func _can_afford(costs: Array) -> bool:
	for cost in costs:
		if not CurrencyManager.can_afford(cost[0], cost[1]):
			return false
	return true


func _spend(costs: Array) -> void:
	for cost in costs:
		CurrencyManager.spend(cost[0], cost[1])


func _drop_immediate_coin(coin: Coin) -> void:
	coin.board = self
	coin.position = Vector3(0, vertical_spacing + 0.2, 0)
	add_child(coin)
	coin.start(Vector3(0, 0.2, 0))
	_start_drop_timer()


func _drop_from_queue() -> void:
	if coin_queue.is_empty():
		return

	var coin: Coin = coin_queue.dequeue()
	coin.board = self
	coin.position = Vector3(0, vertical_spacing + 0.2, 0)
	coin.rotation = Vector3.ZERO
	add_child(coin)
	coin.start(Vector3(0, 0.2, 0))
	_start_drop_timer()


func _start_drop_timer() -> void:
	is_waiting = true
	_drop_timer_remaining = drop_delay
	get_tree().create_timer(drop_delay).timeout.connect(_on_drop_timer_done)


func _on_drop_timer_done() -> void:
	is_waiting = false
	_drop_timer_remaining = 0.0
	_update_drop_fill()
	if coin_queue.has_queue() and not coin_queue.is_empty():
		_drop_from_queue()


func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
	if not _has_advanced_drop and TierRegistry.has_next_tier(board_type) \
			and _type == advanced_bucket_type and _new_balance > 0:
		_show_advanced_drop_bar()
	_update_drop_fill()


func _update_drop_fill() -> void:
	var can_queue: bool = coin_queue.has_queue() and not coin_queue.is_full()
	var show_cooldown: bool = is_waiting and not can_queue

	var fill_pct: float
	if show_cooldown:
		fill_pct = 1.0 - (_drop_timer_remaining / drop_delay) if drop_delay > 0 else 1.0
	else:
		fill_pct = 1.0

	# Normal drop bar
	_drop_main.set_fill(fill_pct)
	var can_drop_normal: bool = _can_afford(_get_drop_costs()) and not show_cooldown
	_drop_main.set_main_disabled(not can_drop_normal)
	_drop_main.apply_fill_colors(not can_drop_normal)

	# Advanced drop bar
	if _drop_advanced.visible:
		_drop_advanced.set_fill(fill_pct)
		var can_drop_advanced: bool = _can_afford(_get_advanced_drop_costs()) and not show_cooldown
		_drop_advanced.set_main_disabled(not can_drop_advanced)
		_drop_advanced.apply_fill_colors(not can_drop_advanced)


func on_coin_landed(coin: Coin) -> void:
	var bucket = get_nearest_bucket(coin.global_position.x)
	var bucket_idx := _get_bucket_index(bucket)
	var amount = bucket.value * coin.multiplier
	CurrencyManager.add(bucket.currency_type, amount)
	coin_landed.emit(board_type, bucket_idx, bucket.currency_type, amount)
	bucket.pulse()
	if coin.multiplier > 1:
		_show_floating_text(coin.global_position, coin.multiplier, amount)
	coin.queue_free()


func _get_bucket_index(bucket: Bucket) -> int:
	var children := buckets_container.get_children()
	return children.find(bucket)


func force_drop_coin(type: Enums.CurrencyType, mult: int = 1) -> void:
	var coin = CoinScene.instantiate()
	coin.board = self
	coin.coin_type = type
	coin.multiplier = mult
	coin.position = Vector3(0, vertical_spacing + 0.2, 0)
	add_child(coin)
	coin.start(Vector3(0, 0.2, 0))


func _on_rewards_claimed(_level: int, rewards: Array[RewardData]) -> void:
	for reward in rewards:
		if reward.type == RewardData.RewardType.DROP_COINS and reward.target_board == board_type:
			for i in reward.coin_count:
				force_drop_coin(reward.coin_type, reward.coin_multiplier)
		elif reward.type == RewardData.RewardType.UNLOCK_UPGRADE and reward.board_type == board_type:
			if ChallengeManager.is_active_challenge and not ChallengeManager.is_upgrade_allowed(reward.upgrade_type):
				# Drop an advanced coin instead of unlocking a blocked upgrade
				if advanced_bucket_type >= 0:
					force_drop_coin(advanced_bucket_type, 3)
				else:
					force_drop_coin(Enums.currency_for_board(board_type), 3)
		elif reward.type == RewardData.RewardType.UNLOCK_ADVANCED_BUCKET and reward.target_board == board_type:
			should_show_advanced_buckets = true
			build_board()

func _show_advanced_drop_bar() -> void:
	if _has_advanced_drop:
		return
	_has_advanced_drop = true
	var t: VisualTheme = ThemeProvider.theme
	var adv_color: Color = t.get_coin_color(advanced_bucket_type)
	var adv_color_dark: Color = t.get_coin_color_dark(advanced_bucket_type)
	_drop_advanced.setup(adv_color, adv_color_dark)
	_drop_advanced.update_text("Drop %s" % Enums.currency_name(advanced_bucket_type))
	_drop_advanced.main_pressed.connect(func(): request_drop(_get_advanced_drop_costs(), advanced_bucket_type))
	_drop_advanced.main_mouse_entered.connect(_on_drop_advanced_hover)
	_drop_advanced.main_mouse_exited.connect(_on_drop_hover_exit)
	_drop_advanced.side_button_hover.connect(_on_drop_side_hover)
	_drop_advanced.visible = true
	var adv_id := StringName("%s_ADVANCED" % Enums.BoardType.keys()[board_type])
	_drop_buttons[adv_id] = _drop_advanced
	if _autodroppers_visible:
		_setup_autodropper_buttons(adv_id)


func get_nearest_bucket(x_position: float) -> Bucket:
	for bucket in buckets_container.get_children():
		if abs(bucket.global_position.x - x_position) < 0.5:
			return bucket
	return buckets_container.get_children()[0]

func build_board() -> void:
	for child in pegs_container.get_children():
		child.queue_free()

	for child in buckets_container.get_children():
		child.queue_free()

	var t: VisualTheme = ThemeProvider.theme
	var peg_mesh := t.make_peg_mesh()
	var peg_mat := t.make_peg_material()

	for i in range(num_rows):
		var x_offset = -i * space_between_pegs / 2
		var y = -vertical_spacing * i
		for j in range(i + 1):
			var peg = PegScene.instantiate()
			peg.position = Vector3(x_offset + (j * space_between_pegs), y, 0)
			var mesh_instance: MeshInstance3D = peg.get_node("MeshInstance3D")
			mesh_instance.mesh = peg_mesh
			mesh_instance.material_override = peg_mat
			if t.peg_shape == VisualTheme.PegShape.CYLINDER:
				mesh_instance.rotation = Vector3(PI / 2, 0, 0)
			else:
				mesh_instance.rotation = Vector3.ZERO
			pegs_container.add_child(peg)

	var num_buckets = num_rows + 1
	var bucket_x_offset = -space_between_pegs * (num_buckets - 1) / 2
	var bucket_y_offset = -vertical_spacing * num_rows + (vertical_spacing / 3)
	buckets_container.position = Vector3(bucket_x_offset, bucket_y_offset, 0)
	
	for i in range(num_buckets):
		var bucket = BucketScene.instantiate()

		@warning_ignore("integer_division")

		var distance_from_center = (abs(i - floor(num_buckets / 2))) 

		var value = 1
		var bucket_currency: Enums.CurrencyType = Enums.currency_for_board(board_type)
		if distance_from_center >= distance_for_advanced_buckets and should_show_advanced_buckets:
			bucket_currency = advanced_bucket_type
			distance_from_center -= distance_for_advanced_buckets

		value += distance_from_center * bucket_value_multiplier
		bucket.setup(bucket_currency, Vector3(i * space_between_pegs, 0, 0), value)
		buckets_container.add_child(bucket)

	board_rebuilt.emit()


## Returns the bounding rect of this board in local space.
## Used by BoardManager to frame the camera.
func get_bounds() -> Rect2:
	var top := vertical_spacing + 0.5
	var bottom := -vertical_spacing * num_rows + (vertical_spacing / 3) - 0.5
	var half_width := (num_rows / 2.0) * space_between_pegs + 0.5
	return Rect2(-half_width, bottom, half_width * 2.0, top - bottom)


func add_two_rows() -> void:
	num_rows += 2
	build_board()

func increase_bucket_values() -> void:
	bucket_value_multiplier += 1
	build_board()

func decrease_drop_delay() -> void:
	drop_delay *= drop_delay_reduction_factor

func _show_floating_text(pos: Vector3, multiplier: int, total: int) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var label := Label3D.new()
	label.text = "x%d = %d" % [multiplier, total]
	label.font_size = t.floating_text_font_size
	label.outline_size = t.label_outline_size
	if t.label_font:
		label.font = t.label_font
	label.position = Vector3(pos.x, pos.y + 0.3, pos.z + 0.05)
	if multiplier >= 9:
		label.modulate = t.high_multiplier_color
	add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y + t.floating_text_rise, t.floating_text_duration)
	tween.parallel().tween_property(label, "modulate:a", 0.0, t.floating_text_duration * 0.5) \
		.set_delay(t.floating_text_duration * 0.5)
	tween.tween_callback(label.queue_free)


func _show_multi_drop_label(count: int) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var label := Label3D.new()
	label.text = "x%d" % count
	label.font_size = t.multi_drop_font_size
	label.outline_size = t.label_outline_size
	if t.label_font:
		label.font = t.label_font
	label.position = Vector3(0, vertical_spacing + 0.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y + 0.5, 0.6)
	tween.parallel().tween_property(label, "modulate", Color(1, 1, 1, 0), 0.6)
	tween.tween_callback(label.queue_free)


func increase_queue_capacity() -> void:
	coin_queue.set_capacity(coin_queue._capacity + 1)


func try_autodrop(is_advanced: bool) -> void:
	var costs: Array = _get_advanced_drop_costs() if is_advanced else _get_drop_costs()
	var coin_type: int = advanced_bucket_type if is_advanced else -1
	if _can_afford(costs):
		request_drop(costs, coin_type)
	else:
		autodrop_failed.emit(board_type)


func set_autodroppers_visible(vis: bool) -> void:
	_autodroppers_visible = vis
	if vis:
		for bid in _drop_buttons:
			_setup_autodropper_buttons(bid)


func _setup_autodropper_buttons(bid: StringName) -> void:
	var bar = _drop_buttons[bid]
	var currency_name: String = _get_currency_name_for_button(bid)
	var captured_bid: StringName = bid

	bar.setup_minus(
		func(): autodropper_adjust_requested.emit(captured_bid, -1),
		func() -> String:
			var total: int = UpgradeManager.get_level(Enums.BoardType.ORANGE, Enums.UpgradeType.AUTODROPPER)
			return "Decrease autodropper for %s\nTotal autodroppers: %d" % [currency_name, total],
	)

	bar.setup_plus(
		func(): autodropper_adjust_requested.emit(captured_bid, 1),
		func() -> String:
			var total: int = UpgradeManager.get_level(Enums.BoardType.ORANGE, Enums.UpgradeType.AUTODROPPER)
			return "Increase autodropper for %s\nTotal autodroppers: %d" % [currency_name, total],
	)


func _get_currency_name_for_button(bid: StringName) -> String:
	if (bid as String).ends_with("_ADVANCED"):
		return Enums.currency_name(advanced_bucket_type, false)
	return Enums.currency_name(Enums.currency_for_board(board_type), false)


func update_autodropper_buttons(assignments: Dictionary, free_count: int) -> void:
	for bid in _drop_buttons:
		var bar = _drop_buttons[bid]
		var assigned: int = assignments.get(bid, 0)
		bar.set_minus_disabled(assigned <= 0)
		bar.set_plus_disabled(free_count <= 0)


func get_drop_button(btn_id: StringName):
	return _drop_buttons.get(btn_id)


## Applies saved upgrade state to this board without going through buy logic.
func apply_saved_state(upgrade_state: Dictionary) -> void:
	var add_row_level: int = upgrade_state.get("ADD_ROW", 0)
	num_rows = 2 + add_row_level * 2

	bucket_value_multiplier = 1 + upgrade_state.get("BUCKET_VALUE", 0)

	var drop_rate_level: int = upgrade_state.get("DROP_RATE", 0)
	for i in drop_rate_level:
		drop_delay *= drop_delay_reduction_factor

	var queue_level: int = upgrade_state.get("QUEUE", 0)
	coin_queue.set_capacity(queue_level)

	if upgrade_state.get("show_advanced_buckets", false):
		should_show_advanced_buckets = true
		_show_advanced_drop_bar()

	build_board()
