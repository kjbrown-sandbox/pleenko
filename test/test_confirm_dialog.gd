extends "res://test/test_base.gd"

## ConfirmDialog tests — run with:
##   godot --headless --scene res://test/test_confirm_dialog.tscn
##
## ConfirmDialog builds its UI in _ready(). show_confirm() populates the message
## + button labels; the buttons emit confirmed/cancelled (signals up) and hide.


func _run_tests() -> void:
	print("\n=== ConfirmDialog Tests ===\n")

	await test_show_confirm_populates_text_and_shows()
	await test_default_button_labels()
	await test_confirm_button_emits_confirmed_and_hides()
	await test_cancel_button_emits_cancelled_and_hides()
	await test_confirm_does_not_emit_cancelled()


# ── Helpers ─────────────────────────────────────────────────────────

class SignalRecorder:
	var count: int = 0
	func record() -> void:
		count += 1


func _make_dialog() -> ConfirmDialog:
	var dialog := ConfirmDialog.new()
	add_child(dialog)  # triggers _ready → builds UI, starts hidden
	return dialog


# Buttons now fade out on dismiss (visible flips false on the tween callback),
# so visibility assertions wait out the frosted-overlay fade.
func _await_fade() -> void:
	await get_tree().create_timer(ThemeProvider.theme.overlay_blur_fade_duration + 0.1).timeout


# ── Tests ───────────────────────────────────────────────────────────

func test_show_confirm_populates_text_and_shows() -> void:
	print("test_show_confirm_populates_text_and_shows")
	var dialog := _make_dialog()
	assert_false(dialog.visible, "dialog starts hidden")

	dialog.show_confirm("Restart this challenge?", "Restart", "Cancel")

	assert_equal(dialog._label.text, "Restart this challenge?", "message text set")
	assert_equal(dialog._confirm_button.title_text, "Restart", "confirm label set")
	assert_equal(dialog._cancel_button.title_text, "Cancel", "cancel label set")
	assert_true(dialog.visible, "dialog shown after show_confirm")

	dialog.queue_free()


func test_default_button_labels() -> void:
	print("test_default_button_labels")
	var dialog := _make_dialog()
	dialog.show_confirm("Are you sure?")
	assert_equal(dialog._confirm_button.title_text, "Confirm", "default confirm label")
	assert_equal(dialog._cancel_button.title_text, "Cancel", "default cancel label")
	dialog.queue_free()


func test_confirm_button_emits_confirmed_and_hides() -> void:
	print("test_confirm_button_emits_confirmed_and_hides")
	var dialog := _make_dialog()
	var rec := SignalRecorder.new()
	dialog.confirmed.connect(rec.record)

	dialog.show_confirm("msg")
	dialog._confirm_button.main_pressed.emit()

	assert_equal(rec.count, 1, "confirmed emitted exactly once")
	await _await_fade()
	assert_false(dialog.visible, "dialog hidden after confirm fades out")
	dialog.queue_free()


func test_cancel_button_emits_cancelled_and_hides() -> void:
	print("test_cancel_button_emits_cancelled_and_hides")
	var dialog := _make_dialog()
	var rec := SignalRecorder.new()
	dialog.cancelled.connect(rec.record)

	dialog.show_confirm("msg")
	dialog._cancel_button.main_pressed.emit()

	assert_equal(rec.count, 1, "cancelled emitted exactly once")
	await _await_fade()
	assert_false(dialog.visible, "dialog hidden after cancel fades out")
	dialog.queue_free()


func test_confirm_does_not_emit_cancelled() -> void:
	print("test_confirm_does_not_emit_cancelled")
	var dialog := _make_dialog()
	var confirmed_rec := SignalRecorder.new()
	var cancelled_rec := SignalRecorder.new()
	dialog.confirmed.connect(confirmed_rec.record)
	dialog.cancelled.connect(cancelled_rec.record)

	dialog.show_confirm("msg")
	dialog._confirm_button.main_pressed.emit()

	assert_equal(confirmed_rec.count, 1, "confirm fired")
	assert_equal(cancelled_rec.count, 0, "cancel must not fire on confirm")
	dialog.queue_free()
