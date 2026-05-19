class_name MainMenu
extends Node3D

const MainScene := preload("res://entities/main/main.tscn")
const OptionsDialogScript := preload("res://entities/options_dialog/options_dialog.gd")
const VignetteScript := preload("res://entities/vignette/vignette.gd")

# TODO: real URLs before launch (stubbed placeholders for now).
const DISCORD_URL := "https://discord.gg/pleenko-placeholder"
const PRESS_KIT_URL := "https://pleenko.example.com/press"
const REPORT_BUG_URL := "https://github.com/kjbrown/pleenko/issues/new"

@onready var play_button: Button = $CanvasLayer/ButtonColumn/PlayButton
@onready var settings_button: Button = $CanvasLayer/ButtonColumn/SettingsButton
@onready var discord_button: Button = $CanvasLayer/ButtonColumn/DiscordButton
@onready var press_kit_button: Button = $CanvasLayer/ButtonColumn/PressKitButton
@onready var report_bug_button: Button = $CanvasLayer/ButtonColumn/ReportBugButton
@onready var quit_button: Button = $CanvasLayer/ButtonColumn/QuitButton
@onready var title_label: Label = $CanvasLayer/TitleLabel
@onready var confirm_overlay: ColorRect = $ConfirmLayer/Overlay
@onready var confirm_panel: PanelContainer = $ConfirmLayer/Overlay/Panel
@onready var confirm_label: Label = $ConfirmLayer/Overlay/Panel/VBox/ConfirmLabel
@onready var cancel_button: Button = $ConfirmLayer/Overlay/Panel/VBox/ButtonRow/CancelButton
@onready var confirm_reset_button: Button = $ConfirmLayer/Overlay/Panel/VBox/ButtonRow/ConfirmResetButton

# Test seams (PeekAnimator precedent): production defaults; tests inject spies
# so the suite never launches a browser, wipes the real save, or kills itself.
var _shell_open_fn := func(url: String) -> void: OS.shell_open(url)
var _quit_fn := func() -> void: get_tree().quit()
var _full_reset_fn := func() -> void: SaveManager.full_reset()

var _options_dialog: CanvasLayer


func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	for button in [play_button, settings_button, discord_button, press_kit_button,
			report_bug_button, quit_button, cancel_button, confirm_reset_button]:
		t.apply_button_theme(button)

	# Title: themed font + palette color (never raw Color/Font) — same idiom as
	# options_dialog.gd's title.
	var font: Font = t.button_font if t.button_font else t.label_font
	if font:
		title_label.add_theme_font_override("font", font)
	title_label.add_theme_font_size_override("font_size", 64)
	title_label.add_theme_color_override("font_color", t.normal_text_color)

	confirm_overlay.color = t.overlay_color
	# The default PanelContainer stylebox is a dark engine grey, which kills the
	# dark themed text. Give it an intentional light card from the palette so the
	# dark text reads — same dark-on-light contrast as the rest of the menu UI.
	# Colors come from the palette; border width / padding are plain layout
	# constants (not part of the button theme), matching options_dialog.gd.
	var card := StyleBoxFlat.new()
	card.bg_color = t.bg_shade_6
	card.border_color = t.button_border_color
	card.set_border_width_all(2)
	card.set_corner_radius_all(t.button_border_radius)
	card.set_content_margin_all(28.0)
	confirm_panel.add_theme_stylebox_override("panel", card)
	confirm_label.add_theme_color_override("font_color", t.normal_text_color)

	_setup_options_dialog()
	_setup_vignette()

	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	discord_button.pressed.connect(_on_discord_pressed)
	press_kit_button.pressed.connect(_on_press_kit_pressed)
	report_bug_button.pressed.connect(_on_report_bug_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	confirm_reset_button.pressed.connect(_on_confirm_reset_pressed)

	confirm_overlay.visible = false


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


func _on_press_kit_pressed() -> void:
	_open_url(PRESS_KIT_URL)


func _on_report_bug_pressed() -> void:
	_open_url(REPORT_BUG_URL)


func _open_url(url: String) -> void:
	_shell_open_fn.call(url)


func _on_quit_pressed() -> void:
	_quit_fn.call()


# Reset Game lives inside Settings. The dialog signals up; MainMenu owns the
# confirm (the reused, palette-styled ConfirmLayer) and the destructive call.
func _on_reset_requested() -> void:
	_options_dialog.hide_dialog()
	confirm_overlay.visible = true


func _on_cancel_pressed() -> void:
	confirm_overlay.visible = false
	_options_dialog.show_dialog()


func _on_confirm_reset_pressed() -> void:
	# full_reset() clears all autoload state in memory and wipes the save, so
	# no scene reload is needed — the menu shows no save-derived state.
	_full_reset_fn.call()
	confirm_overlay.visible = false
