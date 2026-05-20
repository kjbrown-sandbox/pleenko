extends "res://test/test_base.gd"

## Covers the window-mode performance setting:
##  - PerformanceSettings snaps unknown values to the default so a hand-edited /
##    stale save can never push the game into an unsupported window state.
##  - The setter does not crash under the headless display driver (the apply
##    path guards DisplayServer + window calls).
##  - The pref round-trips through SaveManager's main save AND survives a
##    prestige reset (it lives in the minimal save like the audio prefs and
##    max_fps).


func _read_save() -> Dictionary:
	var path: String = SaveManager.SAVE_PATH
	assert_true(FileAccess.file_exists(path), "save written to disk")
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(parsed is Dictionary, "save is valid JSON object")
	return parsed if parsed is Dictionary else {}


func _run_tests() -> void:
	# --- PerformanceSettings: defaulting + clamping + headless-safe apply ---
	assert_equal(PerformanceSettings.DEFAULT_WINDOW_MODE, Window.MODE_FULLSCREEN,
		"default window mode is fullscreen")
	assert_equal(PerformanceSettings.WINDOW_MODE_OPTIONS,
		[Window.MODE_WINDOWED, Window.MODE_FULLSCREEN] as Array[int],
		"window options are WINDOWED + FULLSCREEN")

	PerformanceSettings.set_window_mode(Window.MODE_WINDOWED)
	assert_equal(PerformanceSettings.get_window_mode(), Window.MODE_WINDOWED,
		"valid value (WINDOWED) stored")

	PerformanceSettings.set_window_mode(Window.MODE_FULLSCREEN)
	assert_equal(PerformanceSettings.get_window_mode(), Window.MODE_FULLSCREEN,
		"valid value (FULLSCREEN) stored")

	PerformanceSettings.set_window_mode(9999)
	assert_equal(PerformanceSettings.get_window_mode(),
		PerformanceSettings.DEFAULT_WINDOW_MODE,
		"unknown value falls back to default")

	# Window.MODE_EXCLUSIVE_FULLSCREEN is a real Godot constant but is NOT in
	# our offered options — should snap to the default rather than slip through.
	PerformanceSettings.set_window_mode(Window.MODE_EXCLUSIVE_FULLSCREEN)
	assert_equal(PerformanceSettings.get_window_mode(),
		PerformanceSettings.DEFAULT_WINDOW_MODE,
		"unsupported real Window.MODE_* still snaps to default")

	# Back up any real developer save so the test does not destroy it.
	var path: String = SaveManager.SAVE_PATH
	var had_save := FileAccess.file_exists(path)
	var original := ""
	if had_save:
		var bf := FileAccess.open(path, FileAccess.READ)
		original = bf.get_as_text()
		bf.close()

	# --- pref survives a prestige reset (lives in the minimal save) ---
	# reset_game and reset_game_without_reload build the identical minimal save,
	# so exercising the no-reload variant covers both. (save_game() needs a live
	# BoardManager, so the headless test only drives the reset path — same scope
	# as test_save_audio_prefs_survive_reset and test_performance_settings.)
	PerformanceSettings.set_window_mode(Window.MODE_WINDOWED)
	SaveManager.reset_game_without_reload()
	assert_equal(int(_read_save().get("window_mode", -1)), Window.MODE_WINDOWED,
		"window_mode=WINDOWED preserved in reset minimal save")

	PerformanceSettings.set_window_mode(Window.MODE_FULLSCREEN)
	SaveManager.reset_game_without_reload()
	assert_equal(int(_read_save().get("window_mode", -1)), Window.MODE_FULLSCREEN,
		"a different mode also round-trips (not just defaulting)")

	# Restore the developer's original save (or remove the test artifact).
	if had_save:
		var wf := FileAccess.open(path, FileAccess.WRITE)
		wf.store_string(original)
		wf.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
