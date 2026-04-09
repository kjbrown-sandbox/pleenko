class_name UpgradeSection
extends CanvasLayer

const UpgradeRowScene := preload("res://entities/upgrade_row/upgrade_row.tscn")

@onready var upgrades_container: VBoxContainer = $MarginContainer/OuterVBox/Upgrades
@onready var _hover_tooltip: Tooltip = $MarginContainer/OuterVBox/HoverInfo

var _board: PlinkoBoard
var _board_type: Enums.BoardType
var _rows: Dictionary = {}  # UpgradeType -> UpgradeRow node
var _initial_setup_complete := false

func setup(board: PlinkoBoard, board_type: Enums.BoardType) -> void:
	_board = board
	_board_type = board_type

	# Spawn rows for any upgrades already unlocked
	for upgrade_type in Enums.UpgradeType.values():
		if UpgradeManager.is_unlocked(_board_type, upgrade_type):
			_spawn_row(upgrade_type)

	# Listen for future unlocks and cap raise availability
	UpgradeManager.upgrade_unlocked.connect(_on_upgrade_unlocked)
	UpgradeManager.cap_raise_unlocked.connect(_on_cap_raise_unlocked)
	# Defer so save loading (which also runs during init) finishes first.
	# Upgrades restored from save should not get the materialize animation.
	_mark_setup_complete.call_deferred()


func _mark_setup_complete() -> void:
	_initial_setup_complete = true


func _on_upgrade_unlocked(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType) -> void:
	if board_type != _board_type:
		return
	if upgrade_type in _rows:
		return
	_spawn_row(upgrade_type)
	if _initial_setup_complete:
		_materialize_row(_rows[upgrade_type])


func _materialize_row(row: UpgradeRow) -> void:
	# Wrap the row in a clip container to animate a left-to-right reveal.
	# The VBoxContainer manages the wrapper's size; the wrapper clips the row.
	var wrapper := Control.new()
	wrapper.clip_contents = true
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Swap: remove row from VBox, insert wrapper, put row inside wrapper
	var idx: int = row.get_index()
	upgrades_container.remove_child(row)
	upgrades_container.add_child(wrapper)
	upgrades_container.move_child(wrapper, idx)
	wrapper.add_child(row)

	# Row fills wrapper naturally via layout. Start wrapper at zero height
	# so the VBox allocates space progressively (but we want horizontal clip).
	# Set a fixed height so VBox gives it the right slot, then clip horizontally
	# by offsetting the row and tweening it in.
	_animate_clip_reveal.call_deferred(wrapper, row)


func _animate_clip_reveal(wrapper: Control, row: UpgradeRow) -> void:
	var target_width: float = upgrades_container.size.x
	var row_height: float = row.size.y
	wrapper.custom_minimum_size = Vector2(0, row_height)

	# Position the row absolutely inside the wrapper
	row.position = Vector2.ZERO
	row.size = Vector2(target_width, row_height)

	# Start with wrapper clipping everything (0 width via offset)
	wrapper.size = Vector2(0, row_height)

	var t: VisualTheme = ThemeProvider.theme
	var tween := wrapper.create_tween()
	tween.tween_property(wrapper, "custom_minimum_size:x", target_width, t.upgrade_materialize_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		# Unwrap: move row back to VBox, remove wrapper
		var i: int = wrapper.get_index()
		wrapper.remove_child(row)
		upgrades_container.remove_child(wrapper)
		upgrades_container.add_child(row)
		upgrades_container.move_child(row, i)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrapper.queue_free()
		row.start_attention()
	)


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
			var cap_cost: int = UpgradeManager.get_cap_raise_cost(bt, ut)
			var cap_currency: int = TierRegistry.cap_raise_currency(bt)
			var currency_name: String = FormatUtils.currency_name(cap_currency, false)
			return "Cost: %d %s\nCap %d → %d" % [cap_cost, currency_name, s.current_cap, s.current_cap + 1],
		func(): # on_update
			var can_raise: bool = UpgradeManager.can_buy_cap_raise(bt, ut)
			r.fill_bar.set_plus_disabled(not can_raise)
			r.fill_bar.set_plus_filled(can_raise),
	)


func _on_hover_info_changed(text: String) -> void:
	_hover_tooltip.show_or_hide(text)


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
		Enums.UpgradeType.AUTODROPPER, Enums.UpgradeType.ADVANCED_AUTODROPPER:
			pass  # Pool size is just the upgrade level; BoardManager reads it directly
