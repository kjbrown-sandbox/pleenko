class_name PlinkoBoard
extends Node3D

@export var num_rows: int = 2
@export var space_between_pegs: float = 1.0
@export var vertical_spacing: float

const PegScene := preload("res://entities/peg/peg.tscn")
const BucketScene: PackedScene = preload("res://entities/bucket/bucket.tscn")
const CoinScene := preload("res://entities/coin/coin.tscn")

@onready var pegs_container: Node3D = $Pegs
@onready var buckets_container: Node3D = $Buckets
@onready var upgrade_section = $UpgradeSection

var board_type = Enums.BoardType

var is_waiting = false
var has_funds = true
var bucket_value_multiplier: int = 1

# func _ready() -> void:


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("drop_coin"):
		drop_coin()

	# REMOVE ME ONCE UPGRADES ARE HOOKED UP
	if event is InputEventKey and event.pressed and event.keycode == KEY_U:          
		var success = UpgradeManager.buy(Enums.BoardType.GOLD, "drop_rate")                                                          
		print("Drop rate upgrade: ", "success" if success else "failed")   

func setup(type: Enums.BoardType) -> void:
	board_type = type
	upgrade_section.setup(self, type)
	build_board()


func drop_coin() -> void:
	if is_waiting:
		return

	if not CurrencyManager.spend(Enums.currency_for_board(board_type), 1):
		return

	var coin = CoinScene.instantiate()
	coin.board = self
	coin.position = Vector3(0, vertical_spacing + 0.2, 0) # 0.2 is coin + peg radius
	add_child(coin)
	coin.start(Vector3(0, 0.2, 0))
	is_waiting = true
	get_tree().create_timer(1.0).timeout.connect(func(): is_waiting = false)

func on_coin_landed(coin: Coin) -> void:
	var bucket = get_nearest_bucket(coin.global_position.x)
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, bucket.value)
	coin.queue_free()

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
		var distance_from_center = (abs(i - floor(num_buckets / 2))) * bucket_value_multiplier
		bucket.position = Vector3((i * space_between_pegs), 0, 0)
		bucket.value = distance_from_center + 1
		buckets_container.add_child(bucket)

func add_two_rows() -> void:
	num_rows += 2
	build_board()

func increase_bucket_values() -> void:
	bucket_value_multiplier += 1
	build_board()

# func _on_currency_changed(_type: Enums.CurrencyType, new_balance: int, _new_cap: int) -> void:
# 	if _type == Enums.currency_for_board(board_type):
# 		has_funds = new_balance >= 1
