extends "res://test/test_base.gd"

## LevelManager silent catch-up tests — run with:
##   godot --headless --scene res://test/test_level_manager.tscn
##
## Covers begin_silent_catch_up() / end_silent_catch_up(): bulk currency
## injection (challenge starting coins) must advance current_level WITHOUT
## firing the milestone explosion, and must reconcile the crossed levels'
## permanent rewards while skipping DROP_COINS coin-frenzy drops. Guards the
## regression path too: a live crossing with no catch-up still animates.

var _level_up_ready_count := 0
var _reconcile_rewards: Array = []


func _run_tests() -> void:
	print("\n=== LevelManager Silent Catch-Up Tests ===\n")

	LevelManager.level_up_ready.connect(_on_level_up_ready_probe)
	LevelManager.reconcile_reward.connect(_on_reconcile_probe)

	test_silent_catch_up_advances_level_without_vfx()
	test_silent_catch_up_reconciles_permanent_rewards()
	test_silent_catch_up_skips_coin_frenzy_drops()
	test_live_crossing_still_fires_vfx()

	LevelManager.level_up_ready.disconnect(_on_level_up_ready_probe)
	LevelManager.reconcile_reward.disconnect(_on_reconcile_probe)


func _on_level_up_ready_probe(_level: int, _level_data) -> void:
	_level_up_ready_count += 1


func _on_reconcile_probe(reward) -> void:
	_reconcile_rewards.append(reward)


## Fresh LevelManager state: level 0, empty queue, gold-only table (no prestige
## unlocks in a headless run), and zeroed probe counters.
func _reset() -> void:
	LevelManager.reset()
	LevelManager.rebuild_levels()
	_level_up_ready_count = 0
	_reconcile_rewards.clear()


# --- Test Cases ---

func test_silent_catch_up_advances_level_without_vfx() -> void:
	print("test_silent_catch_up_advances_level_without_vfx")
	_reset()
	var currency := LevelManager.get_active_currency()
	LevelManager.begin_silent_catch_up()
	# Simulate the currency_changed the bulk coin injection fires. Balance 35
	# crosses gold thresholds 7, 13, 35 → three levels.
	LevelManager._on_currency_changed(currency, 35, 999999)
	LevelManager.end_silent_catch_up()

	assert_equal(LevelManager.current_level, 3, "current_level advances past every crossed threshold")
	assert_equal(_level_up_ready_count, 0, "no level_up_ready emitted during silent catch-up")
	assert_false(LevelManager.has_pending_levels(), "no milestone animation queued")


func test_silent_catch_up_reconciles_permanent_rewards() -> void:
	print("test_silent_catch_up_reconciles_permanent_rewards")
	_reset()
	var currency := LevelManager.get_active_currency()
	LevelManager.begin_silent_catch_up()
	LevelManager._on_currency_changed(currency, 35, 999999)
	LevelManager.end_silent_catch_up()

	# Crossed levels 0/1/2 each grant one UNLOCK_UPGRADE (ADD_ROW, BUCKET_VALUE,
	# DROP_RATE) — reconciled silently so the player already owns them.
	assert_equal(_reconcile_rewards.size(), 3, "one reconcile per crossed permanent reward")
	var all_unlocks := true
	for reward in _reconcile_rewards:
		if reward.type != RewardData.RewardType.UNLOCK_UPGRADE:
			all_unlocks = false
	assert_true(all_unlocks, "reconciled rewards are permanent unlocks")


func test_silent_catch_up_skips_coin_frenzy_drops() -> void:
	print("test_silent_catch_up_skips_coin_frenzy_drops")
	_reset()
	var currency := LevelManager.get_active_currency()
	LevelManager.begin_silent_catch_up()
	# Balance 400 crosses into the coin-frenzy milestones (levels 5-8 grant
	# DROP_COINS). Those consumable drops must NOT replay on catch-up.
	LevelManager._on_currency_changed(currency, 400, 999999)
	LevelManager.end_silent_catch_up()

	assert_true(LevelManager.current_level >= 6, "advanced into the coin-frenzy milestone range")
	assert_true(_reconcile_rewards.size() > 0, "permanent rewards still reconciled")
	var has_drop_coins := false
	for reward in _reconcile_rewards:
		if reward.type == RewardData.RewardType.DROP_COINS:
			has_drop_coins = true
	assert_false(has_drop_coins, "coin-frenzy (DROP_COINS) rewards are not replayed — the drop just disappears")


func test_live_crossing_still_fires_vfx() -> void:
	print("test_live_crossing_still_fires_vfx")
	_reset()
	var currency := LevelManager.get_active_currency()
	# No begin_silent_catch_up: a normal in-game threshold crossing must still
	# queue the milestone animation.
	LevelManager._on_currency_changed(currency, 7, 999999)

	assert_equal(LevelManager.current_level, 1, "level advances on a live crossing")
	assert_equal(_level_up_ready_count, 1, "level_up_ready fires for a live threshold crossing")
	assert_true(LevelManager.has_pending_levels(), "a live crossing queues a pending level-up")
