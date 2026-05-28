class_name RefinedBaselineButton
extends HBoxContainer

## Static visual button matching button_prototypes.tscn V1 "01 — Refined
## baseline", with iteration-locked modifications:
##   - Dark interior is transparent; bar color drives bg / border / fill.
##   - Outside corners round; cap-to-bar seams stay square.
##   - 1-pixel inner GAP_PX slit separates the fill from an active cap;
##     outer border stays continuous across the composite.
##   - Disabled main: bg lightened (washed-out look); text colors unchanged.
##   - Disabled cap: bg and border drop entirely so the cap symbol floats
##     in mid-tone, and Main owns the bar's end border on that side.
##
## Three layout modes (mode @export):
##   WITH_BOTH  — minus + main + plus
##   WITH_PLUS  — main + plus
##   NEITHER    — just main (fill becomes the rounded shape itself)
##
## Currently swapped in for FillBar in upgrade rows + currency bars + drop
## section. The shim methods at the bottom are no-ops while iteration is
## still settling — Phase C wires them to real game state.

const BORDER_PX := 4
# Outer corner radius — applied only on the OUTSIDE corners of the composite
# (whichever node forms the perimeter). Fill mirrors these so its visible
# corners flow into the border curve.
const RADIUS_PX := 3
# Thin transparent gap inside the button between the fill and each cap, so
# the cap reads as separate while the outer border stays continuous.
const GAP_PX := 1


func _bar_tint() -> Color:
	# bar_color overrides the theme's normal-text color when alpha > 0 —
	# currencies tint per-coin; upgrade rows + drop buttons fall back to the
	# palette's `normal_text_color` so theme swaps propagate. Shared with
	# MainMenuButton so the menu and the gameplay baseline button can't drift.
	return bar_color if bar_color.a > 0.0 else ThemeProvider.theme.normal_text_color


enum Mode { WITH_BOTH, WITH_PLUS, NEITHER }

## Default NEITHER — matches the original FillBar's "side buttons hidden"
## default. setup_plus / setup_minus elevate to WITH_PLUS / WITH_BOTH.
## Don't change this without auditing `*.plus_button.visible` reads in
## coin_values.gd + upgrade_section.gd, which use it as a "wired?" signal.
@export var mode: Mode = Mode.NEITHER:
	set(value):
		if mode == value: return
		mode = value
		_queue_apply()

@export var title_text: String = "Add rows":
	set(value):
		if title_text == value: return
		title_text = value
		_queue_apply_text()

@export var num_text: String = "":
	set(value):
		if num_text == value: return
		num_text = value
		_queue_apply_text()

@export_range(0.0, 1.0) var fill_amount: float = 0.36:
	set(value):
		var clamped := clampf(value, 0.0, 1.0)
		if absf(fill_amount - clamped) < 0.001: return
		fill_amount = clamped
		_queue_apply_fill()

# Per-bar color override (e.g. currencies). Color(0,0,0,0) → falls back to
# the theme's neutral palette color via `_bar_tint()`.
@export var bar_color: Color = Color(0, 0, 0, 0):
	set(value):
		if bar_color == value: return
		bar_color = value
		_queue_apply()

# Disabled / filled state — driven by game via set_main_disabled / set_*_filled.
@export var demo_main_disabled: bool = false:
	set(value):
		if demo_main_disabled == value: return
		demo_main_disabled = value
		_queue_apply()
@export var demo_minus_filled: bool = true:
	set(value):
		if demo_minus_filled == value: return
		demo_minus_filled = value
		_queue_apply()
@export var demo_plus_filled: bool = true:
	set(value):
		if demo_plus_filled == value: return
		demo_plus_filled = value
		_queue_apply()

# ── FillBar-compat signals (declared so existing connects don't error) ──
signal main_pressed
signal main_mouse_entered
signal main_mouse_exited
signal plus_pressed
signal plus_mouse_entered
signal plus_mouse_exited
signal minus_pressed
signal minus_mouse_entered
signal minus_mouse_exited
signal side_button_hover(text: String)

