extends "res://test/test_base.gd"

## Reset-broadcast tests — run with:
##   godot --headless --scene res://test/test_reset_broadcasts.tscn
##
## Guards the challenge-entry "out of sync" fix: reset() on the managers is
## silent (unlike deserialize, which broadcasts), so CurrencyManager.notify_all()
## and SaveManager.reset_state() must re-broadcast the cleared state. Without it
## the level bar + currency HUD keep painting the previous session's tier/balances
## on challenge entry until the first in-challenge currency_changed.


func _run_tests() -> void:
	print("\n=== Reset Broadcast Tests ===\n")

	test_notify_all_emits_every_currency()
	test_notify_all_reflects_live_values()
	test_reset_state_broadcasts_currency()
	test_reset_state_broadcasts_level_changed()


func test_notify_all_emits_every_currency() -> void:
	print("test_notify_all_emits_every_currency")
	CurrencyManager.reset()
	var seen := {}
	var probe := func(type, _bal, _cap): seen[type] = true
	CurrencyManager.currency_changed.connect(probe)
	CurrencyManager.notify_all()
	CurrencyManager.currency_changed.disconnect(probe)
	assert_equal(seen.size(), Enums.CurrencyType.values().size(),
		"notify_all should emit currency_changed once per currency type")


func test_notify_all_reflects_live_values() -> void:
	print("test_notify_all_reflects_live_values")
	CurrencyManager.reset()
	var captured := {}
	var probe := func(type, bal, cap): captured[type] = [bal, cap]
	CurrencyManager.currency_changed.connect(probe)
	CurrencyManager.notify_all()
	CurrencyManager.currency_changed.disconnect(probe)
	var gold := Enums.CurrencyType.GOLD_COIN
	assert_equal(captured[gold][0], CurrencyManager.get_balance(gold),
		"notify_all should broadcast the live balance")
	assert_equal(captured[gold][1], CurrencyManager.get_cap(gold),
		"notify_all should broadcast the live cap")


func test_reset_state_broadcasts_currency() -> void:
	print("test_reset_state_broadcasts_currency")
	# Dirty the balance so the reset has something to clear.
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 500)
	var seen := {}
	var probe := func(type, bal, _cap): seen[type] = bal
	CurrencyManager.currency_changed.connect(probe)
	SaveManager.reset_state()
	CurrencyManager.currency_changed.disconnect(probe)
	assert_equal(seen.size(), Enums.CurrencyType.values().size(),
		"reset_state should re-broadcast every currency")
	# reset() seeds the starting tier with 1 gold — the broadcast must carry the
	# cleared value, not the pre-reset 501.
	assert_equal(seen.get(Enums.CurrencyType.GOLD_COIN), 1,
		"reset_state broadcast should carry the cleared gold balance")


func test_reset_state_broadcasts_level_changed() -> void:
	print("test_reset_state_broadcasts_level_changed")
	var captured := [false, -1]  # [emitted, level]
	var probe := func(level):
		captured[0] = true
		captured[1] = level
	LevelManager.level_changed.connect(probe)
	SaveManager.reset_state()
	LevelManager.level_changed.disconnect(probe)
	assert_true(captured[0], "reset_state should emit level_changed")
	assert_equal(captured[1], 0, "reset_state should broadcast level 0 after reset")
