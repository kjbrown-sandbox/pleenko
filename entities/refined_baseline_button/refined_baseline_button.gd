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

const BORDER_PX := 4
# Outer corner radius — applied only on the OUTSIDE corners of the composite
# (whichever node forms the perimeter). Fill mirrors these so its visible
# corners flow into the border curve.
const RADIUS_PX := 3
# Thin transparent gap inside the button between the fill and each cap, so
# the cap reads as separate while the outer border stays continuous.
const GAP_PX := 1

# Interaction states. NORMAL is also reused for the "disabled" Godot stylebox
# (a can't-afford button shows the resting look, never a hover/press tint).
enum BtnState { NORMAL, HOVER, PRESSED }
# Color response — same magnitudes as MainMenuButton: hover lightens the bar
# tint, press darkens it (the menu's exact 0.12 / 0.10). Derived from the bar
# tint, not raw colors, so theme swaps propagate. Applied to the cap bodies
# (native styleboxes) AND the main bar's fill panel so the change is visible on
# the bar itself, not just its thin border.
const HOVER_LIGHTEN := 0.12
const PRESS_DARKEN := 0.10
# Resolved interaction state of the MAIN bar — single source of truth for its
# border AND fill shade, recomputed by _refresh_interaction_visual() from the
# inputs below. (Caps shade natively off their own draw mode instead.) Driving
# the main bar by state rather than Godot's draw mode lets a held keyboard
# shortcut force the pressed look — see set_force_pressed().
var _visual_state: BtnState = BtnState.NORMAL
var _mouse_pressed := false   # left mouse held down on the main bar
# Forced pressed by an external held shortcut (e.g. the drop key). Distinct from
# is_held() below, which polls whether the MOUSE is held on the bar.
var _force_pressed := false

# Hover/held stretch — the MAIN bar grows and STAYS big the whole time it's
# hovered or held (mouse or drop key), settling back only when it returns to rest.
# scale.x is visual only (no layout reflow); pivot is the CAPPED edge so the bar
# grows toward its open side — left cap → grows right, right cap → grows left,
# both/none → both ways from centre. Hovering a cap never stretches the whole
# row (see _play_cap_hover).
const HOVER_STRETCH_AMOUNT := 0.03   # scale.x delta while stretched
const HOVER_STRETCH_OUT := 0.12      # fast extend on enter
const HOVER_STRETCH_RETURN := 0.5    # slower settle back on exit
var _stretch_tween: Tween
var _stretched := false              # currently extended (hovered or held)


func _bar_tint() -> Color:
	# bar_color overrides the theme's normal-text color when alpha > 0 —
	# currencies tint per-coin; upgrade rows + drop buttons fall back to the
	# palette's `normal_text_color` so theme swaps propagate. Shared with
	# MainMenuButton so the menu and the gameplay baseline button can't drift.
	return bar_color if bar_color.a > 0.0 else ThemeProvider.theme.normal_text_color


enum Mode { WITH_BOTH, WITH_PLUS, NEITHER }

## Default NEITHER — side buttons hidden until setup_plus / setup_minus
## elevate to WITH_PLUS / WITH_BOTH. Don't change this without auditing
## `*.plus_button.visible` reads in coin_values.gd + upgrade_section.gd,
## which use it as a "wired?" signal.
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

# ── Signals ──
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
	# A fill_amount change only moves the clip — never the panel color/corners —
	# so this hot path (every currency tick) updates geometry alone, no stylebox alloc.
	if not _apply_pending and is_inside_tree(): _update_fill_geometry()


func _flush_apply_text() -> void:
	_apply_text_pending = false
	if not _apply_pending and is_inside_tree(): _apply_text()


func _ready() -> void:
	main_button.focus_mode = Control.FOCUS_NONE
	plus_button.focus_mode = Control.FOCUS_NONE
	minus_button.focus_mode = Control.FOCUS_NONE
	# Main forwards 1:1 via direct Signal.emit Callables (no lambdas);
	# plus/minus go through named handlers because they also fire stored
	# callbacks + tooltip hover refresh.
	main_button.pressed.connect(main_pressed.emit)
	main_button.mouse_entered.connect(_on_main_mouse_entered)
	main_button.mouse_exited.connect(_on_main_mouse_exited)
	# Track press for the fill shade (the border shades natively; the fill panel
	# is a separate node, so we drive it from the same state transitions).
	main_button.button_down.connect(_on_main_button_down)
	main_button.button_up.connect(_on_main_button_up)
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

	# Caps shade natively (Godot swaps the per-state stylebox on hover/press).
	# "disabled" maps to NORMAL so a can't-afford cap keeps the resting look.
	for state in ["normal", "hover", "pressed", "disabled"]:
		var st := _state_for(state)
		minus_button.add_theme_stylebox_override(state, _make_side_style(false, demo_minus_filled, st))
		plus_button.add_theme_stylebox_override(state, _make_side_style(true, demo_plus_filled, st))
	# Main bar border follows _visual_state (all draw modes share one stylebox).
	_refresh_main_border()
	# Hide Main's own text so the BaseLbl/FillLbl overlay alone shows the label.
	main_button.text = ""
	main_button.add_theme_color_override("font_color", Color.TRANSPARENT)

	# Text colors are semantic, not raw BG_6/BG_7 — they have to flip with
	# theme polarity. The bar fill IS `normal_text_color`, so text on the
	# filled portion uses `background_color` (the visual opposite), and text
	# on the empty portion uses `normal_text_color` (visible on the page bg
	# by definition). At-max main fades both text + bg by 0.6 — but ONLY for
	# untinted bars: a tinted (currency) bar's color is its identity, so it
	# never gets the washed-out look. Disabled CAP keeps a mid-tone so the
	# floating glyph still reads against the scene.
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
	# Full fill refresh: rebuild the panel stylebox (color/corners can shift with
	# theme, tint, mode, disabled) THEN update geometry. Only reached from _apply()
	# — the frequent fill_amount + press paths call _update_fill_geometry() alone,
	# which allocates nothing.
	_refresh_fill_shade()
	_update_fill_geometry()


