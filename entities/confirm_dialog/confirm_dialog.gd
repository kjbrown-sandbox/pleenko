class_name ConfirmDialog
extends CanvasLayer

## Reusable yes/no confirmation overlay. Signals up — the parent owns the action
## and the destructive call; this dialog only collects the decision. UI is built
## in code (OptionsDialog precedent) so it can be attached to any scene via
## ConfirmDialog.new() without a per-scene .tscn. Content sits directly on the
## full-screen frosted overlay (no card box), matching OptionsDialog;
## `normal_text_color` reads as light against the darkened frost in challenge mode.

signal confirmed
signal cancelled

var _overlay: FrostedOverlay
var _label: Label
var _confirm_button: RefinedBaselineButton
var _cancel_button: RefinedBaselineButton


func _ready() -> void:
	layer = 10
	var t: VisualTheme = ThemeProvider.theme
	var font: Font = t.button_font if t.button_font else t.label_font

	_overlay = FrostedOverlay.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Swallow clicks so the dimmed game underneath can't be interacted with.
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Content sits directly on the full-screen frosted overlay (no card box) —
	# same layout as OptionsDialog.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.custom_minimum_size = Vector2(680.0, 0.0)
	center.add_child(vbox)

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

	_cancel_button = RefinedBaselineButton.create_action("", _on_cancel_pressed)
	row.add_child(_cancel_button)

	_confirm_button = RefinedBaselineButton.create_action("", _on_confirm_pressed)
	row.add_child(_confirm_button)

	visible = false


## Populate the message + button labels and show. The parent reacts to the
## `confirmed` / `cancelled` signals.
func show_confirm(message: String, confirm_text: String = "Confirm", cancel_text: String = "Cancel") -> void:
	_label.text = message
	_confirm_button.title_text = confirm_text
	_cancel_button.title_text = cancel_text
	# Deferred so each button's auto-size has resolved its own width first; then
	# both snap to the wider of the two.
	_equalize_buttons.call_deferred()
	visible = true
	_overlay.fade_in()


func _equalize_buttons() -> void:
	RefinedBaselineButton.equalize_widths([_cancel_button, _confirm_button])


func _on_confirm_pressed() -> void:
	_overlay.fade_out(func(): visible = false)
	confirmed.emit()


func _on_cancel_pressed() -> void:
	_overlay.fade_out(func(): visible = false)
	cancelled.emit()