# Side-button callbacks supplied by setup_plus / setup_minus.
var _plus_callback: Callable
var _plus_hover_callback: Callable
var _plus_update_callback: Callable
var _minus_callback: Callable
var _minus_hover_callback: Callable
var _minus_update_callback: Callable

# Attention tween (set_attention)
var _attention_tween: Tween

@onready var main_button: Button = $Main
@onready var plus_button: Button = $Plus
@onready var minus_button: Button = $Minus
@onready var _fill_bounds: Control = $Main/FillBounds
@onready var _title_lbl: Label = $Main/FillBounds/TitleLbl
@onready var _num_lbl: Label = $Main/FillBounds/NumLbl
@onready var _fill_clip: Control = $Main/FillBounds/FillClip
@onready var _fill_panel: Panel = $Main/FillBounds/FillClip/Fill
@onready var _fill_title_lbl: Label = $Main/FillBounds/FillClip/FillTitleLbl
@onready var _fill_num_lbl: Label = $Main/FillBounds/FillClip/FillNumLbl

# Deferred-apply state: setter mutations within a single frame collapse
# into one _apply call instead of N stylebox+override rebuilds.
var _apply_pending := false
var _apply_fill_pending := false
var _apply_text_pending := false


func _queue_apply() -> void:
	if _apply_pending or not is_inside_tree(): return
	_apply_pending = true
	_flush_apply.call_deferred()


func _queue_apply_fill() -> void:
	if _apply_pending or _apply_fill_pending or not is_inside_tree(): return
	_apply_fill_pending = true
	_flush_apply_fill.call_deferred()


func _queue_apply_text() -> void:
	if _apply_pending or _apply_text_pending or not is_inside_tree(): return
	_apply_text_pending = true
	_flush_apply_text.call_deferred()


func _flush_apply() -> void:
	_apply_pending = false
	# A full apply subsumes pending fill / text passes; clear their flags too.
	_apply_fill_pending = false
	_apply_text_pending = false
	if is_inside_tree(): _apply()


func _flush_apply_fill() -> void:
	_apply_fill_pending = false
	if not _apply_pending and is_inside_tree(): _apply_fill()


func _flush_apply_text() -> void:
	_apply_text_pending = false
	if not _apply_pending and is_inside_tree(): _apply_text()


func _ready() -> void:
	main_button.focus_mode = Control.FOCUS_NONE
	plus_button.focus_mode = Control.FOCUS_NONE
	minus_button.focus_mode = Control.FOCUS_NONE
	# Wire signals to mirror FillBar's public API. Main forwards 1:1 via
	# direct Signal.emit Callables (no lambdas); plus/minus go through
	# named handlers because they also fire stored callbacks + tooltip
	# hover refresh.
	main_button.pressed.connect(main_pressed.emit)
	main_button.mouse_entered.connect(main_mouse_entered.emit)
	main_button.mouse_exited.connect(main_mouse_exited.emit)
	plus_button.pressed.connect(_on_plus_pressed)
	plus_button.mouse_entered.connect(_on_plus_mouse_entered)
	plus_button.mouse_exited.connect(_on_plus_mouse_exited)
	minus_button.pressed.connect(_on_minus_pressed)
	minus_button.mouse_entered.connect(_on_minus_mouse_entered)
	minus_button.mouse_exited.connect(_on_minus_mouse_exited)
	_apply()


