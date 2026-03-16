class_name PlinkoBoard
extends Node3D

@export var num_rows: int = 2
@export var space_between_pegs: float = 1.0
@export var vertical_spacing: float
@export var drop_delay: float = 2.0
@export var drop_delay_reduction_factor: float = 0.75
@export var distance_for_advanced_buckets: int = 3

const PegScene := preload("res://entities/peg/peg.tscn")
const BucketScene: PackedScene = preload("res://entities/bucket/bucket.tscn")
const CoinScene := preload("res://entities/coin/coin.tscn")
const DropButtonScene := preload("res://entities/drop_section/drop_button.tscn")

@onready var pegs_container: Node3D = $Pegs
@onready var buckets_container: Node3D = $Buckets
@onready var upgrade_section = $UpgradeSection
@onready var drop_section = $DropSection
@onready var coin_queue: CoinQueue = $CoinQueue
@onready var drop_status_label: Label = $DropSection/VBoxContainer/StatusLabel
@onready var drop_region_buttons: HBoxContainer = $DropSection/VBoxContainer/HBoxContainer

var board_type: Enums.BoardType
var advanced_bucket_type: Enums.CurrencyType
var is_waiting: bool = false
var bucket_value_multiplier: int = 1
var should_show_advanced_buckets: bool = false
var _advanced_drop_button: DropButton
var _drop_buttons: Dictionary = {}  # StringName -> DropButton

signal board_rebuilt
signal autodropper_adjust_requested(button_id: StringName, delta: int)

var _drop_timer_remaining: float = 0.0

func _ready() -> void:
	vertical_spacing = space_between_pegs * sqrt(3) / 2 # sqrt because of the 30/60/90 triangle babyyyy
	var normal_id := StringName("%s_NORMAL" % Enums.BoardType.keys()[board_type])
	var drop_button = _create_drop_button(normal_id, _get_drop_costs())
	drop_button.drop_pressed.connect(func(): request_drop())
	# Assign spacebar shortcut so the button visually reacts to the key
	var shortcut := Shortcut.new()
	var key_event := InputEventAction.new()
	key_event.action = "drop_coin"
	shortcut.events = [key_event]
	drop_button.set_shortcut(shortcut)
	drop_region_buttons.add_child(drop_button)
	_update_drop_status()



func setup(type: Enums.BoardType) -> void:
	board_type = type
	upgrade_section.setup(self, type)
	build_board()
	coin_queue.setup(Vector3(0, vertical_spacing + 0.2, 0))
	LevelManager.rewards_claimed.connect(_on_rewards_claimed)
	CurrencyManager.currency_changed.connect(_on_currency_changed)

	# Each board tier doubles the base drop delay: gold=2s, orange=4s, red=8s, etc.
	drop_delay = drop_delay * pow(2, board_type)

	match board_type:
		Enums.BoardType.GOLD:
			advanced_bucket_type = Enums.CurrencyType.RAW_ORANGE
		Enums.BoardType.ORANGE:
			advanced_bucket_type = Enums.CurrencyType.RAW_RED

	# Position the label above the drop point
	# drop_status_label.position = Vector3(0, vertical_spacing + 0.7, 0)



func _process(delta: float) -> void:
	if is_waiting:
		_drop_timer_remaining = maxf(0.0, _drop_timer_remaining - delta)
		_update_drop_status()


func request_drop(costs: Array = [], coin_type: int = -1) -> void:
	if costs.is_empty():
		costs = _get_drop_costs()
	var drop_coin_type: Enums.CurrencyType = (coin_type as Enums.CurrencyType) if coin_type != -1 else Enums.currency_for_board(board_type)

	if not _can_afford(costs):
		return

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


## Returns the costs to drop a normal coin on this board.
func _get_drop_costs() -> Array:
	match board_type:
		Enums.BoardType.GOLD:
			return [[Enums.CurrencyType.GOLD_COIN, 1]]
		Enums.BoardType.ORANGE:
			return [[Enums.CurrencyType.RAW_ORANGE, 1], [Enums.CurrencyType.GOLD_COIN, 100]]
		Enums.BoardType.RED:
			return [[Enums.CurrencyType.RAW_RED, 1], [Enums.CurrencyType.ORANGE_COIN, 100]]
		_:
			return []


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
	_update_drop_status()
	if coin_queue.has_queue() and not coin_queue.is_empty():
		_drop_from_queue()

