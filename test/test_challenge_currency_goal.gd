extends "res://test/test_base.gd"

## ChallengeTracker currency-goal completion tests.
##
## Regression guard for the bug where reaching an exact currency total from a
## non-coin-landing source (buying an upgrade, refining, etc.) failed to
## complete the challenge: the tracker only re-checked objectives on coin
## landings, never on currency_changed. _on_currency_changed now runs the same
## completion check, so any balance change that satisfies a CoinGoal completes.
##
## Drives the real CurrencyManager autoload + the tracker's real
## _on_currency_changed handler (wired exactly as connect_to_boards wires it),
## so the test exercises the production signal path. board_manager is null —
## CoinGoal objectives only read CurrencyManager, so no board is needed.
## Run with: godot --headless --scene res://test/test_challenge_currency_goal.tscn


func _run_tests() -> void:
	print("\n=== Challenge Currency Goal Tests ===\n")

	test_exact_goal_completes_when_balance_hits_target()
	test_exact_goal_does_not_complete_when_over_target()
	test_exact_goal_does_not_complete_when_under_target()
	test_at_least_goal_completes_on_currency_change()
	test_completion_fires_only_once()


# ── Helpers ─────────────────────────────────────────────────────────

# Counts `completed` emissions from a tracker.
class CompleteRecorder:
	var count: int = 0
	func record() -> void:
		count += 1


# Builds a tracker with a single CoinGoal objective and wires it to the real
# CurrencyManager.currency_changed signal — the exact connection production
# makes in connect_to_boards(). Caller frees via _teardown.
func _make_tracker(currency: Enums.CurrencyType, amount: int, exact: bool) -> ChallengeTracker:
	var goal := CoinGoal.new()
	goal.currency_type = currency
	goal.amount = amount
	goal.exact = exact

	var challenge := ChallengeData.new()
	challenge.objectives = [goal]

	var tracker := ChallengeTracker.new()
	tracker.setup(challenge, null)
	CurrencyManager.currency_changed.connect(tracker._on_currency_changed)
	return tracker


func _teardown(tracker: ChallengeTracker) -> void:
	if CurrencyManager.currency_changed.is_connected(tracker._on_currency_changed):
		CurrencyManager.currency_changed.disconnect(tracker._on_currency_changed)
	tracker.free()


# Sets a balance + a comfortable cap directly, no signal emitted. Used to stage
# a starting balance before the tracker is listening.
func _stage_balance(currency: Enums.CurrencyType, balance: int) -> void:
	CurrencyManager.caps[currency] = 1_000_000
	CurrencyManager.balances[currency] = balance


# ── Tests ───────────────────────────────────────────────────────────

func test_exact_goal_completes_when_balance_hits_target() -> void:
	print("test_exact_goal_completes_when_balance_hits_target")
	# The reported bug: 51 gold, goal is exactly 50, spend 1 → exactly 50.
	_stage_balance(Enums.CurrencyType.GOLD_COIN, 51)
	var tracker := _make_tracker(Enums.CurrencyType.GOLD_COIN, 50, true)
	var rec := CompleteRecorder.new()
	tracker.completed.connect(rec.record)

	CurrencyManager.spend(Enums.CurrencyType.GOLD_COIN, 1)  # 51 → 50, exact hit

	assert_equal(rec.count, 1, "challenge completes when balance reaches the exact target")
	_teardown(tracker)


func test_exact_goal_does_not_complete_when_over_target() -> void:
	print("test_exact_goal_does_not_complete_when_over_target")
	_stage_balance(Enums.CurrencyType.GOLD_COIN, 49)
	var tracker := _make_tracker(Enums.CurrencyType.GOLD_COIN, 50, true)
	var rec := CompleteRecorder.new()
	tracker.completed.connect(rec.record)

	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 2)  # 49 → 51, overshoots exact

	assert_equal(rec.count, 0, "exact goal does not complete when balance overshoots the target")
	_teardown(tracker)


func test_exact_goal_does_not_complete_when_under_target() -> void:
	print("test_exact_goal_does_not_complete_when_under_target")
	_stage_balance(Enums.CurrencyType.GOLD_COIN, 10)
	var tracker := _make_tracker(Enums.CurrencyType.GOLD_COIN, 50, true)
	var rec := CompleteRecorder.new()
	tracker.completed.connect(rec.record)

	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 5)  # 10 → 15, still short

	assert_equal(rec.count, 0, "exact goal does not complete while balance is under the target")
	_teardown(tracker)


func test_at_least_goal_completes_on_currency_change() -> void:
	print("test_at_least_goal_completes_on_currency_change")
	# Non-exact (>=) goal reached via a currency change with no coin landing.
	_stage_balance(Enums.CurrencyType.GOLD_COIN, 40)
	var tracker := _make_tracker(Enums.CurrencyType.GOLD_COIN, 50, false)
	var rec := CompleteRecorder.new()
	tracker.completed.connect(rec.record)

	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 15)  # 40 → 55, meets >= 50

	assert_equal(rec.count, 1, "at-least goal completes once balance crosses the target")
	_teardown(tracker)


func test_completion_fires_only_once() -> void:
	print("test_completion_fires_only_once")
	# Once completed, further currency changes must not re-emit (the _has_completed
	# guard keeps repeat completion checks idempotent).
	_stage_balance(Enums.CurrencyType.GOLD_COIN, 49)
	var tracker := _make_tracker(Enums.CurrencyType.GOLD_COIN, 50, false)
	var rec := CompleteRecorder.new()
	tracker.completed.connect(rec.record)

	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 1)  # 49 → 50, completes
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, 5)  # 50 → 55, must not re-complete

	assert_equal(rec.count, 1, "completed emits exactly once across multiple qualifying changes")
	_teardown(tracker)
