class_name PlinkoBoard
extends Node3D

@export var num_rows: int = 2
var space_between_pegs: float
var vertical_spacing: float
@export var drop_delay: float = 2.0
@export var drop_delay_reduction_factor: float = 0.75
@export var distance_for_advanced_buckets: int = 3 # Before you modify this, know I've tested it and 4 feel awful

## Delay between each bonus coin in a multi-drop, so they don't all land simultaneously.
const MULTI_DROP_STAGGER := 0.15

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
@onready var _drop_tooltip: Tooltip = $DropSection/DropTooltip

var board_type: Enums.BoardType
var advanced_bucket_type: Enums.CurrencyType
var is_waiting: bool = false
var bucket_value_multiplier: int = 1
var advanced_coin_multiplier: float = 2.0
var should_show_advanced_buckets: bool = false
var _has_advanced_drop: bool = false
var _normal_autodroppers_visible: bool = false
var _advanced_autodroppers_visible: bool = false
var _drop_buttons: Dictionary = {}  # StringName -> node (for autodropper lookup)
var _bucket_markings: Dictionary = {}  # int (bucket index) -> StringName ("hit" | "target" | "forbidden")
var multi_drop_count: int = -1
var _coin_z_counter: int = 0  # Increments per coin so later coins render in front

signal board_rebuilt
signal autodropper_adjust_requested(button_id: StringName, delta: int)
signal coin_landed(board_type: Enums.BoardType, bucket_index: int, currency_type: Enums.CurrencyType, amount: int)
signal autodrop_failed(board_type: Enums.BoardType)
signal coin_dropped
signal prestige_coin_landed(coin: Coin, bucket: Bucket)

var _drop_timer_remaining: float = 0.0

func _ready() -> void:
	space_between_pegs = ThemeProvider.theme.space_between_pegs
	vertical_spacing = space_between_pegs * sqrt(3) / 2 # sqrt because of the 30/60/90 triangle babyyyy
	multi_drop_count = PrestigeManager.get_multi_drop(board_type) + ChallengeProgressManager.get_bonus_multi_drop(board_type)


func setup(type: Enums.BoardType) -> void:
	board_type = type
	advanced_coin_multiplier = 2.0 + ChallengeProgressManager.get_advanced_coin_multiplier_bonus(board_type)
	multi_drop_count = PrestigeManager.get_multi_drop(board_type) + ChallengeProgressManager.get_bonus_multi_drop(board_type)

	drop_delay = TierRegistry.get_base_drop_delay(board_type)
	var adv: int = TierRegistry.advanced_bucket_currency(board_type)
	if adv >= 0:
		advanced_bucket_type = adv

	# Apply permanent upgrade bonuses from challenge rewards
	bucket_value_multiplier = 1 + ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.BUCKET_VALUE)
	var perm_drop_rate: int = ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.DROP_RATE)
	for i in perm_drop_rate:
		drop_delay *= drop_delay_reduction_factor
	var perm_queue: int = ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.QUEUE)

	_setup_drop_bars()
	_update_drop_fill()
	upgrade_section.setup(self, type)
	build_board()
	coin_queue.setup(Vector3(0, vertical_spacing + 0.2, 0))
	coin_queue.set_capacity(perm_queue)
	LevelManager.rewards_claimed.connect(_on_rewards_claimed)
	CurrencyManager.currency_changed.connect(_on_currency_changed)


func _setup_drop_bars() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var currency_type: Enums.CurrencyType = TierRegistry.primary_currency(board_type)
	var coin_color: Color = t.get_coin_color(currency_type)
	var coin_color_dark: Color = t.get_coin_color_faded(currency_type)

	# Main drop bar
	_drop_main.setup(coin_color, coin_color_dark)
	_drop_main.update_text("Drop %s" % FormatUtils.currency_name(currency_type))
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


