extends CanvasLayer

const UpgradeRowScene := preload("res://entities/upgrade_row/upgrade_row.tscn")

@onready var upgrades_container: VBoxContainer = $MarginContainer/OuterVBox/Upgrades
@onready var hover_info_label: Label = $MarginContainer/OuterVBox/HoverInfo

var _board: PlinkoBoard
var _board_type: Enums.BoardType
var _rows: Dictionary = {}  # UpgradeType -> UpgradeRow node

func setup(board: PlinkoBoard, board_type: Enums.BoardType) -> void:
	_board = board
	_board_type = board_type

	# Style the hover info label
	var t: VisualTheme = ThemeProvider.theme
	hover_info_label.add_theme_font_size_override("font_size", int(t.button_font_size))
	hover_info_label.add_theme_color_override("font_color", t._resolve(VisualTheme.Palette.BG_5))
	var font: Font = t.button_font if t.button_font else t.label_font
	if font:
		hover_info_label.add_theme_font_override("font", font)

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
	row.hover_info_changed.connect(_on_hover_info_changed)
	upgrades_container.add_child(row)
	_rows[upgrade_type] = row


func _on_hover_info_changed(text: String) -> void:
	if text.is_empty():
		hover_info_label.visible = false
	else:
		hover_info_label.text = text
		hover_info_label.visible = true


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
		Enums.UpgradeType.AUTODROPPER:
			pass  # Pool size is just the upgrade level; BoardManager reads it directly
