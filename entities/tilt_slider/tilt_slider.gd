class_name TiltSlider
extends Control

## The per-board tilt control: a five-notch slider under the buckets running
## from "Centre" to "Edges", with the untilted default in the middle.
##
## Pure view + input. Emits `notch_changed` UP; everything else is called DOWN by
## PlinkoBoard (`setup`, `refresh`). It never reads UpgradeManager or writes
## board state itself — the board owns the notch, and the slider only proposes.
##
## Its own node rather than part of DropSection: the drop buttons are always
## present, while this appears only once the upgrade is owned.
##
## Positioned by an anchor override on the instance in plinko_board.tscn, like
## DropSection — a fixed screen slot below the drop buttons, NOT tracked to the
## bucket row. Tracking the board would need per-frame unproject_position (see
## PlinkoBoard._update_drop_rate_label_position); a fixed slot is what the drop
## buttons already do, and the slider reads as part of that cluster.

signal notch_changed(notch: int)

@onready var _slider: HSlider = $VBox/Slider
@onready var _left_label: Label = $VBox/Labels/LeftLabel
@onready var _right_label: Label = $VBox/Labels/RightLabel
@onready var _odds_label: Label = $VBox/OddsLabel

var _board: PlinkoBoard


func setup(board: PlinkoBoard) -> void:
	_board = board
	_slider.min_value = BoardTilt.NOTCH_CENTER
	_slider.max_value = BoardTilt.NOTCH_EDGES
	_slider.step = 1
	_slider.value = board.get_tilt_notch()
	_slider.value_changed.connect(_on_slider_changed)
	_apply_theme()
	ThemeProvider.theme_changed.connect(_apply_theme)
	refresh()


## Re-reads the board. Called DOWN after a load, or after the upgrade level
## changes (which moves the odds without moving the slider).
func refresh() -> void:
	if not is_instance_valid(_board):
		return
	# Assign without re-emitting: value_changed would fire notch_changed back at
	# the board that just told us its value, and a float/int round-trip through
	# HSlider could land one notch off.
	_slider.set_value_no_signal(_board.get_tilt_notch())
	_update_odds()


func _on_slider_changed(value: float) -> void:
	notch_changed.emit(BoardTilt.clamp_notch(roundi(value)))
	_update_odds()


func _update_odds() -> void:
	if not is_instance_valid(_board):
		return
	var notch: int = _board.get_tilt_notch()
	if notch == BoardTilt.NOTCH_DEFAULT:
		# An untilted board is a fair coin; "50%" invites the reader to wonder
		# which side it favours, when the answer is neither.
		_odds_label.text = "No tilt"
	else:
		_odds_label.text = "%d%% toward %s" % [
			_board.tilt_odds_percent(),
			"centre" if notch < BoardTilt.NOTCH_DEFAULT else "edges",
		]


func _apply_theme() -> void:
	var t: VisualTheme = ThemeProvider.theme
	for label: Label in [_left_label, _right_label, _odds_label]:
		label.add_theme_color_override("font_color", t.normal_text_color)
	# The grabber and track would otherwise render in stock Godot grey next to
	# fully-themed buttons. Palette-sourced so theme swaps propagate.
	_slider.modulate = t.normal_text_color
	_left_label.text = BoardTilt.notch_label(BoardTilt.NOTCH_CENTER)
	_right_label.text = BoardTilt.notch_label(BoardTilt.NOTCH_EDGES)
