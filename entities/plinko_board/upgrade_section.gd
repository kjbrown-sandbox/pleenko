class_name UpgradeSection
extends CanvasLayer

const UpgradeRowScene := preload("res://entities/upgrade_row/upgrade_row.tscn")

@onready var upgrades_container: VBoxContainer = $MarginContainer/OuterVBox/Upgrades
@onready var _outer_vbox: VBoxContainer = $MarginContainer/OuterVBox
@onready var _hover_tooltip: Tooltip = $MarginContainer/OuterVBox/HoverInfo

var _board: PlinkoBoard
var _board_type: Enums.BoardType
var _rows: Dictionary = {}  # UpgradeType -> UpgradeRow node
var _initial_setup_complete := false
var _section_label: Label

# Cap-raise reveal cinematic (CapRaiseRevealAnimator): while active, this board's
# cap "+" buttons are wired but kept hidden so the animator can reveal them one
# at a time. See begin/get_pending/end_cap_raise_reveal.
var _cap_raise_reveal_active := false

func setup(board: PlinkoBoard, board_type: Enums.BoardType) -> void:
	_board = board
	_board_type = board_type

	# Spawn rows for any upgrades already unlocked
	# (Autodropper types live in the HUD, not here)
	for upgrade_type in Enums.UpgradeType.values():
		if _is_universal_upgrade(upgrade_type):
			continue
		if UpgradeManager.is_unlocked(_board_type, upgrade_type):
			_spawn_row(upgrade_type)

	# Show section title immediately if any rows were restored from save
	if not _rows.is_empty():
		_add_section_label()

	# Listen for future unlocks and cap raise availability
	UpgradeManager.upgrade_unlocked.connect(_on_upgrade_unlocked)
	UpgradeManager.cap_raise_unlocked.connect(_on_cap_raise_unlocked)
	# Defer so save loading (which also runs during init) finishes first.
	# Upgrades restored from save should not get the materialize animation.
	_mark_setup_complete.call_deferred()


func _mark_setup_complete() -> void:
	_initial_setup_complete = true


func _on_upgrade_unlocked(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType) -> void:
	if _is_universal_upgrade(upgrade_type):
		return
	if board_type != _board_type:
		return
	if upgrade_type in _rows:
		return
	_spawn_row(upgrade_type)
	if _initial_setup_complete:
		if _section_label:
			# Title already shown — just materialize the row
			_rows[upgrade_type].materialize()
		else:
			# First upgrade during gameplay — hide the row, typewriter the title,
			# then materialize the row once the title is fully typed
			var row: UpgradeRow = _rows[upgrade_type]
			row.visible = false
			_animate_section_title(row)
	elif not _section_label:
		_add_section_label()


func _on_cap_raise_unlocked(board_type: Enums.BoardType) -> void:
	if board_type != _board_type:
		return
	for upgrade_type in _rows:
		_setup_cap_raise_if_needed(_rows[upgrade_type], upgrade_type)


## The UpgradeRow for a type, or null if it hasn't been unlocked/spawned yet.
func get_upgrade_row(upgrade_type: Enums.UpgradeType) -> UpgradeRow:
	return _rows.get(upgrade_type)


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
	if row.bar.plus_button.visible:
		return  # Already set up

	var bt := _board_type
	var ut := upgrade_type
	var r = row

	row.setup_plus(
		func(): # on_pressed
			UpgradeManager.buy_cap_raise(bt, ut),
		func() -> String: # on_hover
			var state2: UpgradeManager.UpgradeState = UpgradeManager.get_state(bt, ut)
			var cap_cost: int = UpgradeManager.get_cap_raise_cost(bt, ut)
			var cap_currency: int = TierRegistry.cap_raise_currency(bt)
			var currency_name: String = FormatUtils.currency_name(cap_currency, false)
			return "Increase max level %d → %d\n\nCost: %d %s" % [
				state2.current_cap, state2.current_cap + 1, cap_cost, currency_name],
		func(): # on_update
			var can_raise: bool = UpgradeManager.can_buy_cap_raise(bt, ut)
			r.bar.set_plus_disabled(not can_raise)
			r.bar.set_plus_filled(can_raise),
	)

	if _cap_raise_reveal_active:
		# Wired but hidden — CapRaiseRevealAnimator reveals it on its own clock.
		row.bar.show_plus_button(false)


