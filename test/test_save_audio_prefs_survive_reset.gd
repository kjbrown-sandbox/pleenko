extends "res://test/test_base.gd"

## Regression: prestige (reset_game / reset_game_without_reload) must preserve
## the player's audio preferences. The minimal save written on reset previously
## dropped the audio block, so on reload `audio_muted` defaulted back to false
## and a muted player got sound again. master_volume / vfx_settings shared the
## same bug. reset_game and reset_game_without_reload build the identical minimal
## save, so exercising the no-reload variant covers both.


func _read_minimal_save() -> Dictionary:
	var path: String = SaveManager.SAVE_PATH
	assert_true(FileAccess.file_exists(path), "minimal save written to disk")
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(parsed is Dictionary, "minimal save is valid JSON object")
	return parsed if parsed is Dictionary else {}


func _run_tests() -> void:
	# Back up any real developer save so the test does not destroy it.
	var path: String = SaveManager.SAVE_PATH
	var had_save := FileAccess.file_exists(path)
	var original := ""
	if had_save:
		var bf := FileAccess.open(path, FileAccess.READ)
		original = bf.get_as_text()
		bf.close()

	# --- muted == true survives reset ---
	AudioManager.set_muted(true)
	AudioManager.set_master_volume(37.0)
	SaveManager.reset_game_without_reload()

	var saved_muted := _read_minimal_save()
	assert_equal(saved_muted.get("audio_muted", false), true,
		"audio_muted=true preserved in minimal save")
	assert_near(float(saved_muted.get("master_volume", -1.0)), 37.0, 0.01,
		"master_volume preserved in minimal save")
	assert_true(saved_muted.has("vfx_settings"),
		"vfx_settings block written to minimal save")

	# --- muted == false also round-trips (not just defaulting) ---
	AudioManager.set_muted(false)
	SaveManager.reset_game_without_reload()

	var saved_unmuted := _read_minimal_save()
	assert_equal(saved_unmuted.get("audio_muted", true), false,
		"audio_muted=false preserved in minimal save")

	# Restore the developer's original save (or remove the test artifact).
	if had_save:
		var wf := FileAccess.open(path, FileAccess.WRITE)
		wf.store_string(original)
		wf.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
