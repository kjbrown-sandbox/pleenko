class_name MainMenuButton
extends Control

## Standalone main-menu button. Owns its own hover-expand (grows
## custom_minimum_size.y so the VBoxContainer parent re-flows neighbors
## up/down — the "Dock magnification" feel) and a public `pluck()` API
## the main menu drives in beat with the MenuBoard chord bed.
##
## Pluck and hover-stretch both extend the button leftward (right edge stays
## anchored to the column). They use additive offsets composed into a single
## `Button.offset_left` so they can run concurrently without fighting.
##
## Signals UP, calls DOWN: emits semantic signals only; never reads
## MenuBoard / AudioManager / theme audio state. MainMenu wires beat
## ticks → pluck() and hover_started → arpeggio audio.

signal pressed
signal hover_started
signal hover_ended

@export var title_text: String = "Button":
	set(value):
		if title_text == value: return
		title_text = value
		if is_inside_tree(): _text_label.text = title_text

@export var baseline_height: float = 64.0:
	set(value):
		baseline_height = value
		if is_inside_tree() and not _hovered:
			custom_minimum_size.y = baseline_height

@export var expanded_height: float = 78.0
# Two-phase stretch: a fast snap to `hover_x_growth`, then a long slow
# creep to `hover_x_growth_max` (1.5x by default) so a steady hover keeps
# expanding subtly even after the initial bulge has settled.
@export var hover_x_growth: float = 80.0
@export var hover_x_growth_max: float = 120.0
@export var pluck_offset_x: float = 8.0
@export var pluck_pull_duration: float = 0.15
@export var pluck_return_duration: float = 1.0
@export var hover_expand_duration: float = 0.18
@export var hover_collapse_duration: float = 0.22
@export var hover_stretch_duration: float = 0.7
@export var hover_stretch_extended_duration: float = 4.0
@export var hover_stretch_collapse_duration: float = 0.25
# Text drifts left while hovered. Linear so the motion reads as a slow,
# steady creep, independent of the EXPO_OUT stretch curve.
@export var text_drift_x: float = 60.0
@export var text_drift_collapse_duration: float = 0.25

const FONT_SIZE := 28
# Default right margin of the text from the column edge (matches the Button
# stylebox's content_margin_right). Text drift adds to this leftward.
const TEXT_BASELINE_OFFSET_RIGHT := -28.0

@onready var _button: Button = $Button
@onready var _text_label: Label = $TextLabel

var _pluck_tween: Tween
var _size_tween: Tween
var _stretch_tween: Tween
var _text_tween: Tween
var _hovered: bool = false

# Pluck and stretch contributions to Button.offset_left. Tweens mutate these
# components via tween_method; _apply_button_offset_left() composes them.
var _pluck_offset: float = 0.0
var _stretch_offset: float = 0.0


func _ready() -> void:
	custom_minimum_size.y = baseline_height
	_button.focus_mode = Control.FOCUS_NONE
	_text_label.text = title_text
	_apply_theme()
	_button.pressed.connect(pressed.emit)
	_button.mouse_entered.connect(_on_mouse_entered)
	_button.mouse_exited.connect(_on_mouse_exited)


func _exit_tree() -> void:
	# MainMenu can be freed mid-fade by SceneManager — kill tweens so deferred
	# callbacks don't fire against freeing nodes.
	for t in [_pluck_tween, _size_tween, _stretch_tween, _text_tween]:
		if t and t.is_valid():
			t.kill()


# Custom styling instead of theme.apply_button_theme — the menu button is
# intentionally bolder than the shared button look (thicker border, wider
# horizontal padding, hover/pressed shade variants). A schema change to
# VisualTheme button defaults won't propagate here; that's by design.
func _apply_theme() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var bar := t.button_border_color
	var text_col := t.bg_shade_6
	var hover_bar := bar.lightened(0.12)
	var pressed_bar := bar.darkened(0.10)
	_button.add_theme_stylebox_override("normal", _make_style(bar))
	_button.add_theme_stylebox_override("hover", _make_style(hover_bar))
	_button.add_theme_stylebox_override("pressed", _make_style(pressed_bar))
	_button.add_theme_stylebox_override("focus", _make_style(bar))
	_text_label.add_theme_color_override("font_color", text_col)
	_text_label.add_theme_font_size_override("font_size", FONT_SIZE)