# ── Cap-raise reveal handshake (called down by CapRaiseRevealAnimator) ───────
# While a reveal is active, this board's cap "+" buttons are wired but kept
# hidden (_setup_cap_raise_if_needed self-suppresses). The animator pulls them
# via get_pending_cap_raise_targets() and reveals them one at a time;
# end_cap_raise_reveal() force-shows whatever is left if the cinematic is cut short.

func begin_cap_raise_reveal() -> void:
	_cap_raise_reveal_active = true


## This board's cap "+" buttons that are wired but still hidden, in row order
## (top-to-bottom). Each entry:
## { node: Control (for explosion position), plus_button: Control, reveal: Callable }.
func get_pending_cap_raise_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if not _cap_raise_reveal_active or not UpgradeManager.is_cap_raise_available(_board_type):
		return targets
	for upgrade_type in _rows:
		var row: UpgradeRow = _rows[upgrade_type]
		if row.bar.plus_button.visible:
			continue
		var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_board_type, upgrade_type)
		if state.base_cap <= 0:
			continue
		var captured_row := row
		targets.append({
			"node": row,
			"plus_button": row.bar.plus_button,
			"reveal": func() -> void: _reveal_row_cap_button(captured_row),
		})
	return targets


func end_cap_raise_reveal() -> void:
	_cap_raise_reveal_active = false
	# Re-run the normal reveal — now unsuppressed it force-shows every cap button.
	_on_cap_raise_unlocked(_board_type)


func _reveal_row_cap_button(row: UpgradeRow) -> void:
	if not is_instance_valid(row):
		return
	row.bar.show_plus_button(true)
	row.bar.update_plus()


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
		Enums.UpgradeType.AUTODROPPER, Enums.UpgradeType.ADVANCED_AUTODROPPER, \
		Enums.UpgradeType.PEG_DEFLECTOR:
			pass  # Universal upgrades — bought via CoinValues, not here


func _is_universal_upgrade(upgrade_type: Enums.UpgradeType) -> bool:
	# Per-board "unique" upgrades are all universal — they render in the
	# CoinValues HUD (left), not in this per-board section.
	return upgrade_type == Enums.UpgradeType.AUTODROPPER \
		or upgrade_type == Enums.UpgradeType.ADVANCED_AUTODROPPER \
		or upgrade_type == Enums.UpgradeType.PEG_DEFLECTOR


func _get_section_title() -> String:
	var tier: TierData = TierRegistry.get_tier(_board_type)
	return "%s board upgrades" % tier.display_name


func _add_section_label(initial_text: String = "") -> void:
	var t: VisualTheme = ThemeProvider.theme
	var bold_font: Font = preload("res://style_lab/VendSans-Bold.ttf")
	var btn_font: Font = t.button_font if t.button_font else bold_font
	_section_label = Label.new()
	_section_label.text = initial_text if initial_text != "" else _get_section_title()
	_section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_section_label.add_theme_font_size_override("font_size", t.button_font_size)
	_section_label.add_theme_color_override("font_color", t.normal_text_color)
	_section_label.add_theme_font_override("font", btn_font)
	upgrades_container.add_child(_section_label)
	upgrades_container.move_child(_section_label, 0)


func _animate_section_title(row: UpgradeRow) -> void:
	_add_section_label("")

	var full_text := _get_section_title()
	var char_delay: float = ThemeProvider.theme.typewriter_char_delay
	var tween := create_tween()
	for i in full_text.length():
		tween.tween_callback(func(): _section_label.text = full_text.substr(0, i + 1))
		tween.tween_interval(char_delay)
	tween.tween_callback(row.materialize)
