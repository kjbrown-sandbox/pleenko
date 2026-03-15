extends Node3D

@onready var board_manager: BoardManager = $BoardManager
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	board_manager.setup(camera)
	# board_manager.unlock_board(Enums.BoardType.ORANGE) # just here for testing that orange can be unlocked