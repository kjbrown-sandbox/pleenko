extends CanvasLayer

const UpgradeRowScene := preload("res://entities/upgrade_row/upgrade_row.tscn")

@onready var upgrades_container: VBoxContainer = $Upgrades

var _board: PlinkoBoard
var _board_type: Enums.BoardType

func setup(board: PlinkoBoard, board_type: Enums.BoardType) -> void:
	_board = board
	_board_type = board_type
	_build_upgrades()

func _build_upgrades() -> void:
	for upgrade_type in UpgradeManager.UpgradeType.values():
		var upgrade_id: String = UpgradeManager.UPGRADE_IDS[upgrade_type]
		var row = UpgradeRowScene.instantiate()
		row.setup(_board_type, upgrade_id, _buy_upgrade.bind(upgrade_id))
		upgrades_container.add_child(row)

func _buy_upgrade(upgrade_id: String) -> void:
	if not UpgradeManager.buy(_board_type, upgrade_id):
		return

	match upgrade_id:
		"add_row":
			_board.add_two_rows()
		"bucket_value":
			_board.increase_bucket_values()
