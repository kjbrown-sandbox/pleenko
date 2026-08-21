extends "res://test/test_base.gd"

## Every manager's serialize() -> deserialize() must be lossless. Nothing
## enforced that before, so a field added to one side and forgotten on the other
## would silently drop a player's progress on their next load.
##
## Runs entirely in memory — no disk, no save file touched. Each test snapshots
## the manager's real state, round-trips a value through it, and restores.


func _run_tests() -> void:
	test_currency_round_trip()
	test_currency_serialize_covers_every_currency()
	test_prestige_round_trip()
	test_onboarding_round_trip()
	test_onboarding_peeked_boards_round_trip()
	test_challenge_progress_round_trip()
	test_deserialize_of_empty_dict_is_safe()


func test_currency_round_trip() -> void:
	print("test_currency_round_trip")
	var snapshot := CurrencyManager.serialize()

	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 137)
	var expected: int = CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN)
	var blob := CurrencyManager.serialize()

	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 999)
	CurrencyManager.deserialize(blob)
	assert_equal(CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN), expected,
		"gold balance survives serialize -> deserialize")

	CurrencyManager.deserialize(snapshot)


func test_currency_serialize_covers_every_currency() -> void:
	print("test_currency_serialize_covers_every_currency")
	# A new CurrencyType added to the enum but missed in serialize() would drop
	# that currency's balance on every load.
	var blob := CurrencyManager.serialize()
	for currency_type in Enums.CurrencyType.values():
		var key: String = Enums.CurrencyType.keys()[currency_type]
		assert_true(blob.has(key), "%s present in serialized currency" % key)
		var entry: Dictionary = blob[key]
		assert_true(entry.has("balance"), "%s has a balance" % key)
		assert_true(entry.has("cap"), "%s has a cap" % key)
		assert_true(entry.has("cap_raise_level"), "%s has a cap_raise_level" % key)


func test_prestige_round_trip() -> void:
	print("test_prestige_round_trip")
	var snapshot := PrestigeManager.serialize()

	PrestigeManager.trigger_prestige(Enums.BoardType.GOLD)
	PrestigeManager.claim_prestige(Enums.BoardType.GOLD)
	var blob := PrestigeManager.serialize()
	var expected_unlocked := PrestigeManager.is_board_unlocked_permanently(Enums.BoardType.GOLD)

	PrestigeManager.reset()
	PrestigeManager.deserialize(blob)
	assert_equal(PrestigeManager.is_board_unlocked_permanently(Enums.BoardType.GOLD),
		expected_unlocked, "prestige unlock survives serialize -> deserialize")

	PrestigeManager.reset()
	PrestigeManager.deserialize(snapshot)


func test_onboarding_round_trip() -> void:
	print("test_onboarding_round_trip")
	var snapshot := OnboardingProgress.serialize()

	OnboardingProgress.mark_challenges_peeked()
	OnboardingProgress.mark_autodropper_intro_seen()
	var blob := OnboardingProgress.serialize()

	OnboardingProgress.full_reset()
	assert_false(OnboardingProgress.has_peeked_challenges(), "full_reset clears the flag")

	OnboardingProgress.deserialize(blob)
	assert_true(OnboardingProgress.has_peeked_challenges(),
		"peeked_challenges survives serialize -> deserialize")
	assert_true(OnboardingProgress.has_seen_autodropper_intro(),
		"autodropper_intro_seen survives serialize -> deserialize")

	OnboardingProgress.full_reset()
	OnboardingProgress.deserialize(snapshot)


func test_onboarding_peeked_boards_round_trip() -> void:
	print("test_onboarding_peeked_boards_round_trip")
	# peeked_boards serializes as an int array rather than the live dictionary,
	# so the two sides can disagree without anything else noticing.
	var snapshot := OnboardingProgress.serialize()

	OnboardingProgress.full_reset()
	OnboardingProgress.mark_board_peeked(Enums.BoardType.ORANGE)
	var blob := OnboardingProgress.serialize()

	OnboardingProgress.full_reset()
	OnboardingProgress.deserialize(blob)
	assert_true(OnboardingProgress.has_peeked_board(Enums.BoardType.ORANGE),
		"peeked orange board survives the round trip")
	assert_false(OnboardingProgress.has_peeked_board(Enums.BoardType.RED),
		"an unpeeked board stays unpeeked")

	OnboardingProgress.full_reset()
	OnboardingProgress.deserialize(snapshot)


func test_challenge_progress_round_trip() -> void:
	print("test_challenge_progress_round_trip")
	var snapshot := ChallengeProgressManager.serialize()
	var blob := ChallengeProgressManager.serialize()

	ChallengeProgressManager.reset()
	ChallengeProgressManager.deserialize(blob)
	var after := ChallengeProgressManager.serialize()
	assert_equal(after.keys().size(), blob.keys().size(),
		"challenge progress keeps the same block shape across a round trip")

	ChallengeProgressManager.reset()
	ChallengeProgressManager.deserialize(snapshot)


func test_deserialize_of_empty_dict_is_safe() -> void:
	print("test_deserialize_of_empty_dict_is_safe")
	# A corrupt or truncated save reaches deserialize as {}. Every manager must
	# fall back to defaults rather than erroring — this is the load path for a
	# first-run player too.
	var currency := CurrencyManager.serialize()
	var prestige := PrestigeManager.serialize()
	var onboarding := OnboardingProgress.serialize()

	CurrencyManager.deserialize({})
	PrestigeManager.deserialize({})
	OnboardingProgress.deserialize({})
	assert_false(PrestigeManager.is_board_unlocked_permanently(Enums.BoardType.GOLD),
		"empty prestige blob -> nothing unlocked, no error")
	assert_false(OnboardingProgress.has_peeked_challenges(),
		"empty onboarding blob -> defaults, no error")

	CurrencyManager.deserialize(currency)
	PrestigeManager.deserialize(prestige)
	OnboardingProgress.deserialize(onboarding)
