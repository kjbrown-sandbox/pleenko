extends Node3D

const UpgradeRowScene := preload("res://entities/upgrade_row/upgrade_row.tscn")

@onready var plinko_board: Node3D = $PlinkoBoard
@onready var upgrades_container: Node = $UpgradeSection/Upgrades


func _ready() -> void:
	plinko_board.setup(Enums.BoardType.GOLD)
	build_upgrades()

func build_upgrades() -> void:
	for upgrade_type in UpgradeManager.UpgradeType.values():
		var upgrade_id: String = UpgradeManager.UPGRADE_IDS[upgrade_type]
		var row = UpgradeRowScene.instantiate()
		row.setup(Enums.BoardType.GOLD, upgrade_id, func(): _buy_upgrade(upgrade_id))
		upgrades_container.add_child(row)

func _buy_upgrade(upgrade_id: String) -> void:
	UpgradeManager.buy(Enums.BoardType.GOLD, upgrade_id)
	# Apply effects specific to this board
	if upgrade_id == "add_row":
		plinko_board.add_two_rows()

