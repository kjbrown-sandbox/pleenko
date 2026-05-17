extends "res://test/test_base.gd"

## Covers the FPS-cap performance setting:
##  - PerformanceSettings clamps unknown values to the default and applies
##    Engine.max_fps so a hand-edited / stale save can never run uncapped.
##  - The pref round-trips through SaveManager's main save AND survives a
##    prestige reset (it lives in the minimal save like the audio prefs).


func _read_save() -> Dictionary:
	var path: String = SaveManager.SAVE_PATH
	assert_true(FileAccess.file_exists(path), "save written to disk")
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(parsed is Dictionary, "save is valid JSON object")
	return parsed if parsed is Dictionary else {}


func _run_tests() -> void:
	# --- PerformanceSettings: defaulting + clamping + live apply ---
	assert_equal(PerformanceSettings.DEFAULT_MAX_FPS, 120, "default cap is 120")
	assert_equal(PerformanceSettings.FPS_OPTIONS, [30, 60, 120, 144] as Array[int],
		"FPS options are 30/60/120/144")

	PerformanceSettings.set_max_fps(60)
	assert_equal(PerformanceSettings.get_max_fps(), 60, "valid value (60) stored")
	assert_equal(Engine.max_fps, 60, "Engine.max_fps applied for 60")

	PerformanceSettings.set_max_fps(30)
	assert_equal(Engine.max_fps, 30, "Engine.max_fps applied for 30")

	PerformanceSettings.set_max_fps(999)
	assert_equal(PerformanceSettings.get_max_fps(), PerformanceSettings.DEFAULT_MAX_FPS,
		"unknown value falls back to default")
	assert_equal(Engine.max_fps, PerformanceSettings.DEFAULT_MAX_FPS,
		"Engine.max_fps applied for fallback")

	PerformanceSettings.set_max_fps(0)
	assert_equal(PerformanceSettings.get_max_fps(), PerformanceSettings.DEFAULT_MAX_FPS,
		"0 (would be uncapped) falls back to default, never uncapped")

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
	# as test_save_audio_prefs_survive_reset.)
	PerformanceSettings.set_max_fps(144)
	SaveManager.reset_game_without_reload()
	assert_equal(int(_read_save().get("max_fps", -1)), 144,
		"max_fps preserved in reset minimal save")

	PerformanceSettings.set_max_fps(30)
	SaveManager.reset_game_without_reload()
	assert_equal(int(_read_save().get("max_fps", -1)), 30,
		"a different cap also round-trips (not just defaulting)")

	# Restore the developer's original save (or remove the test artifact).
	if had_save:
		var wf := FileAccess.open(path, FileAccess.WRITE)
		wf.store_string(original)
		wf.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
