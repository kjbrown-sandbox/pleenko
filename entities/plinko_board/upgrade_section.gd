extends CanvasLayer

const UpgradeRowScene := preload("res://entities/upgrade_row/upgrade_row.tscn")

@onready var upgrades_container: VBoxContainer = $Upgrades

var _board: PlinkoBoard
var _board_type: Enums.BoardType
var _rows: Dictionary = {}  # UpgradeType -> UpgradeRow node

func setup(board: PlinkoBoard, board_type: Enums.BoardType) -> void:
	_board = board
	_board_type = board_type

	# Spawn rows for any upgrades already unlocked
	for upgrade_type in Enums.UpgradeType.values():
		if UpgradeManager.is_unlocked(_board_type, upgrade_type):
			_spawn_row(upgrade_type)

	# Listen for future unlocks
	UpgradeManager.upgrade_unlocked.connect(_on_upgrade_unlocked)


func _on_upgrade_unlocked(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType) -> void:
	if board_type != _board_type:
		return
	if upgrade_type in _rows:
		return
	_spawn_row(upgrade_type)


func _spawn_row(upgrade_type: Enums.UpgradeType) -> void:
	var row = UpgradeRowScene.instantiate()
	row.setup(_board_type, upgrade_type, _buy_upgrade.bind(upgrade_type))
	upgrades_container.add_child(row)
	_rows[upgrade_type] = row


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
		Enums.UpgradeType.QUEUE:
			_board.increase_queue_capacity()