# Rebuilds the fill panel's stylebox for the current tint / mode / _visual_state.
# Shared by _apply_fill and _refresh_interaction_visual so the two can't drift.
func _refresh_fill_shade() -> void:
	if _fill_panel:
		_fill_panel.add_theme_stylebox_override("panel",
			_make_fill_style(mode == Mode.WITH_BOTH, mode != Mode.NEITHER, demo_main_disabled))


func _update_fill_geometry() -> void:
	if not _fill_clip:
		return
	_fill_clip.anchor_right = fill_amount
	if fill_amount > 0.001:
		var stretch := 1.0 / fill_amount
		_fill_title_lbl.anchor_right = stretch
		_fill_num_lbl.anchor_right = stretch


# Hover lightens, press darkens — matched to MainMenuButton. NORMAL (and the
# "disabled" stylebox, which maps here) returns the tint unchanged.
func _shade_for_state(tint: Color, state: BtnState) -> Color:
	match state:
		BtnState.HOVER: return tint.lightened(HOVER_LIGHTEN)
		BtnState.PRESSED: return tint.darkened(PRESS_DARKEN)
		_: return tint


func _state_for(state_name: String) -> BtnState:
	# Godot's "disabled" stylebox shares the resting (NORMAL) look on purpose.
	match state_name:
		"hover": return BtnState.HOVER
		"pressed": return BtnState.PRESSED
		_: return BtnState.NORMAL