func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
	if not _advanced_drop_button and board_type != Enums.BoardType.RED \
			and _type == advanced_bucket_type and _new_balance > 0:
		_spawn_advanced_drop_button()
	if not is_waiting:
		_update_drop_status()


func _update_drop_status() -> void:
	var text: String
	if is_waiting:
		text = "%.1fs" % _drop_timer_remaining
	else:
		var parts: PackedStringArray = []
		for cost in _get_drop_costs():
			var currency_name: String = Enums.CurrencyType.keys()[cost[0]].to_lower().replace("_", " ")
			parts.append("%d %s" % [cost[1], currency_name])
		text = "Need " + ", ".join(parts)

	if coin_queue.has_queue():
		text += " [%d/%d]" % [coin_queue.count, coin_queue._capacity]

	drop_status_label.text = text


func on_coin_landed(coin: Coin) -> void:
	var bucket = get_nearest_bucket(coin.global_position.x)
	var amount = bucket.value * coin.multiplier
	CurrencyManager.add(bucket.currency_type, amount)
	if coin.multiplier > 1:
		_show_floating_text(coin.global_position, coin.multiplier, amount)
	coin.queue_free()


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
		elif reward.type == RewardData.RewardType.UNLOCK_ADVANCED_BUCKET and reward.target_board == board_type:
			should_show_advanced_buckets = true
			build_board()

func _spawn_advanced_drop_button() -> void:
	var adv_id := StringName("%s_ADVANCED" % Enums.BoardType.keys()[board_type])
	var adv_button = _create_drop_button(adv_id, _get_advanced_drop_costs())
	adv_button.drop_pressed.connect(func(): request_drop(_get_advanced_drop_costs(), advanced_bucket_type))
	drop_region_buttons.add_child(adv_button)
	_advanced_drop_button = adv_button


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

	for i in range(num_rows):
		var x_offset = -i * space_between_pegs / 2
		var y = -vertical_spacing * i
		for j in range(i + 1):
			var peg = PegScene.instantiate()
			peg.position = Vector3(x_offset + (j * space_between_pegs), y, 0)
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
	var label := Label3D.new()
	label.text = "x%d = %d" % [multiplier, total]
	label.font_size = 40
	label.position = Vector3(pos.x, pos.y + 0.3, pos.z + 0.05)
	if multiplier >= 9:
		label.modulate = Color(1, 0.3, 0.3, 1)
	add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y + 1.5, 1.2)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.6)
	tween.tween_callback(label.queue_free)


func increase_queue_capacity() -> void:
	coin_queue.set_capacity(coin_queue._capacity + 1)


func _create_drop_button(btn_id: StringName, costs: Array) -> DropButton:
	var button = DropButtonScene.instantiate()
	var currencies_needed: Array[DropButton.CurrencyNeeded] = []
	var label_parts: PackedStringArray = []
	for cost in costs:
		currencies_needed.append(DropButton.CurrencyNeeded.new(cost[0], cost[1]))
		label_parts.append("%d %s" % [cost[1], Enums.CurrencyType.keys()[cost[0]].to_lower().replace("_", " ")])
	var cost_str := ", ".join(label_parts)
	var coin_name: String = Enums.CurrencyType.keys()[costs[0][0]].to_lower().replace("_", " ")
	button.setup(currencies_needed, "Drop %s (%s)" % [coin_name, cost_str], btn_id)
	button.autodropper_adjust_requested.connect(
		func(bid: StringName, delta: int): autodropper_adjust_requested.emit(bid, delta)
	)
	_drop_buttons[btn_id] = button
	return button


func try_autodrop(is_advanced: bool) -> void:
	var costs: Array = _get_advanced_drop_costs() if is_advanced else _get_drop_costs()
	var coin_type: int = advanced_bucket_type if is_advanced else -1
	if _can_afford(costs):
		request_drop(costs, coin_type)


func set_autodroppers_visible(vis: bool) -> void:
	for button in _drop_buttons.values():
		button.show_autodropper_controls(vis)


func get_drop_button(btn_id: StringName) -> DropButton:
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
		_spawn_advanced_drop_button()

	build_board()
