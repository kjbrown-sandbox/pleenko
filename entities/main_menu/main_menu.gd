class_name MainMenu
extends Node3D

const MainScene := preload("res://entities/main/main.tscn")
const OptionsDialogScript := preload("res://entities/options_dialog/options_dialog.gd")
const VignetteScript := preload("res://entities/vignette/vignette.gd")

const DISCORD_URL := "https://discord.gg/uadVU3K63y"
const FEEDBACK_URL := "https://docs.google.com/forms/d/e/1FAIpQLSdRHDVqaQzeNyE8e4Wtf-kIO_pXKOPUvtnAt3X3wrnBU2Xk5g/viewform?usp=publish-editor"

@onready var menu_board: MenuBoard = $MenuBoard
@onready var play_button: MainMenuButton = $CanvasLayer/ButtonColumn/PlayButton
@onready var settings_button: MainMenuButton = $CanvasLayer/ButtonColumn/SettingsButton
@onready var discord_button: MainMenuButton = $CanvasLayer/ButtonColumn/DiscordButton
@onready var feedback_button: MainMenuButton = $CanvasLayer/ButtonColumn/FeedbackButton
@onready var quit_button: MainMenuButton = $CanvasLayer/ButtonColumn/QuitButton
@onready var menu_title: MenuTitle = $CanvasLayer/MenuTitle
@onready var confirm_overlay: FrostedOverlay = $ConfirmLayer/Overlay
@onready var confirm_label: Label = $ConfirmLayer/Overlay/CenterContainer/VBox/ConfirmLabel
@onready var cancel_button: RefinedBaselineButton = $ConfirmLayer/Overlay/CenterContainer/VBox/ButtonRow/CancelButton
@onready var confirm_reset_button: RefinedBaselineButton = $ConfirmLayer/Overlay/CenterContainer/VBox/ButtonRow/ConfirmResetButton

# Test seams (PeekAnimator precedent): production defaults; tests inject spies
# so the suite never launches a browser, wipes the real save, or kills itself.
var _shell_open_fn := func(url: String) -> void: OS.shell_open(url)
var _quit_fn := func() -> void: get_tree().quit()
var _full_reset_fn := func() -> void: SaveManager.full_reset()

var _options_dialog: CanvasLayer

# Round-robin pluck dispatcher: each chord-bed beat advances to the next
# MainMenuButton in the column. Population order matches column order top→bottom
# so the visible wave reads "starting at the top button" per the design.
var _arpeggiator := MenuHoverArpeggiator.new()
var _menu_buttons: Array[MainMenuButton] = []
var _beat_counter: int = 0
# Strumming pauses while any button is hovered — the cascading plucks compete
# with the player's interaction. Counter (not bool) because hover_started on
# one button can fire before hover_ended on the previous if they overlap.
# After all hovers end, plucks stay suppressed for an additional grace window
# so the cascade doesn't snap back the moment the cursor leaves a button.
var _hover_count: int = 0
const HOVER_PLUCK_RESUME_DELAY_MS := 500
var _last_hover_end_ms: int = -HOVER_PLUCK_RESUME_DELAY_MS - 1  # don't gate first ticks
# Hover notes are quantized to an eighth-note (0.125s) grid so they read as
# rhythmic instead of jittery. The timer free-runs from _ready — NOT phase-
# locked to MenuBoard's chord bed, so a hover note can land up to 0.125s off
# the bed's beat (musically close enough for this UX). Each hover commits a
# pitch to the queue; the timer pops one per tick. Queue capacity 3 —
# additional rapid hovers are dropped (and don't advance the arpeggiator
# either, so the arpeggio progression stays in sync with what's audible).
const HOVER_QUANTIZE_SECONDS := 0.125
const HOVER_QUEUE_CAPACITY := 3
const HOVER_NOTE_SUSTAIN_S := 3.0
var _hover_pitch_queue: Array[float] = []
var _hover_quantize_timer: Timer