func _make_style(bg: Color) -> StyleBoxFlat:
	var t: VisualTheme = ThemeProvider.theme
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = t.button_border_color
	s.set_border_width_all(4)
	s.set_corner_radius_all(t.button_border_radius)
	s.set_content_margin_all(12.0)
	return s


## Called DOWN by MainMenu on each chord-bed beat tick. Two-segment tween:
## a fast extension leftward, then a slow return. Additively combines with
## the hover-stretch via `_apply_button_offset_left`. The button's right edge
## stays anchored (offset_right unchanged), so it only ever grows.
func pluck() -> void:
	if _pluck_tween and _pluck_tween.is_valid():
		_pluck_tween.kill()
	_pluck_offset = 0.0
	_apply_button_offset_left()
	_pluck_tween = create_tween()
	_pluck_tween.tween_method(_set_pluck_offset, 0.0, -pluck_offset_x, pluck_pull_duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_pluck_tween.tween_method(_set_pluck_offset, -pluck_offset_x, 0.0, pluck_return_duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


func _on_mouse_entered() -> void:
	_hovered = true
	_tween_height_to(expanded_height, hover_expand_duration, Tween.EASE_OUT)
	_start_grow_stretch()
	_start_text_drift()
	hover_started.emit()


func _on_mouse_exited() -> void:
	_hovered = false
	_tween_height_to(baseline_height, hover_collapse_duration, Tween.EASE_IN)
	_start_collapse_stretch()
	_start_text_drift_return()
	hover_ended.emit()


func _tween_height_to(target: float, duration: float, ease: Tween.EaseType) -> void:
	if _size_tween and _size_tween.is_valid():
		_size_tween.kill()
	_size_tween = create_tween()
	_size_tween.tween_property(self, "custom_minimum_size:y", target, duration) \
		.set_ease(ease).set_trans(Tween.TRANS_QUAD)


# Left-only horizontal bulge with a single EXPO_OUT curve over the full
# duration — the curve's natural shape gives fast initial growth and a long
# slow tail. A chained two-phase tween produced a visible pause at the seam
# (EXPO_OUT ends near zero velocity, second tween picks up speed again).
# Right edge stays anchored so all five buttons remain flush right.
func _start_grow_stretch() -> void:
	if _stretch_tween and _stretch_tween.is_valid():
		_stretch_tween.kill()
	var total_duration: float = hover_stretch_duration + hover_stretch_extended_duration
	_stretch_tween = create_tween()
	_stretch_tween.tween_method(_set_stretch_offset, _stretch_offset, -hover_x_growth_max, total_duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)


func _start_collapse_stretch() -> void:
	if _stretch_tween and _stretch_tween.is_valid():
		_stretch_tween.kill()
	_stretch_tween = create_tween()
	_stretch_tween.tween_method(_set_stretch_offset, _stretch_offset, 0.0, hover_stretch_collapse_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


# Linear text drift: text travels leftward at a constant rate over the full
# hover-stretch duration, finishing at TEXT_BASELINE_OFFSET_RIGHT - text_drift_x.
func _start_text_drift() -> void:
	if _text_tween and _text_tween.is_valid():
		_text_tween.kill()
	var total_duration: float = hover_stretch_duration + hover_stretch_extended_duration
	_text_tween = create_tween()
	_text_tween.tween_property(_text_label, "offset_right",
		TEXT_BASELINE_OFFSET_RIGHT - text_drift_x, total_duration) \
		.set_trans(Tween.TRANS_LINEAR)


func _start_text_drift_return() -> void:
	if _text_tween and _text_tween.is_valid():
		_text_tween.kill()
	_text_tween = create_tween()
	_text_tween.tween_property(_text_label, "offset_right",
		TEXT_BASELINE_OFFSET_RIGHT, text_drift_collapse_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _set_pluck_offset(v: float) -> void:
	_pluck_offset = v
	_apply_button_offset_left()


func _set_stretch_offset(v: float) -> void:
	_stretch_offset = v
	_apply_button_offset_left()


func _apply_button_offset_left() -> void:
	_button.offset_left = _pluck_offset + _stretch_offset
