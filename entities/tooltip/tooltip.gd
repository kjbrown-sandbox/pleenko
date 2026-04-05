class_name Tooltip
extends Control

enum Placement { TOP, RIGHT, BOTTOM, LEFT, INLINE }

## Static text to display. Leave empty for dynamic text via update_and_show().
@export var text: String = ""
## Which side of the anchor to position the tooltip on.
## INLINE means the tooltip sits in its parent's layout and just toggles visibility.
@export var position_side: Placement = Placement.TOP
## Gap in pixels between the anchor edge and the tooltip.
@export var offset: float = 8.0
## If true, auto-connects to parent's mouse_entered/mouse_exited signals.
@export var use_parent_signals: bool = true
## Node to position relative to. Empty = parent.
@export var anchor_node_path: NodePath = NodePath("")
## Horizontal text alignment for the label.
@export var horizontal_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT

@onready var _label: Label = $Label


func _ready() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE

	# Prevent inheriting parent rotation/scale (e.g. rotated nav arrows)
	if position_side != Placement.INLINE:
		top_level = true
	else:
		# In INLINE mode, expand to fill parent container so text alignment works.
		# The Label must stretch to the Tooltip's width, and the Tooltip must
		# stretch to its parent container's width.
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_apply_theme()

	if not text.is_empty():
		_label.text = text

	_label.horizontal_alignment = horizontal_alignment
	_label.mouse_filter = MOUSE_FILTER_IGNORE

	if use_parent_signals:
		_connect_to_parent.call_deferred()


func _apply_theme() -> void:
	var t: VisualTheme = ThemeProvider.theme
	_label.add_theme_font_size_override("font_size", int(t.button_font_size))
	_label.add_theme_color_override("font_color", t.body_text_color)
	_label.add_theme_constant_override("line_spacing", -int(t.button_font_size) / 3)
	var font: Font = t.button_font if t.button_font else t.label_font
	if font:
		_label.add_theme_font_override("font", font)


func _connect_to_parent() -> void:
	var parent := get_parent()
	if parent is Control:
		parent.mouse_entered.connect(show_tooltip)
		parent.mouse_exited.connect(hide_tooltip)


func show_tooltip() -> void:
	visible = true
	_label.size = Vector2.ZERO
	if position_side != Placement.INLINE:
		_position_tooltip.call_deferred()


func hide_tooltip() -> void:
	visible = false


func set_text(new_text: String) -> void:
	_label.text = new_text


func update_and_show(new_text: String) -> void:
	_label.text = new_text
	show_tooltip()


func show_or_hide(new_text: String) -> void:
	if new_text.is_empty():
		hide_tooltip()
	else:
		update_and_show(new_text)


func _get_anchor() -> Control:
	if not anchor_node_path.is_empty():
		var node := get_node_or_null(anchor_node_path)
		if node is Control:
			return node
	var parent := get_parent()
	if parent is Control:
		return parent
	return null


func _position_tooltip() -> void:
	var anchor := _get_anchor()
	if not anchor:
		return

	var anchor_pos: Vector2 = anchor.global_position
	var anchor_size: Vector2 = anchor.size
	var tooltip_size: Vector2 = _label.size

	match position_side:
		Placement.TOP:
			global_position = Vector2(
				anchor_pos.x + (anchor_size.x - tooltip_size.x) / 2.0,
				anchor_pos.y - tooltip_size.y - offset
			)
		Placement.BOTTOM:
			global_position = Vector2(
				anchor_pos.x + (anchor_size.x - tooltip_size.x) / 2.0,
				anchor_pos.y + anchor_size.y + offset
			)
		Placement.LEFT:
			global_position = Vector2(
				anchor_pos.x - tooltip_size.x - offset,
				anchor_pos.y + (anchor_size.y - tooltip_size.y) / 2.0
			)
		Placement.RIGHT:
			global_position = Vector2(
				anchor_pos.x + anchor_size.x + offset,
				anchor_pos.y + (anchor_size.y - tooltip_size.y) / 2.0
			)
