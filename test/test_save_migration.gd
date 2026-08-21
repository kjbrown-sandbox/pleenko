extends "res://test/test_base.gd"

## Covers SaveManager._migrate(): a pure (Dictionary, int) -> Dictionary that
## every existing player's save passes through on load. A mistake here bricks
## saves in the field, and nothing exercised it before.
##
## One fixture per starting version, so each migration step is checked both on
## its own and as part of the full v1 -> current chain.


## A v1-shaped save: the oldest format, before prestige/challenges/onboarding.
func _v1_save() -> Dictionary:
	return {
		"version": 1,
		"currency": {"balances": {"0": 500}},
		"level": {"current_level": 12},
		"upgrades": {},
		"boards": {
			"board_types": [
				Enums.BoardType.GOLD,
				Enums.BoardType.ORANGE,
			],
			"normal_autodroppers_unlocked": true,
		},
	}


func _run_tests() -> void:
	test_sets_current_version()
	test_v1_seeds_prestige_and_challenges()
	test_v5_seeds_peeked_boards_excluding_gold()
	test_v5_seeds_peeked_challenges_from_visited()
	test_v6_seeds_autodropper_intro_when_unlocked()
	test_v6_leaves_autodropper_intro_unseen_when_locked()
	test_v7_seeds_revealed_milestone_tiers()
	test_v7_tiers_cover_current_level()
	test_migrating_current_version_is_identity()
	test_migration_preserves_unrelated_blocks()
	test_empty_save_survives_full_chain()


func test_sets_current_version() -> void:
	print("test_sets_current_version")
	var out := SaveManager._migrate(_v1_save(), 1)
	assert_equal(out["version"], SaveManager.SAVE_VERSION,
		"migrated save is stamped with the current version")


func test_v1_seeds_prestige_and_challenges() -> void:
	print("test_v1_seeds_prestige_and_challenges")
	var out := SaveManager._migrate(_v1_save(), 1)
	assert_true(out.has("prestige"), "v1 -> v2 seeds a prestige block")
	assert_true(out.has("challenges"), "v3 -> v4 seeds a challenges block")


func test_v5_seeds_peeked_boards_excluding_gold() -> void:
	print("test_v5_seeds_peeked_boards_excluding_gold")
	# A player who already owns orange must not be re-peeked at it. Gold is the
	# starting board and never peeks, so it is deliberately excluded.
	var out := SaveManager._migrate(_v1_save(), 4)
	var onboarding: Dictionary = out.get("onboarding", {})
	var peeked: Array = onboarding.get("peeked_boards", [])
	assert_true(peeked.has(Enums.BoardType.ORANGE), "owned orange board marked peeked")
	assert_false(peeked.has(Enums.BoardType.GOLD), "gold excluded — it never peeks")


func test_v5_seeds_peeked_challenges_from_visited() -> void:
	print("test_v5_seeds_peeked_challenges_from_visited")
	var visited := _v1_save()
	visited["challenges"] = {"challenges_ever_visited": true}
	var out := SaveManager._migrate(visited, 4)
	assert_equal(out["onboarding"]["peeked_challenges"], true,
		"a player who visited challenges is not re-peeked")

	var unvisited := _v1_save()
	unvisited["challenges"] = {"challenges_ever_visited": false}
	var out2 := SaveManager._migrate(unvisited, 4)
	assert_equal(out2["onboarding"]["peeked_challenges"], false,
		"a player who never visited challenges still gets the peek")


func test_v6_seeds_autodropper_intro_when_unlocked() -> void:
	print("test_v6_seeds_autodropper_intro_when_unlocked")
	var out := SaveManager._migrate(_v1_save(), 5)
	assert_equal(out["onboarding"].get("autodropper_intro_seen", false), true,
		"autodropper already unlocked -> intro marked seen")


func test_v6_leaves_autodropper_intro_unseen_when_locked() -> void:
	print("test_v6_leaves_autodropper_intro_unseen_when_locked")
	var locked := _v1_save()
	locked["boards"]["normal_autodroppers_unlocked"] = false
	var out := SaveManager._migrate(locked, 5)
	assert_false(out["onboarding"].get("autodropper_intro_seen", false),
		"autodropper still locked -> intro will play when they buy it")


func test_v7_seeds_revealed_milestone_tiers() -> void:
	print("test_v7_seeds_revealed_milestone_tiers")
	var out := SaveManager._migrate(_v1_save(), 6)
	var tiers: Array = out["onboarding"].get("revealed_milestone_tiers", [])
	assert_true(tiers.has(0), "tier 0 always revealed")
	assert_false(tiers.is_empty(), "at least one tier seeded")


func test_v7_tiers_cover_current_level() -> void:
	print("test_v7_tiers_cover_current_level")
	# Every tier start at or below current_level must be marked revealed, so a
	# mid-game player doesn't replay the bar reveal for tiers already passed.
	var save := _v1_save()
	save["level"] = {"current_level": 12}
	var out := SaveManager._migrate(save, 6)
	var tiers: Array = out["onboarding"]["revealed_milestone_tiers"]
	var expected_start: int = 0
	while expected_start <= 12:
		assert_true(tiers.has(expected_start),
			"tier start %d revealed for level 12" % expected_start)
		expected_start += LevelManager.LEVELS_PER_TIER
	for tier in tiers:
		assert_true(int(tier) <= 12, "no tier beyond current_level seeded")


func test_migrating_current_version_is_identity() -> void:
	print("test_migrating_current_version_is_identity")
	# Loading an up-to-date save must not rewrite anything — every `if version <`
	# branch is skipped, so onboarding keeps exactly what the player had.
	var current := {
		"version": SaveManager.SAVE_VERSION,
		"level": {"current_level": 3},
		"boards": {"board_types": [Enums.BoardType.GOLD]},
		"onboarding": {"peeked_challenges": true, "autodropper_intro_seen": false},
	}
	var out := SaveManager._migrate(current, SaveManager.SAVE_VERSION)
	assert_equal(out["onboarding"]["peeked_challenges"], true,
		"existing onboarding untouched at current version")
	assert_equal(out["onboarding"]["autodropper_intro_seen"], false,
		"a false flag is not flipped by a no-op migration")


func test_migration_preserves_unrelated_blocks() -> void:
	print("test_migration_preserves_unrelated_blocks")
	# Migration must never drop blocks it doesn't understand.
	var save := _v1_save()
	save["currency"] = {"balances": {"0": 500}}
	var out := SaveManager._migrate(save, 1)
	assert_true(out.has("currency"), "currency block survives the chain")
	assert_equal(out["currency"]["balances"]["0"], 500, "currency values unchanged")
	assert_true(out.has("upgrades"), "upgrades block survives the chain")
	assert_equal(int(out["level"]["current_level"]), 12, "level block unchanged")


func test_empty_save_survives_full_chain() -> void:
	print("test_empty_save_survives_full_chain")
	# A truncated or corrupt-but-parseable save must migrate without erroring —
	# every step reads through .get() defaults.
	var out := SaveManager._migrate({}, 1)
	assert_equal(out["version"], SaveManager.SAVE_VERSION, "empty save still versioned")
	assert_true(out.has("onboarding"), "onboarding seeded from nothing")
	assert_true(out.has("prestige"), "prestige seeded from nothing")
