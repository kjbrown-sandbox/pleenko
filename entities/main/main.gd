extends Node3D

@onready var plinko_board: Node3D = $PlinkoBoard


func _ready() -> void:
	plinko_board.setup(Enums.BoardType.GOLD)
