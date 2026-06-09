class_name ConfirmDialog
extends CanvasLayer

## Reusable yes/no confirmation overlay. Signals up — the parent owns the action
## and the destructive call; this dialog only collects the decision. UI is built
## in code (OptionsDialog precedent) so it can be attached to any scene via
## ConfirmDialog.new() without a per-scene .tscn. Styling mirrors
## ChallengeCompleteDialog (the in-game dialog that already reads correctly under
## the challenge theme): the engine's default dark PanelContainer + light text,
## NOT MainMenu's light card (which assumes the normal theme's dark text).

signal confirmed
signal cancelled

var _overlay: ColorRect
var _label: Label
var _confirm_button: Button
var _cancel_button: Button


func _ready() -> void:
	layer = 10
	var t: VisualTheme = ThemeProvider.theme
	var font: Font = t.button_font if t.button_font else t.label_font

	_overlay = ColorRect.new()
	_overlay.color = t.overlay_color
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Swallow clicks so the dimmed game underneath can't be interacted with.
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	# Default PanelContainer stylebox (dark) — same as ChallengeCompleteDialog.
	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.custom_minimum_size = Vector2(420.0, 0.0)
	margin.add_child(vbox)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_color_override("font_color", t.normal_text_color)
	_label.add_theme_font_size_override("font_size", 26)
	if font:
		_label.add_theme_font_override("font", font)
	vbox.add_child(_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vbox.add_child(row)

	_cancel_button = Button.new()
	_cancel_button.focus_mode = Control.FOCUS_NONE
	t.apply_button_theme(_cancel_button)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	row.add_child(_cancel_button)

	_confirm_button = Button.new()
	_confirm_button.focus_mode = Control.FOCUS_NONE
	t.apply_button_theme(_confirm_button)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	row.add_child(_confirm_button)

	visible = false


## Populate the message + button labels and show. The parent reacts to the
## `confirmed` / `cancelled` signals.
func show_confirm(message: String, confirm_text: String = "Confirm", cancel_text: String = "Cancel") -> void:
	_label.text = message
	_confirm_button.text = confirm_text
	_cancel_button.text = cancel_text
	visible = true


func _on_confirm_pressed() -> void:
	visible = false
	confirmed.emit()


func _on_cancel_pressed() -> void:
	visible = false
	cancelled.emit()