func _apply() -> void:
	var has_minus := (mode == Mode.WITH_BOTH)
	var has_plus := (mode != Mode.NEITHER)
	# A "disabled" cap has no bg + no border — the bar's outline closes at
	# Main's edge as if the cap weren't there, and the cap symbol floats.
	var has_minus_active := has_minus and demo_minus_filled
	var has_plus_active := has_plus and demo_plus_filled
	minus_button.visible = has_minus
	plus_button.visible = has_plus

	# Top/bottom: fill flush with Main's outer edge.
	# Cap-side: inset by GAP_PX only when the cap is ACTIVE (filled); a
	# disabled cap is treated like "no cap" so Main owns the outline.
	_fill_bounds.offset_left = GAP_PX if has_minus_active else 0
	_fill_bounds.offset_right = -GAP_PX if has_plus_active else 0
	_fill_bounds.offset_top = 0
	_fill_bounds.offset_bottom = 0

	var minus_style := _make_side_style(false, demo_minus_filled)
	var main_style := _make_main_style(has_minus, has_plus, has_minus_active, has_plus_active)
	var plus_style := _make_side_style(true, demo_plus_filled)
	for state in ["normal", "hover", "pressed", "disabled"]:
		minus_button.add_theme_stylebox_override(state, minus_style)
		main_button.add_theme_stylebox_override(state, main_style)
		plus_button.add_theme_stylebox_override(state, plus_style)
	# Hide Main's own text so the BaseLbl/FillLbl overlay alone shows the label.
	main_button.text = ""
	main_button.add_theme_color_override("font_color", Color.TRANSPARENT)

	# Text colors are semantic, not raw BG_6/BG_7 — they have to flip with
	# theme polarity. The bar fill IS `normal_text_color`, so text on the
	# filled portion uses `background_color` (the visual opposite), and text
	# on the empty portion uses `normal_text_color` (visible on the page bg
	# by definition). Disabled MAIN fades both alongside the lightened bg so
	# the whole "at-max" state reads dim. Disabled CAP keeps a mid-tone so
	# the floating glyph reads against the scene.
	var t: VisualTheme = ThemeProvider.theme
	var cap_disabled_text: Color = t.bg_shade_3
	var is_tinted := bar_color.a > 0.0
	var main_faded := demo_main_disabled and not is_tinted
	var fill_text: Color = t.background_color
	var base_text: Color = t.normal_text_color
	var cap_filled_text: Color = t.background_color
	if main_faded:
		fill_text = Color(fill_text.r, fill_text.g, fill_text.b, 0.6)
		base_text = Color(base_text.r, base_text.g, base_text.b, 0.6)
	var minus_text: Color = cap_filled_text if demo_minus_filled else cap_disabled_text
	var plus_text: Color = cap_filled_text if demo_plus_filled else cap_disabled_text
	minus_button.add_theme_color_override("font_color", minus_text)
	minus_button.add_theme_color_override("font_hover_color", minus_text)
	minus_button.add_theme_color_override("font_disabled_color", cap_disabled_text)
	plus_button.add_theme_color_override("font_color", plus_text)
	plus_button.add_theme_color_override("font_hover_color", plus_text)
	plus_button.add_theme_color_override("font_disabled_color", cap_disabled_text)
	_title_lbl.add_theme_color_override("font_color", base_text)
	_num_lbl.add_theme_color_override("font_color", base_text)
	_fill_title_lbl.add_theme_color_override("font_color", fill_text)
	_fill_num_lbl.add_theme_color_override("font_color", fill_text)

	_apply_text()
	_apply_fill()


func _apply_text() -> void:
	if _title_lbl:
		_title_lbl.text = title_text
		_fill_title_lbl.text = title_text
	if _num_lbl:
		_num_lbl.text = num_text
		_fill_num_lbl.text = num_text
		# Empty num → title centers across the whole bar; hide num labels so
		# their right-aligned position doesn't reserve space.
		var has_num := not num_text.is_empty()
		_num_lbl.visible = has_num
		_fill_num_lbl.visible = has_num
		var align := HORIZONTAL_ALIGNMENT_LEFT if has_num else HORIZONTAL_ALIGNMENT_CENTER
		_title_lbl.horizontal_alignment = align
		_fill_title_lbl.horizontal_alignment = align


