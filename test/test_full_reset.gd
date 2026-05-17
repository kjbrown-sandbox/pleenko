extends "res://test/test_base.gd"

## Covers SaveManager.full_reset() — the "Reset Game" main-menu option.
## Unlike the prestige-preserving reset_game(), a full reset must wipe ALL
## progress (prestige counts, challenge progress incl. unlocks, every
## onboarding flag) while still preserving audio/device preferences and
## leaving NO progress blocks on disk.


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

	# --- Populate persistent progress that normally survives a prestige reset ---
	PrestigeManager.deserialize({"ORANGE": 1})
	ChallengeProgressManager.deserialize({
		"states": {"some_challenge": ChallengeProgressManager.ChallengeState.COMPLETED},
		"unlocks": [ChallengeRewardData.UnlockType.HOLD_TO_DROP],
		"challenges_ever_visited": true,
	})
	OnboardingProgress.mark_autodropper_intro_seen()
	OnboardingProgress.mark_deflector_placed()
	OnboardingProgress.mark_challenges_peeked()
	OnboardingProgress.mark_board_peeked(Enums.BoardType.ORANGE)

	# Sanity: state is actually set before the wipe.
	assert_true(PrestigeManager.is_board_unlocked_permanently(Enums.BoardType.ORANGE),
		"prestige count set before reset")
	assert_equal(ChallengeProgressManager.get_state("some_challenge"),
		ChallengeProgressManager.ChallengeState.COMPLETED,
		"challenge marked completed before reset")
	assert_true(ChallengeProgressManager.is_unlocked(ChallengeRewardData.UnlockType.HOLD_TO_DROP),
		"challenge unlock set before reset")
	assert_true(OnboardingProgress.has_seen_autodropper_intro(),
		"autodropper intro seen before reset")
	assert_true(OnboardingProgress.has_placed_deflector(),
		"deflector placed before reset")

	# Audio/device prefs the wipe must preserve.
	AudioManager.set_muted(true)
	AudioManager.set_master_volume(42.0)

	# --- The wipe ---
	SaveManager.full_reset()

	# All progress cleared in memory.
	assert_false(PrestigeManager.is_board_unlocked_permanently(Enums.BoardType.ORANGE),
		"prestige count cleared after full reset")
	assert_equal(PrestigeManager.serialize().size(), 0,
		"prestige serialize empty after full reset")
	assert_equal(ChallengeProgressManager.get_state("some_challenge"),
		ChallengeProgressManager.ChallengeState.LOCKED,
		"challenge state cleared after full reset")
	assert_false(ChallengeProgressManager.is_unlocked(ChallengeRewardData.UnlockType.HOLD_TO_DROP),
		"challenge unlock cleared after full reset (deserialize would NOT clear this)")
	assert_false(ChallengeProgressManager.challenges_ever_visited,
		"challenges_ever_visited cleared after full reset")
	assert_false(OnboardingProgress.has_seen_autodropper_intro(),
		"autodropper intro flag cleared after full reset")
	assert_false(OnboardingProgress.has_placed_deflector(),
		"permanent deflector flag cleared after full reset")
	assert_false(OnboardingProgress.has_peeked_challenges(),
		"peeked-challenges flag cleared after full reset")
	assert_false(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE),
		"peeked-board flag cleared after full reset")

	# Audio/device prefs preserved on disk; no progress blocks remain.
	var saved := _read_minimal_save()
	assert_equal(saved.get("audio_muted", false), true,
		"audio_muted preserved across full reset")
	assert_near(float(saved.get("master_volume", -1.0)), 42.0, 0.01,
		"master_volume preserved across full reset")
	assert_true(saved.has("vfx_settings"), "vfx_settings block written")
	assert_false(saved.has("prestige"), "no prestige block on disk after full reset")
	assert_false(saved.has("challenges"), "no challenges block on disk after full reset")
	assert_false(saved.has("onboarding"), "no onboarding block on disk after full reset")

	# Restore the developer's original save (or remove the test artifact).
	if had_save:
		var wf := FileAccess.open(path, FileAccess.WRITE)
		wf.store_string(original)
		wf.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