func _make_fill_style(has_minus: bool, has_plus: bool, disabled: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	# Disabled bar bg is LIGHTER than enabled — washed-out look. But tinted
	# bars (currencies) never gray out: their color is their identity.
	var tint := _bar_tint()
	var is_tinted := bar_color.a > 0.0
	var base: Color = tint.lightened(0.25) if disabled and not is_tinted else tint
	# Hover lightens / press darkens the filled portion (the visible "bar"), so
	# the color response reads on the bar itself — not just the thin border.
	s.bg_color = _shade_for_state(base, _visual_state)
	# Fill is flush with Main's outer edge on non-cap sides, so its corners
	# match Main's outer curve exactly (covering the border with same color).
	s.corner_radius_top_left = 0 if has_minus else RADIUS_PX
	s.corner_radius_bottom_left = 0 if has_minus else RADIUS_PX
	s.corner_radius_top_right = 0 if has_plus else RADIUS_PX
	s.corner_radius_bottom_right = 0 if has_plus else RADIUS_PX
	return s


func _make_side_style(is_right_side: bool, filled: bool = true, state: BtnState = BtnState.NORMAL) -> StyleBoxFlat:
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
	# Solid cap: the whole body (bg + border) lightens on hover / darkens on
	# press, just like the menu button's solid bar.
	var shade := _shade_for_state(_bar_tint(), state)
	s.bg_color = shade
	s.border_color = shade
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


func _make_main_style(has_minus: bool, has_plus: bool, has_minus_active: bool, has_plus_active: bool, state: BtnState = BtnState.NORMAL) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.content_margin_left = 14.0
	s.content_margin_top = 6.0
	s.content_margin_right = 14.0
	s.content_margin_bottom = 6.0
	s.bg_color = Color.TRANSPARENT
	# Transparent body (the fill panel shows the progress color); only the border
	# responds to hover/press — lightened / darkened to match the menu button.
	s.border_color = _shade_for_state(_bar_tint(), state)
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


# ── Public API ──

func setup(_fill_color: Color, _disabled_color: Color) -> void:
	# Bar tint is set explicitly via `bar_color` (currencies do it; upgrade
	# rows + drop buttons leave it default = TAN). The caller's fill_color
	# is deliberately ignored — button_enabled_color isn't a good whole-bar
	# tint.
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


# ── Internal: signal handlers ──────────────────────────────────────────

# Caps don't stretch the row — just a small scale pop on the cap itself plus the
# hover note. Hover always acknowledges the hover, even when the cap is disabled
# (disabled only blocks the click; the washed-out look + tooltip convey that).
func _play_cap_hover(cap: Button) -> void:
	ThemeProvider.theme.pulse_control(cap)
	AudioManager.play_ui_hover()


# Extend the WHOLE row and hold (on), or settle it back (off). scale.x only — no
# layout reflow. See the HOVER_STRETCH_* block for the hold/pivot semantics.
func _set_stretched(on: bool) -> void:
	if _stretched == on:
		return
	_stretched = on
	if _stretch_tween and _stretch_tween.is_valid():
		_stretch_tween.kill()
	_apply_stretch_pivot()
	var target: float = (1.0 + HOVER_STRETCH_AMOUNT) if on else 1.0
	var duration: float = HOVER_STRETCH_OUT if on else HOVER_STRETCH_RETURN
	_stretch_tween = create_tween()
	_stretch_tween.tween_property(self, "scale:x", target, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


# Pivot at the CAPPED edge so the bar grows toward its open side.
func _apply_stretch_pivot() -> void:
	var has_left_cap := mode == Mode.WITH_BOTH
	var has_right_cap := mode != Mode.NEITHER
	var pivot_x: float
	if has_left_cap == has_right_cap:
		pivot_x = size.x * 0.5            # both caps or none → grow both ways
	elif has_left_cap:
		pivot_x = 0.0                     # left cap only → anchor left, grow right
	else:
		pivot_x = size.x                  # right cap only → anchor right, grow left
	pivot_offset = Vector2(pivot_x, size.y * 0.5)


# ── Main bar interaction: stretch + hover note + shade tracking ──

## Force the main bar's pressed look on/off from an external held shortcut (e.g.
## holding the drop hotkey). Independent of is_held() (which polls the MOUSE);
## combines with mouse state in _refresh_interaction_visual.
func set_force_pressed(pressed: bool) -> void:
	if _force_pressed == pressed:
		return
	_force_pressed = pressed
	_refresh_interaction_visual()


# Resolve the main bar's state from all inputs and reshade if it changed. Pressed
# wins (mouse OR forced shortcut), then hover, else normal.
func _refresh_interaction_visual() -> void:
	# Disabled only blocks the click — hover/press still shade so the button
	# always acknowledges interaction (e.g. the drop bar with a full queue).
	var state: BtnState
	if _mouse_pressed or _force_pressed:
		state = BtnState.PRESSED
	elif main_button.is_hovered():
		state = BtnState.HOVER
	else:
		state = BtnState.NORMAL
	# Stay stretched the whole time the bar is hovered OR held (e.g. drop key
	# down); settle back only at rest. This is what makes holding space stretch
	# the drop bar, not just shade it.
	_set_stretched(state != BtnState.NORMAL)
	if state == _visual_state:
		return
	_visual_state = state
	_refresh_main_border()
	_refresh_fill_shade()


# Border for the main bar — one stylebox shared across all draw modes, shaded by
# the resolved _visual_state (see the loop note in _apply).
func _refresh_main_border() -> void:
	var has_minus := mode == Mode.WITH_BOTH
	var has_plus := mode != Mode.NEITHER
	var style := _make_main_style(has_minus, has_plus,
		has_minus and demo_minus_filled, has_plus and demo_plus_filled, _visual_state)
	for state in ["normal", "hover", "pressed", "disabled"]:
		main_button.add_theme_stylebox_override(state, style)


func _on_main_mouse_entered() -> void:
	_refresh_interaction_visual()  # → HOVER state + stretch out (held while hovering)
	AudioManager.play_ui_hover()
	main_mouse_entered.emit()


func _on_main_mouse_exited() -> void:
	_refresh_interaction_visual()
	main_mouse_exited.emit()


func _on_main_button_down() -> void:
	_mouse_pressed = true
	_refresh_interaction_visual()


func _on_main_button_up() -> void:
	_mouse_pressed = false
	_refresh_interaction_visual()


func _on_plus_pressed() -> void:
	if _plus_callback.is_valid():
		_plus_callback.call()
	# Re-emit hover info with fresh text so the tooltip reflects the post-
	# purchase cost without requiring the player to mouse out and back in.
	if _plus_hover_callback.is_valid():
		side_button_hover.emit(_plus_hover_callback.call())
	plus_pressed.emit()


func _on_plus_mouse_entered() -> void:
	_play_cap_hover(plus_button)
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
	_play_cap_hover(minus_button)
	if _minus_hover_callback.is_valid():
		side_button_hover.emit(_minus_hover_callback.call())
	minus_mouse_entered.emit()


func _on_minus_mouse_exited() -> void:
	side_button_hover.emit("")
	minus_mouse_exited.emit()