func _apply_fill() -> void:
	if not _fill_clip:
		return
	_fill_clip.anchor_right = fill_amount
	if _fill_panel:
		var has_minus := mode == Mode.WITH_BOTH
		var has_plus := mode != Mode.NEITHER
		_fill_panel.add_theme_stylebox_override("panel", _make_fill_style(has_minus, has_plus, demo_main_disabled))
	if fill_amount > 0.001:
		var stretch := 1.0 / fill_amount
		_fill_title_lbl.anchor_right = stretch
		_fill_num_lbl.anchor_right = stretch


func _make_fill_style(has_minus: bool, has_plus: bool, disabled: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	# Disabled bar bg is LIGHTER than enabled — washed-out look. But tinted
	# bars (currencies) never gray out: their color is their identity.
	var tint := _bar_tint()
	var is_tinted := bar_color.a > 0.0
	s.bg_color = tint.lightened(0.25) if disabled and not is_tinted else tint
	# Fill is flush with Main's outer edge on non-cap sides, so its corners
	# match Main's outer curve exactly (covering the border with same color).
	s.corner_radius_top_left = 0 if has_minus else RADIUS_PX
	s.corner_radius_bottom_left = 0 if has_minus else RADIUS_PX
	s.corner_radius_top_right = 0 if has_plus else RADIUS_PX
	s.corner_radius_bottom_right = 0 if has_plus else RADIUS_PX
	return s


func _make_side_style(is_right_side: bool, filled: bool = true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.content_margin_left = 10.0
	s.content_margin_top = 6.0
	s.content_margin_right = 10.0
	s.content_margin_bottom = 6.0
	if not filled:
		# Disabled cap: no bg, no border. Main owns the outline; the +/- glyph
		# floats outside the bar.
		s.bg_color = Color.TRANSPARENT
		s.border_color = Color.TRANSPARENT
		return s
	var tint := _bar_tint()
	s.bg_color = tint
	s.border_color = tint
	# Border on outside + top + bottom only; inner seam (against Main) is borderless.
	s.border_width_left = 0 if is_right_side else BORDER_PX
	s.border_width_top = BORDER_PX
	s.border_width_right = BORDER_PX if is_right_side else 0
	s.border_width_bottom = BORDER_PX
	# Cap's outside corners round so the whole composite shares one outline.
	if is_right_side:
		s.corner_radius_top_right = RADIUS_PX
		s.corner_radius_bottom_right = RADIUS_PX
	else:
		s.corner_radius_top_left = RADIUS_PX
		s.corner_radius_bottom_left = RADIUS_PX
	return s


func _make_main_style(has_minus: bool, has_plus: bool, has_minus_active: bool, has_plus_active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.content_margin_left = 14.0
	s.content_margin_top = 6.0
	s.content_margin_right = 14.0
	s.content_margin_bottom = 6.0
	s.bg_color = Color.TRANSPARENT
	s.border_color = _bar_tint()
	# Border: drawn only when the cap isn't actively covering that side, so
	# the bar's outline closes itself when a cap is disabled.
	s.border_width_left = 0 if has_minus_active else BORDER_PX
	s.border_width_top = BORDER_PX
	s.border_width_right = 0 if has_plus_active else BORDER_PX
	s.border_width_bottom = BORDER_PX
	# Corner: square whenever the mode has a cap on that side (even if the
	# cap is currently disabled) — the seam is always sharp.
	s.corner_radius_top_left = 0 if has_minus else RADIUS_PX
	s.corner_radius_bottom_left = 0 if has_minus else RADIUS_PX
	s.corner_radius_top_right = 0 if has_plus else RADIUS_PX
	s.corner_radius_bottom_right = 0 if has_plus else RADIUS_PX
	return s


# ── Public API (mirrors FillBar surface so call sites stay untouched) ──

func setup(_fill_color: Color, _disabled_color: Color) -> void:
	# Bar tint is set explicitly via `bar_color` (currencies do it; upgrade
	# rows + drop buttons leave it default = TAN). We deliberately ignore
	# the caller's fill_color so upgrade-row bars don't take on
	# button_enabled_color, which was FillBar's old per-state fill color but
	# isn't a good whole-bar tint.
	pass

func is_held() -> bool:
	# Polls Input so caller's button.disabled toggles don't interrupt the hold.
	return main_button.is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func update_text(t: String) -> void:
	title_text = t

func set_fill(percent: float) -> void:
	fill_amount = percent

func get_fill_clip() -> Control:
	return _fill_clip

func set_main_disabled(v: bool) -> void:
	main_button.disabled = v
	# Visual lightened state is driven by at_max via apply_fill_colors —
	# "can't afford" blocks clicks but leaves the bar looking normal.

func apply_fill_colors(_is_disabled: bool, at_max: bool = false) -> void:
	demo_main_disabled = at_max

func setup_plus(on_pressed: Callable, on_hover: Callable = Callable(), on_update: Callable = Callable()) -> void:
	_plus_callback = on_pressed
	_plus_hover_callback = on_hover
	_plus_update_callback = on_update
	show_plus_button(true)

func setup_minus(on_pressed: Callable, on_hover: Callable = Callable(), on_update: Callable = Callable()) -> void:
	_minus_callback = on_pressed
	_minus_hover_callback = on_hover
	_minus_update_callback = on_update
	show_minus_button(true)

func show_plus_button(show: bool) -> void:
	if show and mode == Mode.NEITHER:
		mode = Mode.WITH_PLUS
	elif not show:
		mode = Mode.NEITHER

func set_plus_disabled(v: bool) -> void:
	plus_button.disabled = v

func set_plus_filled(v: bool) -> void:
	demo_plus_filled = v

func update_plus() -> void:
	if _plus_update_callback.is_valid():
		_plus_update_callback.call()

func show_minus_button(show: bool) -> void:
	if show:
		mode = Mode.WITH_BOTH
	elif mode == Mode.WITH_BOTH:
		mode = Mode.WITH_PLUS

func set_minus_disabled(v: bool) -> void:
	minus_button.disabled = v

func set_minus_filled(v: bool) -> void:
	demo_minus_filled = v

func update_minus() -> void:
	if _minus_update_callback.is_valid():
		_minus_update_callback.call()

func set_attention(enabled: bool) -> void:
	if _attention_tween:
		_attention_tween.kill()
		_attention_tween = null
	if not enabled:
		scale = Vector2.ONE
		modulate.a = 1.0
		return
	_attention_tween = ThemeProvider.theme.blink_scale_fade(self, 1.05, 0.5)

func pulse_main(scale_override: float = 0.0) -> void:
	if not main_button.disabled:
		ThemeProvider.theme.pulse_control(main_button, scale_override)

func pulse_plus() -> void:
	if not plus_button.disabled:
		ThemeProvider.theme.pulse_control(plus_button)

func pulse_minus() -> void:
	if not minus_button.disabled:
		ThemeProvider.theme.pulse_control(minus_button)


# ── Internal: signal handlers ──────────────────────────────────────────

func _on_plus_pressed() -> void:
	if _plus_callback.is_valid():
		_plus_callback.call()
	# Re-emit hover info with fresh text so the tooltip reflects the post-
	# purchase cost without requiring the player to mouse out and back in.
	if _plus_hover_callback.is_valid():
		side_button_hover.emit(_plus_hover_callback.call())
	plus_pressed.emit()


func _on_plus_mouse_entered() -> void:
	pulse_plus()
	if _plus_hover_callback.is_valid():
		side_button_hover.emit(_plus_hover_callback.call())
	plus_mouse_entered.emit()


func _on_plus_mouse_exited() -> void:
	side_button_hover.emit("")
	plus_mouse_exited.emit()


func _on_minus_pressed() -> void:
	if _minus_callback.is_valid():
		_minus_callback.call()
	minus_pressed.emit()


func _on_minus_mouse_entered() -> void:
	pulse_minus()
	if _minus_hover_callback.is_valid():
		side_button_hover.emit(_minus_hover_callback.call())
	minus_mouse_entered.emit()


func _on_minus_mouse_exited() -> void:
	side_button_hover.emit("")
	minus_mouse_exited.emit()
