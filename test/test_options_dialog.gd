extends "res://test/test_base.gd"

## OptionsDialog "Exit challenge" tests — run with:
##   godot --headless --scene res://test/test_options_dialog.tscn
##
## The IN_GAME footer grows an "Exit challenge" button only while a challenge is
## active; pressing it hides the dialog and emits exit_challenge_requested up to
## the parent (Main), which owns the teardown.
##
## The IN_GAME footer also carries a "Quit game" button (absent in MAIN_MENU,
## which has its own Quit) that saves before quitting via the injectable
## `_quit_fn` seam.


func _run_tests() -> void:
	print("\n=== OptionsDialog Exit-Challenge Tests ===\n")

	test_exit_button_present_during_challenge()
	test_exit_button_absent_outside_challenge()
	test_exit_button_absent_in_main_menu_context()
	await test_exit_button_emits_and_hides()

	test_quit_button_present_in_game()
	test_quit_button_absent_in_main_menu_context()
	test_quit_calls_quit_fn_outside_challenge()
	test_quit_calls_quit_fn_during_challenge()


# ── Helpers ─────────────────────────────────────────────────────────

class SignalRecorder:
	var count: int = 0
	func record() -> void:
		count += 1


func _make_dialog(context: OptionsDialog.Context) -> OptionsDialog:
	var dialog := OptionsDialog.new()
	dialog.context = context  # must be set before add_child → _ready builds UI
	add_child(dialog)
	return dialog


func _find_button(dialog: OptionsDialog, label: String) -> RefinedBaselineButton:
	for child in dialog._panel.get_children():
		if child is RefinedBaselineButton and child.title_text == label:
			return child
	return null


# Footer buttons fade out on dismiss (visible flips false on the tween callback).
func _await_fade() -> void:
	await get_tree().create_timer(ThemeProvider.theme.overlay_blur_fade_duration + 0.1).timeout


# ── Tests ───────────────────────────────────────────────────────────

func test_exit_button_present_during_challenge() -> void:
	print("test_exit_button_present_during_challenge")
	ChallengeManager.set_challenge(ChallengeData.new())
	var dialog := _make_dialog(OptionsDialog.Context.IN_GAME)
	assert_true(_find_button(dialog, "Exit challenge") != null,
		"Exit Challenge button built while a challenge is active")
	dialog.queue_free()
	ChallengeManager.clear_challenge()


func test_exit_button_absent_outside_challenge() -> void:
	print("test_exit_button_absent_outside_challenge")
	ChallengeManager.clear_challenge()
	var dialog := _make_dialog(OptionsDialog.Context.IN_GAME)
	assert_true(_find_button(dialog, "Exit challenge") == null,
		"Exit Challenge button absent on the normal board")
	dialog.queue_free()


func test_exit_button_absent_in_main_menu_context() -> void:
	print("test_exit_button_absent_in_main_menu_context")
	# Even with a (hypothetical) active challenge, the MAIN_MENU footer never
	# constructs in-game nav — the exit button is IN_GAME only.
	ChallengeManager.set_challenge(ChallengeData.new())
	var dialog := _make_dialog(OptionsDialog.Context.MAIN_MENU)
	assert_true(_find_button(dialog, "Exit challenge") == null,
		"Exit Challenge button never appears in MAIN_MENU context")
	dialog.queue_free()
	ChallengeManager.clear_challenge()


func test_exit_button_emits_and_hides() -> void:
	print("test_exit_button_emits_and_hides")
	ChallengeManager.set_challenge(ChallengeData.new())
	var dialog := _make_dialog(OptionsDialog.Context.IN_GAME)
	var rec := SignalRecorder.new()
	dialog.exit_challenge_requested.connect(rec.record)

	var button := _find_button(dialog, "Exit challenge")
	assert_true(button != null, "exit button exists")
	button.main_pressed.emit()

	assert_equal(rec.count, 1, "exit_challenge_requested emitted once")
	await _await_fade()
	assert_false(dialog.visible, "dialog hidden after exit fades out")
	dialog.queue_free()
	ChallengeManager.clear_challenge()


# ── Quit-game tests ─────────────────────────────────────────────────

func test_quit_button_present_in_game() -> void:
	print("test_quit_button_present_in_game")
	ChallengeManager.clear_challenge()
	var dialog := _make_dialog(OptionsDialog.Context.IN_GAME)
	assert_true(_find_button(dialog, "Quit game") != null,
		"Quit game button built in the IN_GAME footer")
	dialog.queue_free()


func test_quit_button_absent_in_main_menu_context() -> void:
	print("test_quit_button_absent_in_main_menu_context")
	# MAIN_MENU has its own Quit — the dialog's Quit is IN_GAME only.
	var dialog := _make_dialog(OptionsDialog.Context.MAIN_MENU)
	assert_true(_find_button(dialog, "Quit game") == null,
		"Quit game button never appears in MAIN_MENU context")
	dialog.queue_free()


func test_quit_calls_quit_fn_outside_challenge() -> void:
	print("test_quit_calls_quit_fn_outside_challenge")
	ChallengeManager.clear_challenge()
	var dialog := _make_dialog(OptionsDialog.Context.IN_GAME)
	# save_game() is a safe no-op here (no board manager registered); we only
	# assert the quit seam fires so the headless run can't actually exit.
	var quit_calls := [0]
	dialog._quit_fn = func() -> void: quit_calls[0] += 1

	var button := _find_button(dialog, "Quit game")
	assert_true(button != null, "quit button exists")
	button.main_pressed.emit()

	assert_equal(quit_calls[0], 1, "quit_fn called once outside a challenge")
	dialog.queue_free()


func test_quit_calls_quit_fn_during_challenge() -> void:
	print("test_quit_calls_quit_fn_during_challenge")
	ChallengeManager.set_challenge(ChallengeData.new())
	var dialog := _make_dialog(OptionsDialog.Context.IN_GAME)
	var quit_calls := [0]
	dialog._quit_fn = func() -> void: quit_calls[0] += 1

	var button := _find_button(dialog, "Quit game")
	assert_true(button != null, "quit button exists mid-challenge")
	button.main_pressed.emit()

	assert_equal(quit_calls[0], 1, "quit_fn called once during a challenge")
	dialog.queue_free()
	ChallengeManager.clear_challenge()