func _format_cost_text(costs: Array) -> String:
	var parts: PackedStringArray = []
	for cost in costs:
		parts.append("%s %s" % [FormatUtils.format_number(cost[1]), FormatUtils.currency_name(cost[0], false)])
	return ", ".join(parts)


func _on_drop_main_hover() -> void:
	_drop_main.pulse_main(1.005)
	_drop_tooltip.update_and_show("Cost: %s\nHotkey: SPACE" % _format_cost_text(_get_drop_costs()))


func _on_drop_advanced_hover() -> void:
	_drop_advanced.pulse_main(1.005)
	_drop_tooltip.update_and_show("Cost: %s" % _format_cost_text(_get_advanced_drop_costs()))


func _on_drop_hover_exit() -> void:
	_drop_tooltip.hide_tooltip()


func _on_drop_side_hover(text: String) -> void:
	_drop_tooltip.show_or_hide(text)


func _process(delta: float) -> void:
	if is_waiting:
		_drop_timer_remaining = maxf(0.0, _drop_timer_remaining - delta)
		_update_drop_fill()
	elif _is_hold_to_drop_active():
		request_drop()


func _is_hold_to_drop_active() -> bool:
	return Input.is_action_pressed("drop_coin") \
		and ChallengeProgressManager.is_unlocked(ChallengeRewardData.UnlockType.HOLD_TO_DROP) \
		and drop_section.visible


func request_drop(costs: Array = [], coin_type: int = -1) -> void:
	if ChallengeManager.is_active_challenge and ChallengeManager.has_failed():
		return

	if costs.is_empty():
		costs = _get_drop_costs()
	var drop_coin_type: Enums.CurrencyType = (coin_type as Enums.CurrencyType) if coin_type != -1 else TierRegistry.primary_currency(board_type)

	if not _can_afford(costs):
		return

	multi_drop_count = PrestigeManager.get_multi_drop(board_type) + ChallengeProgressManager.get_bonus_multi_drop(board_type)

	# First coin — normal queue/immediate path (pays cost once)
	var coin: Coin = CoinScene.instantiate()
	coin.coin_type = drop_coin_type
	if drop_coin_type == advanced_bucket_type:
		coin.multiplier = advanced_coin_multiplier

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

	# Multi-drop: first coin pays the cost (above). Bonus coins from prestige/challenges
	# are free and staggered so they don't all land in the same bucket simultaneously.
	var mult: float = advanced_coin_multiplier if drop_coin_type == advanced_bucket_type else 1.0
	for i in range(1, multi_drop_count):
		var tween := create_tween()
		tween.tween_interval(i * MULTI_DROP_STAGGER)
		tween.tween_callback(force_drop_coin.bind(drop_coin_type, mult))

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


func _launch_coin(coin: Coin) -> void:
	coin.board = self
	_coin_z_counter += 1
	coin.position = Vector3(0, vertical_spacing + 0.2, _coin_z_counter * 0.001)
	add_child(coin)
	coin.landed.connect(on_coin_landed)
	coin.final_bounce_started.connect(_on_final_bounce_started)
	coin.start(Vector3(0, 0.2, 0))
	coin_dropped.emit()


func _drop_immediate_coin(coin: Coin) -> void:
	_launch_coin(coin)
	_start_drop_timer()


func _drop_from_queue() -> void:
	if coin_queue.is_empty():
		return

	var coin: Coin = coin_queue.dequeue()
	_launch_coin(coin)
	_start_drop_timer()


func _start_drop_timer() -> void:
	is_waiting = true
	_drop_timer_remaining = drop_delay
	var tween := create_tween()
	tween.tween_interval(drop_delay)
	tween.tween_callback(_on_drop_timer_done)


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
	finalize_coin_landing(coin, bucket)


