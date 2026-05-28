class_name MenuTitle
extends Control

## Animated PLUNK wordmark for the main menu. Five per-letter Labels in an
## HBoxContainer wobble elastically when a live `MenuBoard` decorative coin
## crosses each letter's screen rect (reuses the peg-wobble curve at smaller
## scale). Visual-only — no audio (the menu already has chord bed + peg
## ticks + hover plucks).
##
## Architecture follows PeekAnimator: Callable seams for the menu-board
## query, the camera unproject, and behind-check so the wobble + hit-detection
## logic are testable without a Camera3D / live scene tree.

const LETTER_FONT_SIZE := 120
const EYEBROW_FONT_SIZE := 44
const EYEBROW_TEXT := "now with more"
const EYEBROW_ALPHA := 0.45
## Staggered fade-in for each eyebrow character. Each char alpha tweens 0→1
## over EYEBROW_FADE_DURATION, with each starting EYEBROW_FADE_STAGGER after
## the previous — so the line writes itself on once when the menu opens.
const EYEBROW_FADE_DURATION := 1.0
const EYEBROW_FADE_STAGGER := 0.2

# Gasoek One (OFL, free to embed) is the wordmark display face. Project's
# VendSans stays the default for everything else, including the eyebrow.
const LETTER_FONT := preload("res://assets/fonts/Gasoek_One/GasoekOne-Regular.ttf")

## Per-letter elastic wobble. Same curve as MenuBoard._wobble_peg (TRANS_ELASTIC
## + EASE_OUT), smaller peak / shorter duration since the letters are 2D UI.
const LETTER_WOBBLE_SCALE_PEAK := 1.12
const LETTER_WOBBLE_DURATION := 0.9
## Per-letter cooldown — prevents spam when many coins drift through one rect.
const LETTER_WOBBLE_COOLDOWN_SEC := 0.6

@onready var _eyebrow_row: HBoxContainer = $VBox/EyebrowRow
@onready var _letter_row: HBoxContainer = $VBox/LetterRow
@onready var _letter_p: Label = $VBox/LetterRow/LetterP
@onready var _letter_l: Label = $VBox/LetterRow/LetterL
@onready var _letter_u: Label = $VBox/LetterRow/LetterU
@onready var _letter_n: Label = $VBox/LetterRow/LetterN
@onready var _letter_k: Label = $VBox/LetterRow/LetterK

var _letters: Array[Label] = []
var _letter_wobble_tweens: Array[Tween] = []
var _letter_next_wobble_time: PackedFloat32Array = PackedFloat32Array()
# Tracks last-frame inside state per letter (any coin overlapping the rect).
var _letter_was_inside: Array[bool] = []
# Per-character Labels in the eyebrow row + their fade-in tweens. Each char
# is its own Control so modulate.a can be tweened independently.
var _eyebrow_chars: Array[Label] = []
var _eyebrow_fade_tweens: Array[Tween] = []

var _menu_board: MenuBoard
var _camera: Camera3D

# Test seams (PeekAnimator precedent): production defaults wire to MenuBoard /
# Camera3D; tests inject stubs.
var get_coin_positions_fn: Callable
var unproject_fn: Callable
var is_behind_fn: Callable


func setup(menu_board: MenuBoard) -> void:
	_menu_board = menu_board

	if not get_coin_positions_fn.is_valid():
		get_coin_positions_fn = func() -> PackedVector3Array:
			if _menu_board == null:
				return PackedVector3Array()
			return _menu_board.get_live_coin_positions()
	if not unproject_fn.is_valid():
		unproject_fn = func(p: Vector3) -> Vector2:
			return _camera.unproject_position(p) if _camera != null else Vector2.ZERO
	if not is_behind_fn.is_valid():
		is_behind_fn = func(p: Vector3) -> bool:
			return _camera.is_position_behind(p) if _camera != null else true


func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme

	_letters = [_letter_p, _letter_l, _letter_u, _letter_n, _letter_k]
	_letter_wobble_tweens.resize(_letters.size())
	_letter_next_wobble_time.resize(_letters.size())
	_letter_was_inside.resize(_letters.size())
	for i in _letters.size():
		_letter_wobble_tweens[i] = null
		_letter_next_wobble_time[i] = 0.0
		_letter_was_inside[i] = false

	_apply_theme(t)

	for letter in _letters:
		letter.resized.connect(_on_letter_resized.bind(letter))
		_on_letter_resized(letter)

	# Right-align the eyebrow to PLUNK's actual rendered width — without this it
	# stretches to the full title rect (which extends past K) and floats off.
	_letter_row.resized.connect(_match_eyebrow_to_letter_row_width)
	_match_eyebrow_to_letter_row_width()

	_start_eyebrow_fade_in()

	set_process(true)


func _match_eyebrow_to_letter_row_width() -> void:
	_eyebrow_row.custom_minimum_size.x = _letter_row.size.x


