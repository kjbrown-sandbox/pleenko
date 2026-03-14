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
	for upgrade_type in Enums.UpgradeType.values():
		var row = UpgradeRowScene.instantiate()
		row.setup(_board_type, upgrade_type, _buy_upgrade.bind(upgrade_type))
		upgrades_container.add_child(row)

func _buy_upgrade(upgrade_type: Enums.UpgradeType) -> void:
	if not UpgradeManager.buy(_board_type, upgrade_type):
		return

	match upgrade_type:
		Enums.UpgradeType.ADD_ROW:
			_board.add_two_rows()
		Enums.UpgradeType.BUCKET_VALUE:
			_board.increase_bucket_values()
		Enums.UpgradeType.DROP_RATE:
			_board.decrease_drop_delay()
