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

	# Listen for future unlocks and cap raise availability
	UpgradeManager.upgrade_unlocked.connect(_on_upgrade_unlocked)
	UpgradeManager.cap_raise_unlocked.connect(_on_cap_raise_unlocked)


func _on_upgrade_unlocked(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType) -> void:
	if board_type != _board_type:
		return
	if upgrade_type in _rows:
		return
	_spawn_row(upgrade_type)


func _on_cap_raise_unlocked(board_type: Enums.BoardType) -> void:
	if board_type != _board_type:
		return
	for upgrade_type in _rows:
		_setup_cap_raise_if_needed(_rows[upgrade_type], upgrade_type)


func _spawn_row(upgrade_type: Enums.UpgradeType) -> void:
	var row = UpgradeRowScene.instantiate()
	row.setup(_board_type, upgrade_type, _buy_upgrade.bind(upgrade_type))
	row.hover_info_changed.connect(_on_hover_info_changed)
	upgrades_container.add_child(row)
	_rows[upgrade_type] = row
	_setup_cap_raise_if_needed(row, upgrade_type)


func _setup_cap_raise_if_needed(row, upgrade_type: Enums.UpgradeType) -> void:
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, upgrade_type)
	if state.base_cap <= 0 or not UpgradeManager.is_cap_raise_available(_board_type):
		return
	if row.fill_bar.plus_button.visible:
		return  # Already set up

	var bt := _board_type
	var ut := upgrade_type
	var r = row

	row.setup_plus(
		func(): # on_pressed
			UpgradeManager.buy_cap_raise(bt, ut),
		func() -> String: # on_hover
			var s: UpgradeManager.UpgradeState = UpgradeManager.get_state(bt, ut)
			var cap_cost := UpgradeManager.get_cap_raise_cost(bt, ut)
			var cap_currency: int = Enums.cap_raise_currency_for_board(bt)
			var currency_name := Enums.currency_name(cap_currency, false)
			return "Cost: %d %s  |  Cap %d → %d" % [cap_cost, currency_name, s.current_cap, s.current_cap + 1],
		func(): # on_update
			var can_raise := UpgradeManager.can_buy_cap_raise(bt, ut)
			r.fill_bar.set_plus_disabled(not can_raise)
			r.fill_bar.set_plus_filled(can_raise),
	)


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