func _apply_theme(t: VisualTheme) -> void:
	# Letters use the dedicated wordmark face (Gasoek One); eyebrow keeps the
	# project's default font from the theme. Wordmark + eyebrow share
	# `normal_text_color` so they read as a single unit.
	var plunk_color: Color = t.normal_text_color
	for letter: Label in [_letter_p, _letter_l, _letter_u, _letter_n, _letter_k]:
		letter.add_theme_font_override("font", LETTER_FONT)
		letter.add_theme_font_size_override("font_size", LETTER_FONT_SIZE)
		letter.add_theme_color_override("font_color", plunk_color)
		letter.pivot_offset = letter.size * 0.5
	_build_eyebrow_chars(t, plunk_color)
	# Row modulate carries the eyebrow's faded look; per-char modulate.a then
	# tweens 0→1 underneath, so final visible alpha = EYEBROW_ALPHA * char_a.
	_eyebrow_row.modulate = Color(1.0, 1.0, 1.0, EYEBROW_ALPHA)


func _build_eyebrow_chars(t: VisualTheme, color: Color) -> void:
	var font: Font = t.button_font if t.button_font else t.label_font
	for c: String in EYEBROW_TEXT:
		var lbl := Label.new()
		lbl.text = c
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if font:
			lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", EYEBROW_FONT_SIZE)
		lbl.add_theme_color_override("font_color", color)
		lbl.modulate.a = 0.0
		_eyebrow_row.add_child(lbl)
		_eyebrow_chars.append(lbl)


func _start_eyebrow_fade_in() -> void:
	for i in _eyebrow_chars.size():
		var lbl: Label = _eyebrow_chars[i]
		var tw: Tween = create_tween()
		if i > 0:
			tw.tween_interval(i * EYEBROW_FADE_STAGGER)
		tw.tween_property(lbl, "modulate:a", 1.0, EYEBROW_FADE_DURATION)
		_eyebrow_fade_tweens.append(tw)


func _on_letter_resized(letter: Label) -> void:
	letter.pivot_offset = letter.size * 0.5


func _process(_delta: float) -> void:
	_detect_letter_hits()


func _detect_letter_hits() -> void:
	if _menu_board == null or _letters.is_empty():
		return
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return

	var world_positions: PackedVector3Array = get_coin_positions_fn.call()
	# Precompute letter global rects once per frame.
	var letter_rects: Array[Rect2] = []
	letter_rects.resize(_letters.size())
	for i in _letters.size():
		letter_rects[i] = _letters[i].get_global_rect()

	var now: float = Time.get_ticks_msec() / 1000.0
	var any_inside: Array[bool] = []
	any_inside.resize(_letters.size())
	for i in any_inside.size():
		any_inside[i] = false

	for wp: Vector3 in world_positions:
		if is_behind_fn.call(wp):
			continue
		var screen: Vector2 = unproject_fn.call(wp)
		var idx := letter_hit_at_screen_pos(letter_rects, screen)
		if idx >= 0:
			any_inside[idx] = true

	for i in _letters.size():
		var entering: bool = any_inside[i] and not _letter_was_inside[i]
		_letter_was_inside[i] = any_inside[i]
		if entering and now >= _letter_next_wobble_time[i]:
			_wobble_letter(i)
			_letter_next_wobble_time[i] = now + LETTER_WOBBLE_COOLDOWN_SEC


func _wobble_letter(idx: int) -> void:
	if idx < 0 or idx >= _letters.size():
		return
	var letter: Label = _letters[idx]
	# Prior-kill-and-replace dedupe (mirrors MenuBoard._peg_wobbles pattern).
	var prior: Tween = _letter_wobble_tweens[idx]
	if prior != null and prior.is_valid():
		prior.kill()

	# Ensure pivot is centred before the scale tween (size may have just
	# settled after a resize).
	letter.pivot_offset = letter.size * 0.5

	var tw: Tween = create_tween()
	tw.tween_property(letter, "scale",
			Vector2.ONE, LETTER_WOBBLE_DURATION) \
		.from(Vector2(LETTER_WOBBLE_SCALE_PEAK, LETTER_WOBBLE_SCALE_PEAK)) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# Only clear + snap-reset if WE'RE still the active wobble — a newer
	# wobble that replaced us mid-flight is allowed to keep tweening.
	tw.tween_callback(func() -> void:
		if _letter_wobble_tweens[idx] == tw:
			_letter_wobble_tweens[idx] = null
			letter.scale = Vector2.ONE)
	_letter_wobble_tweens[idx] = tw


func _exit_tree() -> void:
	for tw: Tween in _letter_wobble_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	for tw: Tween in _eyebrow_fade_tweens:
		if tw != null and tw.is_valid():
			tw.kill()


# ── Pure static helpers (unit-testable without a scene tree) ──

## Returns the index of the first letter rect containing `p`, or -1 if none.
static func letter_hit_at_screen_pos(letter_rects: Array[Rect2],
		p: Vector2) -> int:
	for i in letter_rects.size():
		if letter_rects[i].has_point(p):
			return i
	return -1
