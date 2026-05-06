class_name AutodropperSummary
extends Label

## Single-line summary of autodropper assignments shown below the currency bars.
## Format: "Autodroppers: 2 gold · 1 orange"


func setup(board_manager: BoardManager) -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var t: VisualTheme = ThemeProvider.theme
	add_theme_font_size_override("font_size", t.button_font_size)
	add_theme_color_override("font_color", t.button_bg_color)
	var btn_font: Font = t.button_font if t.button_font else preload("res://style_lab/VendSans-Bold.ttf")
	add_theme_font_override("font", btn_font)
	board_manager.assignments_changed.connect(_refresh)


func _refresh(assignments: Dictionary) -> void:
	var per_board: Dictionary = {}  # BoardType -> int
	for bid in assignments:
		var count: int = assignments[bid]
		if count <= 0:
			continue
		var board_type := _board_type_from_button_id(bid)
		per_board[board_type] = per_board.get(board_type, 0) + count

	if per_board.is_empty():
		visible = false
		return

	visible = true
	var parts: PackedStringArray = []
	var board_types: Array = per_board.keys()
	board_types.sort()
	for board_type in board_types:
		var currency: Enums.CurrencyType = TierRegistry.primary_currency(board_type)
		var name: String = FormatUtils.currency_name(currency, false).to_lower()
		parts.append("%d %s" % [per_board[board_type], name])
	text = "Autodroppers: %s" % " · ".join(parts)


func _board_type_from_button_id(bid: StringName) -> Enums.BoardType:
	var s: String = (bid as String).replace("_NORMAL", "").replace("_ADVANCED", "")
	return Enums.BoardType[s]