## Completes the normal landing flow: adds currency, emits signal, cleans up coin.
## Prestige coins skip currency add and queue_free — the PrestigeAnimator handles them.
func finalize_coin_landing(coin: Coin, bucket: Bucket) -> void:
	# Clip the coin so it doesn't poke through the bottom of the bucket
	var t: VisualTheme = ThemeProvider.theme
	coin.set_clip_y(bucket.global_position.y - t.bucket_height / 2.0)

	var bucket_idx := _get_bucket_index(bucket)
	var amount: int = roundi(bucket.value * coin.multiplier)
	if not coin.is_prestige_coin:
		CurrencyManager.add(bucket.currency_type, amount)
		coin_landed.emit(board_type, bucket_idx, bucket.currency_type, amount)
	bucket.pulse()
	if coin.multiplier > 1 and not coin.is_prestige_coin:
		_show_floating_text(coin.global_position, coin.multiplier, amount)
	if not coin.is_prestige_coin:
		coin.queue_free()


## Called when a coin starts its final bounce and we can predict which bucket it will land in.
## If this landing would trigger a prestige, emit prestige_coin_landed so the animator can take over.
func _on_final_bounce_started(coin: Coin, predicted_bucket: Bucket) -> void:
	if _will_trigger_prestige(predicted_bucket.currency_type):
		prestige_coin_landed.emit(coin, predicted_bucket)


## Checks if earning this currency type would trigger a prestige for a new board.
func _will_trigger_prestige(currency_type: Enums.CurrencyType) -> bool:
	for i in range(1, TierRegistry.get_tier_count()):
		var tier := TierRegistry.get_tier_by_index(i)
		if tier.raw_currency == currency_type:
			return PrestigeManager.can_prestige(tier.board_type)
	return false


func _get_bucket_index(bucket: Bucket) -> int:
	var children := buckets_container.get_children()
	return children.find(bucket)


func get_bucket(index: int) -> Bucket:
	var children := buckets_container.get_children()
	if index >= 0 and index < children.size():
		return children[index]
	return null


func mark_bucket_hit(index: int) -> void:
	_bucket_markings[index] = &"hit"
	var bucket := get_bucket(index)
	if bucket:
		bucket.mark_hit()


func mark_bucket_target(index: int) -> void:
	_bucket_markings[index] = &"target"
	var bucket := get_bucket(index)
	if bucket:
		bucket.mark_target()


func mark_bucket_forbidden(index: int) -> void:
	_bucket_markings[index] = &"forbidden"
	var bucket := get_bucket(index)
	if bucket:
		bucket.mark_forbidden()


func unmark_bucket(index: int) -> void:
	_bucket_markings.erase(index)
	var bucket := get_bucket(index)
	if bucket:
		bucket.mark_unhit()


func clear_all_markings() -> void:
	for index in _bucket_markings:
		var bucket := get_bucket(index)
		if bucket:
			bucket.mark_unhit()
	_bucket_markings.clear()


func force_drop_coin(type: Enums.CurrencyType, mult: float = 1.0) -> void:
	var coin = CoinScene.instantiate()
	coin.coin_type = type
	coin.multiplier = mult
	_launch_coin(coin)


func _on_rewards_claimed(_level: int, rewards: Array[RewardData]) -> void:
	for reward in rewards:
		if reward.type == RewardData.RewardType.DROP_COINS and reward.target_board == board_type:
			var mult: float = advanced_coin_multiplier if reward.coin_type == advanced_bucket_type else 1.0
			for i in reward.coin_count:
				force_drop_coin(reward.coin_type, mult)
		elif reward.type == RewardData.RewardType.UNLOCK_UPGRADE and reward.board_type == board_type:
			if ChallengeManager.is_active_challenge and not ChallengeManager.is_upgrade_allowed(reward.upgrade_type):
				# Drop an advanced coin instead of unlocking a blocked upgrade
				if advanced_bucket_type >= 0:
					force_drop_coin(advanced_bucket_type, advanced_coin_multiplier)
				else:
					force_drop_coin(TierRegistry.primary_currency(board_type), advanced_coin_multiplier)
		elif reward.type == RewardData.RewardType.UNLOCK_ADVANCED_BUCKET and reward.target_board == board_type:
			should_show_advanced_buckets = true
			build_board()

