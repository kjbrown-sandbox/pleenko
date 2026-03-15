extends Node3D

@onready var board_manager: BoardManager = $BoardManager
@onready var camera: Camera3D = $Camera3D
@onready var coin_values = $CanvasLayer/CoinValues


func _ready() -> void:
	board_manager.setup(camera)
	coin_values.setup(board_manager)