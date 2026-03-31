class_name CoinQueue
extends Node3D

## Where the first coin in the queue sits (local to this node).
@export var start_position: Vector3 = Vector3(-1, sqrt(3)/2 + 0.2, 0)
## Spacing between coins along the X axis.
@export var coin_spacing: float = 0.20 
## How long it takes a coin to tween to its new slot.
@export var slide_time: float = 0.15
## Tilt coins so their face is visible.
@export var coin_rotation: Vector3 = Vector3(0, 0, 0)

var _capacity: int = 0
var _coins: Array[Coin] = []

## Returns the number of coins currently in the queue.
var count: int:
	get: return _coins.size()

func setup(_start_position: Vector3) -> void:
	start_position = _start_position


func set_capacity(new_capacity: int) -> void:
	_capacity = new_capacity


func is_full() -> bool:
	return _coins.size() >= _capacity


func is_empty() -> bool:
	return _coins.is_empty()


func has_queue() -> bool:
	return _capacity > 0


func enqueue(coin: Coin) -> void:
	if is_full():
		return

	var slot_index := _coins.size()
	coin.position = _slot_position(slot_index)
	coin.rotation = coin_rotation
	add_child(coin)
	_coins.append(coin)


func dequeue() -> Coin:
	if is_empty():
		return null

	var coin: Coin = _coins.pop_front()
	remove_child(coin)
	_slide_coins_forward()
	return coin


func _slot_position(index: int) -> Vector3:
	return start_position + Vector3(-index * coin_spacing, 0, 0)


func _slide_coins_forward() -> void:
	for i in _coins.size():
		var coin: Coin = _coins[i]
		var target := _slot_position(i)
		var tween: Tween = create_tween()
		tween.tween_interval(i * 0.1)
		tween.tween_property(coin, "position", target, slide_time) \
			.set_trans(Tween.TRANS_LINEAR)