func _show_advanced_drop_bar() -> void:
	if _has_advanced_drop:
		return
	_has_advanced_drop = true
	var t: VisualTheme = ThemeProvider.theme
	var adv_color: Color = t.get_coin_color(advanced_bucket_type)
	var adv_color_dark: Color = t.get_coin_color_faded(advanced_bucket_type)
	_drop_advanced.setup(adv_color, adv_color_dark)
	_drop_advanced.update_text("Drop %s" % FormatUtils.currency_name(advanced_bucket_type))
	_drop_advanced.main_pressed.connect(func(): request_drop(_get_advanced_drop_costs(), advanced_bucket_type))
	_drop_advanced.main_mouse_entered.connect(_on_drop_advanced_hover)
	_drop_advanced.main_mouse_exited.connect(_on_drop_hover_exit)
	_drop_advanced.side_button_hover.connect(_on_drop_side_hover)
	_drop_advanced.visible = true
	var adv_id := StringName("%s_ADVANCED" % Enums.BoardType.keys()[board_type])
	_drop_buttons[adv_id] = _drop_advanced
	if _advanced_autodroppers_visible:
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
		buckets_container.remove_child(child)
		child.queue_free()

	var t: VisualTheme = ThemeProvider.theme
	var peg_mesh := t.make_peg_mesh()
	var shared_peg_mat := t.make_peg_material()
	var _peg_list: Array[MeshInstance3D] = []

	for i in range(num_rows):
		var x_offset = -i * space_between_pegs / 2
		var y = -vertical_spacing * i
		for j in range(i + 1):
			var peg = PegScene.instantiate()
			peg.position = Vector3(x_offset + (j * space_between_pegs), y, 0)
			var mesh_instance: MeshInstance3D = peg.get_node("MeshInstance3D")
			mesh_instance.mesh = peg_mesh
			if t.peg_glow_halo_enabled:
				var own_mat := t.make_peg_material()
				mesh_instance.material_override = own_mat
				mesh_instance.set_meta("own_mat", own_mat)
			else:
				mesh_instance.material_override = shared_peg_mat
			if t.peg_shape == VisualTheme.PegShape.CYLINDER:
				mesh_instance.rotation = Vector3(PI / 2, 0, 0)
			else:
				mesh_instance.rotation = Vector3.ZERO
			pegs_container.add_child(peg)
			_peg_list.append(mesh_instance)
	set_meta("pegs", _peg_list)

	var num_buckets = num_rows + 1
	var bucket_x_offset = -space_between_pegs * (num_buckets - 1) / 2
	var bucket_y_offset = -vertical_spacing * num_rows + (vertical_spacing / 3)
	buckets_container.position = Vector3(bucket_x_offset, bucket_y_offset, 0)
	
	for i in range(num_buckets):
		var bucket = BucketScene.instantiate()

		@warning_ignore("integer_division")

		var distance_from_center = (abs(i - floor(num_buckets / 2))) 

		var value = 1
		var bucket_currency: Enums.CurrencyType = TierRegistry.primary_currency(board_type)
		if distance_from_center >= distance_for_advanced_buckets and should_show_advanced_buckets:
			bucket_currency = advanced_bucket_type
			distance_from_center -= distance_for_advanced_buckets

		value += distance_from_center * bucket_value_multiplier
		var pct_bonus := ChallengeProgressManager.get_bucket_value_percent_bonus(board_type)
		if pct_bonus > 0.0:
			value = roundi(value * (1.0 + pct_bonus))
		buckets_container.add_child(bucket)
		bucket.setup(bucket_currency, Vector3(i * space_between_pegs, 0, 0), value)

	# Re-apply stored markings after rebuild
	for index in _bucket_markings:
		var bucket := get_bucket(index)
		if bucket:
			match _bucket_markings[index]:
				&"hit": bucket.mark_hit()
				&"target": bucket.mark_target()
				&"forbidden": bucket.mark_forbidden()

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
	var old_delay := drop_delay
	drop_delay *= drop_delay_reduction_factor
	# If currently waiting, scale remaining time proportionally so the player
	# doesn't have to wait the full old duration
	if is_waiting and old_delay > 0.0:
		_drop_timer_remaining *= drop_delay / old_delay

