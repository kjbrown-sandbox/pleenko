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
	# The VBoxContainer forces direct children to full width, so clip_contents
	# on a VBox child does nothing useful. Instead we use two layers:
	#   wrapper (in VBox, full width, holds height) → clip (manually sized) → row
	# The wrapper is a plain Control so it doesn't manage clip's size.
	var idx: int = row.get_index()
	upgrades_container.remove_child(row)

	var wrapper := Control.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrades_container.add_child(wrapper)
	upgrades_container.move_child(wrapper, idx)

	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(clip)

	clip.add_child(row)

	_animate_clip_reveal.call_deferred(wrapper, clip, row)


func _animate_clip_reveal(wrapper: Control, clip: Control, row: UpgradeRow) -> void:
	var target_width: float = upgrades_container.size.x
	var row_height: float = row.size.y

	# Wrapper reserves the right height in the VBox
	wrapper.custom_minimum_size.y = row_height

	# Row is full-size inside the clip, positioned at origin
	row.position = Vector2.ZERO
	row.size = Vector2(target_width, row_height)

	# Clip starts at 0 width — row is fully hidden
	clip.size = Vector2(0, row_height)

	var t: VisualTheme = ThemeProvider.theme
	var tween := clip.create_tween()
	tween.tween_property(clip, "size:x", target_width, t.upgrade_materialize_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		# Unwrap: move row back into VBox, remove wrapper
		var i: int = wrapper.get_index()
		clip.remove_child(row)
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
			var cap_cost: int = UpgradeManager.get_cap_raise_cost(bt, ut)
			var cap_currency: int = TierRegistry.cap_raise_currency(bt)
			var currency_name: String = FormatUtils.currency_name(cap_currency, false)
			return "Cost: %d %s" % [cap_cost, currency_name],
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
