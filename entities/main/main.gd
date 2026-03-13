extends Node3D

const UpgradeRowScene := preload("res://entities/upgrade_row/upgrade_row.tscn")

@onready var plinko_board: Node3D = $PlinkoBoard
@onready var upgrades_container: Node = $UpgradeSection/Upgrades


func _ready() -> void:
	plinko_board.setup(Enums.BoardType.GOLD)
	build_upgrades()

func build_upgrades() -> void:
	var row = UpgradeRowScene.instantiate()
	row.setup("Add rows", func(): plinko_board.add_two_rows())
	upgrades_container.add_child(row)