func _show_floating_text(pos: Vector3, multiplier: float, total: int) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var label := Label3D.new()
	if multiplier == floorf(multiplier):
		label.text = "x%d = %s" % [int(multiplier), FormatUtils.format_number(total)]
	else:
		label.text = "x%.1f = %s" % [multiplier, FormatUtils.format_number(total)]
	label.font_size = t.floating_text_font_size
	label.outline_size = t.label_outline_size
	if t.label_font:
		label.font = t.label_font
	label.modulate = t.normal_text_color
	var local_pos := to_local(pos)
	label.position = Vector3(local_pos.x, local_pos.y + 0.3, local_pos.z + 0.05)
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
	label.modulate = t.normal_text_color
	label.position = Vector3(0, vertical_spacing + 0.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y + 0.5, 0.6)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func flash_nearest_peg(coin_pos: Vector3, currency_type: int) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var pegs: Array = get_meta("pegs", [])
	var closest_peg: MeshInstance3D = null
	var closest_dist := INF

	for peg: MeshInstance3D in pegs:
		if not is_instance_valid(peg):
			continue
		var dist := coin_pos.distance_to(peg.global_position)
		if dist < closest_dist and dist < space_between_pegs * 0.8:
			closest_dist = dist
			closest_peg = peg

	if not closest_peg:
		return

	var peg_mat: StandardMaterial3D = closest_peg.get_meta("own_mat", null)
	if not peg_mat:
		peg_mat = t.make_peg_material()
		closest_peg.set_meta("own_mat", peg_mat)
		closest_peg.material_override = peg_mat

	var glow_color := t.get_coin_color(currency_type)
	peg_mat.albedo_color = glow_color

	var old_tween: Tween = closest_peg.get_meta("glow_tween", null)
	if old_tween and old_tween.is_valid():
		old_tween.kill()

	var glow_tween := create_tween()
	glow_tween.tween_property(peg_mat, "albedo_color", t.peg_color, t.peg_glow_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	closest_peg.set_meta("glow_tween", glow_tween)

	if t.peg_glow_halo_enabled:
		var halo_shader: Shader = preload("res://entities/coin/coin_halo.gdshader")
		var halo := MeshInstance3D.new()
		var halo_mesh := QuadMesh.new()
		halo_mesh.size = Vector2(t.peg_glow_halo_radius, t.peg_glow_halo_radius)
		halo.mesh = halo_mesh
		var halo_mat := ShaderMaterial.new()
		halo_mat.shader = halo_shader
		var halo_color := glow_color
		halo_color.a = t.peg_glow_halo_opacity
		halo_mat.set_shader_parameter("glow_color", halo_color)
		halo_mat.set_shader_parameter("opacity_mult", 1.0)
		halo.material_override = halo_mat
		var local_pos := to_local(closest_peg.global_position)
		halo.position = Vector3(local_pos.x, local_pos.y, local_pos.z - 0.05)
		add_child(halo)
		var halo_tween := create_tween()
		halo_tween.tween_property(halo_mat, "shader_parameter/opacity_mult", 0.0, t.peg_glow_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		halo_tween.tween_callback(halo.queue_free)


func increase_queue_capacity() -> void:
	coin_queue.set_capacity(coin_queue._capacity + 1)


func try_autodrop(is_advanced: bool) -> void:
	var costs: Array = _get_advanced_drop_costs() if is_advanced else _get_drop_costs()
	var coin_type: int = advanced_bucket_type if is_advanced else -1
	if _can_afford(costs):
		request_drop(costs, coin_type)
	else:
		autodrop_failed.emit(board_type)


func set_normal_autodroppers_visible(vis: bool) -> void:
	_normal_autodroppers_visible = vis
	if vis:
		for bid in _drop_buttons:
			if not (bid as String).ends_with("_ADVANCED"):
				_setup_autodropper_buttons(bid)


func set_advanced_autodroppers_visible(vis: bool) -> void:
	_advanced_autodroppers_visible = vis
	if vis:
		for bid in _drop_buttons:
			if (bid as String).ends_with("_ADVANCED"):
				_setup_autodropper_buttons(bid)


func _setup_autodropper_buttons(bid: StringName) -> void:
	var bar = _drop_buttons[bid]
	var currency_name: String = _get_currency_name_for_button(bid)
	var captured_bid: StringName = bid
	var is_adv: bool = (bid as String).ends_with("_ADVANCED")
	var pool_board: Enums.BoardType = Enums.BoardType.RED if is_adv else Enums.BoardType.ORANGE
	var pool_type: Enums.UpgradeType = Enums.UpgradeType.ADVANCED_AUTODROPPER if is_adv else Enums.UpgradeType.AUTODROPPER
	var label: String = "advanced autodropper" if is_adv else "autodropper"

	bar.setup_minus(
		func(): autodropper_adjust_requested.emit(captured_bid, -1),
		func() -> String:
			var total: int = UpgradeManager.get_level(pool_board, pool_type)
			return "Decrease %s for %s\nTotal: %d" % [label, currency_name, total],
	)

	bar.setup_plus(
		func(): autodropper_adjust_requested.emit(captured_bid, 1),
		func() -> String:
			var total: int = UpgradeManager.get_level(pool_board, pool_type)
			return "Increase %s for %s\nTotal: %d" % [label, currency_name, total],
	)


func _get_currency_name_for_button(bid: StringName) -> String:
	if (bid as String).ends_with("_ADVANCED"):
		return FormatUtils.currency_name(advanced_bucket_type, false)
	return FormatUtils.currency_name(TierRegistry.primary_currency(board_type), false)


func update_autodropper_buttons(assignments: Dictionary, normal_free: int, advanced_free: int) -> void:
	for bid in _drop_buttons:
		var bar = _drop_buttons[bid]
		var assigned: int = assignments.get(bid, 0)
		var free: int = advanced_free if (bid as String).ends_with("_ADVANCED") else normal_free
		bar.set_minus_disabled(assigned <= 0)
		bar.set_minus_filled(assigned > 0)
		bar.set_plus_disabled(free <= 0)
		bar.set_plus_filled(free > 0)


func get_drop_button(btn_id: StringName):
	return _drop_buttons.get(btn_id)


## Applies saved upgrade state to this board without going through buy logic.
## Permanent challenge bonuses are added on top of player-bought upgrade levels.
func apply_saved_state(upgrade_state: Dictionary) -> void:
	var add_row_level: int = upgrade_state.get("ADD_ROW", 0)
	num_rows = 2 + add_row_level * 2

	var perm_bv: int = ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.BUCKET_VALUE)
	bucket_value_multiplier = 1 + upgrade_state.get("BUCKET_VALUE", 0) + perm_bv

	var base_acm: float = upgrade_state.get("advanced_coin_multiplier", 2.0)
	var bonus_acm: float = ChallengeProgressManager.get_advanced_coin_multiplier_bonus(board_type)
	advanced_coin_multiplier = base_acm + bonus_acm

	var drop_rate_level: int = upgrade_state.get("DROP_RATE", 0)
	var perm_dr: int = ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.DROP_RATE)
	for i in drop_rate_level + perm_dr:
		drop_delay *= drop_delay_reduction_factor

	var queue_level: int = upgrade_state.get("QUEUE", 0)
	var perm_q: int = ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.QUEUE)
	coin_queue.set_capacity(queue_level + perm_q)

	if upgrade_state.get("show_advanced_buckets", false):
		should_show_advanced_buckets = true
		_show_advanced_drop_bar()

	build_board()
