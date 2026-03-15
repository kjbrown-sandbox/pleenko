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

@onready var pegs_container: Node3D = $Pegs
@onready var buckets_container: Node3D = $Buckets
@onready var upgrade_section = $UpgradeSection
@onready var coin_queue: CoinQueue = $CoinQueue

var board_type: Enums.BoardType
var advanced_bucket_type: Enums.CurrencyType
var is_waiting: bool = false
var bucket_value_multiplier: int = 1
var should_show_advanced_buckets: bool = false

func setup(type: Enums.BoardType) -> void:
	board_type = type
	upgrade_section.setup(self, type)
	build_board()
	coin_queue.setup(Vector3(0, vertical_spacing + 0.2, 0))
	LevelManager.rewards_claimed.connect(_on_rewards_claimed)

	if board_type == Enums.BoardType.GOLD:
		advanced_bucket_type = Enums.CurrencyType.RAW_ORANGE
	elif board_type == Enums.BoardType.ORANGE:
		advanced_bucket_type = Enums.CurrencyType.RAW_RED
	else:
		print("YOU DID NOT FINISH ME")


func request_drop() -> void:
	if not CurrencyManager.can_afford(Enums.currency_for_board(board_type), 1):
		return

	print("coin drop queue, capacity=%d, count=%d" % [coin_queue._capacity, coin_queue.count])
	if coin_queue.has_queue() and not coin_queue.is_full():
		print('enqueueing drop')
		CurrencyManager.spend(Enums.currency_for_board(board_type), 1)
		coin_queue.enqueue()
		# If we're not waiting on a drop delay, start dropping immediately
		if not is_waiting:
			_drop_from_queue()
	elif not is_waiting and CurrencyManager.spend(Enums.currency_for_board(board_type), 1):
		print('drop pping immediately')
		_drop_immediate()


func _drop_immediate() -> void:
	var coin = CoinScene.instantiate()
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
	get_tree().create_timer(drop_delay).timeout.connect(_on_drop_timer_done)


func _on_drop_timer_done() -> void:
	is_waiting = false
	if coin_queue.has_queue() and not coin_queue.is_empty():
		_drop_from_queue()


func on_coin_landed(coin: Coin) -> void:
	var bucket = get_nearest_bucket(coin.global_position.x)
	var amount = bucket.value * coin.multiplier
	CurrencyManager.add(bucket.currency_type, amount)
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

	vertical_spacing = space_between_pegs * sqrt(3) / 2 # sqrt because of the 30/60/90 triangle babyyyy

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

func add_two_rows() -> void:
	num_rows += 2
	build_board()

func increase_bucket_values() -> void:
	bucket_value_multiplier += 1
	build_board()

func decrease_drop_delay() -> void:
	drop_delay *= drop_delay_reduction_factor

func increase_queue_capacity() -> void:
	coin_queue.set_capacity(coin_queue._capacity + 1)