func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	# Confirm-dialog buttons are RefinedBaselineButtons (filled, capless) — they
	# style themselves; MainMenuButtons own their styling too.

	menu_title.setup(menu_board)

	# Content sits directly on the full-screen frosted overlay (no card box),
	# matching the Settings dialog opened from this menu.
	confirm_label.add_theme_color_override("font_color", t.normal_text_color)

	_setup_options_dialog()
	_setup_vignette()

	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	discord_button.pressed.connect(_on_discord_pressed)
	feedback_button.pressed.connect(_on_feedback_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	cancel_button.main_pressed.connect(_on_cancel_pressed)
	confirm_reset_button.main_pressed.connect(_on_confirm_reset_pressed)
	RefinedBaselineButton.equalize_widths([cancel_button, confirm_reset_button])

	_menu_buttons = [play_button, settings_button, discord_button, feedback_button, quit_button]
	for btn in _menu_buttons:
		btn.hover_started.connect(_on_menu_button_hover)
		btn.hover_ended.connect(_on_menu_button_hover_ended)
	menu_board.chime_beat_fired.connect(_on_chime_beat_fired)

	_hover_quantize_timer = Timer.new()
	_hover_quantize_timer.wait_time = HOVER_QUANTIZE_SECONDS
	_hover_quantize_timer.autostart = true
	_hover_quantize_timer.timeout.connect(_on_hover_quantize_tick)
	add_child(_hover_quantize_timer)

	# Feed the MenuBoard's live chord to AudioManager so the dialog/confirm
	# RefinedBaselineButtons hover in tune with the bed, just like the
	# MainMenuButtons (whose hover reads the same source directly).
	AudioManager.ui_hover_chord_pitches_fn = func() -> PackedFloat32Array:
		if not is_instance_valid(menu_board):
			return PackedFloat32Array()
		return menu_board.get_chord_pitches(menu_board.get_current_chord_index())

	confirm_overlay.visible = false


func _exit_tree() -> void:
	# Drop the menu chord source so gameplay hovers fall back to the board chord.
	if AudioManager.ui_hover_chord_pitches_fn.is_valid():
		AudioManager.ui_hover_chord_pitches_fn = Callable()


func _setup_options_dialog() -> void:
	# Mirrors main.gd's setup, but MAIN_MENU context swaps the in-game footer
	# for Reset Game / Close. Context must be set BEFORE add_child — the dialog
	# builds its whole UI (incl. footer) in _ready.
	_options_dialog = CanvasLayer.new()
	_options_dialog.layer = 10
	_options_dialog.set_script(OptionsDialogScript)
	_options_dialog.context = OptionsDialog.Context.MAIN_MENU
	add_child(_options_dialog)
	_options_dialog.reset_requested.connect(_on_reset_requested)


func _setup_vignette() -> void:
	# Same self-contained vignette overlay the gameplay scene uses (main.gd);
	# it self-gates on VisualTheme.vignette_enabled and reads its own params.
	var vignette := CanvasLayer.new()
	vignette.set_script(VignetteScript)
	add_child(vignette)


func _on_play_pressed() -> void:
	SceneManager.set_new_scene(MainScene)


func _on_settings_pressed() -> void:
	_options_dialog.show_dialog()


func _on_discord_pressed() -> void:
	_open_url(DISCORD_URL)


func _on_feedback_pressed() -> void:
	_open_url(FEEDBACK_URL)


func _open_url(url: String) -> void:
	_shell_open_fn.call(url)


func _on_quit_pressed() -> void:
	_quit_fn.call()


# Reset Game lives inside Settings. The dialog signals up; MainMenu owns the
# confirm (the reused, palette-styled ConfirmLayer) and the destructive call.
func _on_reset_requested() -> void:
	_options_dialog.hide_dialog()
	confirm_overlay.fade_in()


func _on_cancel_pressed() -> void:
	confirm_overlay.fade_out(func(): confirm_overlay.visible = false)
	_options_dialog.show_dialog()


func _on_confirm_reset_pressed() -> void:
	# full_reset() clears all autoload state in memory and wipes the save, so
	# no scene reload is needed — the menu shows no save-derived state.
	_full_reset_fn.call()
	confirm_overlay.fade_out(func(): confirm_overlay.visible = false)


# MenuBoard's chord bed fires every 0.5s; the strum walks down the column then
# bounces back up (ping-pong). For N buttons the period is 2*(N-1) beats =
# 8 for 5 buttons; reading position = beat_counter % period then mirroring
# above N gives 0,1,2,3,4,3,2,1, repeat. Pauses while the user is hovering —
# beat_counter doesn't advance so the cascade resumes where it left off.
func _on_chime_beat_fired(_chord_idx: int, _beat_idx: int) -> void:
	if _menu_buttons.is_empty() or _hover_count > 0: return
	if Time.get_ticks_msec() - _last_hover_end_ms < HOVER_PLUCK_RESUME_DELAY_MS: return
	var n := _menu_buttons.size()
	var period: int = maxi(1, 2 * (n - 1))
	var pos := _beat_counter % period
	var index: int = pos if pos < n else period - pos
	_menu_buttons[index].pluck()
	_beat_counter += 1


func _on_menu_button_hover_ended() -> void:
	_hover_count = maxi(0, _hover_count - 1)
	if _hover_count == 0:
		_last_hover_end_ms = Time.get_ticks_msec()


# Hover arpeggio: each hover commits a quantized note to the playback queue.
# Queue-full hovers are dropped without advancing the arpeggiator so its
# progression stays aligned with what the player will actually hear.
func _on_menu_button_hover() -> void:
	_hover_count += 1
	if _hover_pitch_queue.size() >= HOVER_QUEUE_CAPACITY:
		return
	var note := _arpeggiator.advance(Time.get_ticks_msec())
	var chord_idx := menu_board.get_current_chord_index()
	var pitches := menu_board.get_chord_pitches(chord_idx)
	if pitches.is_empty(): return
	_hover_pitch_queue.append(MenuHoverArpeggiator.pitch_mult_for(note.x, note.y, pitches))


# Pops one queued hover pitch per 0.125s tick — quantizes hovers to the grid.
func _on_hover_quantize_tick() -> void:
	if _hover_pitch_queue.is_empty(): return
	var pitch_mult: float = _hover_pitch_queue.pop_front()
	# BUCKET_VOLUME_DB (-17.5) — sits inside the chord bed's dynamic range
	# (bed plays roughly -23 to -11 dB across its arpeggio). Loud enough to
	# read as an interaction cue, quiet enough not to swamp the music.
	# Long sustain (3.0s vs the 0.6s default) so a single deliberate hover
	# gives a satisfying ring instead of a staccato blip.
	AudioManager.play_pitched_chime(pitch_mult, AudioManager.BUCKET_VOLUME_DB,
		HOVER_NOTE_SUSTAIN_S, Instrument.Type.MUSIC_BOX)
