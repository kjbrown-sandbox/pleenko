extends Node3D

@onready var ui: CanvasLayer = $UI

var coin_scene: PackedScene = preload("res://scenes/coin.tscn")
var coin_total: int = 0

const SPAWN_POS := Vector3(0.0, 3.0, 0.0)
const BUCKET_LEFT_X := -1.0
const BUCKET_RIGHT_X := 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("drop_coin"):
		_drop_coin()


func _drop_coin() -> void:
	var coin: Node3D = coin_scene.instantiate()
	coin.position = SPAWN_POS
	add_child(coin)

	var go_left := randf() < 0.5
	var target_x := BUCKET_LEFT_X if go_left else BUCKET_RIGHT_X

	coin.landed.connect(_on_coin_landed)
	coin.animate(target_x, 1)


func _on_coin_landed(bucket_value: int) -> void:
	coin_total += bucket_value
	ui.update_coins(coin_total)
