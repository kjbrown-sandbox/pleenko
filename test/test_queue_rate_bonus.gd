extends "res://test/test_base.gd"

## Queue rate bonus tests — run with:
##   godot --headless --scene res://test/test_queue_rate_bonus.tscn
##
## Verifies the math behind get_effective_drop_delay() (the first queued coin is
## "free" — only EXTRA coins boost the rate) and the proportional timer rescale
## that fires when the queue's full count changes mid-cycle.


func _run_tests() -> void:
	print("\n=== Queue Rate Bonus Tests ===\n")

	test_effective_delay_zero_coins()
	test_effective_delay_one_coin_is_free()
	test_effective_delay_six_coins_five_extra()
	test_effective_delay_eleven_coins_doubles_rate()
	test_effective_delay_one_hundred_coins_never_zero()
	test_effective_delay_with_null_queue()
	test_rescale_proportional_grow()
	test_rescale_proportional_shrink()


# --- Helpers ---

## Pure math mirror of get_effective_drop_delay: the always-present first slot is
## "free", so only EXTRA coins (max(0, count-1)) boost the rate:
##   effective = base / (1 + bonus * max(0, count - 1))
func _effective(base_delay: float, bonus_per_coin: float, full_count: int) -> float:
	var extra: int = maxi(0, full_count - 1)
	return base_delay / (1.0 + bonus_per_coin * float(extra))


# --- Effective delay math ---

func test_effective_delay_zero_coins() -> void:
	print("test_effective_delay_zero_coins")
	# 0 coins → unchanged (0 extra).
	assert_near(_effective(1.5, 0.10, 0), 1.5, 0.0001, "0 coins gives base delay")


func test_effective_delay_one_coin_is_free() -> void:
	print("test_effective_delay_one_coin_is_free")
	# 1 coin → still base delay; the first slot doesn't count (0 extra).
	assert_near(_effective(1.5, 0.10, 1), 1.5, 0.0001, "first queued coin is free")


func test_effective_delay_six_coins_five_extra() -> void:
	print("test_effective_delay_six_coins_five_extra")
	# 6 coins → 5 extra → 1.5 / 1.5 = 1.0 (50% rate boost).
	assert_near(_effective(1.5, 0.10, 6), 1.0, 0.0001, "6 coins: 1.5/(1+0.5)")


func test_effective_delay_eleven_coins_doubles_rate() -> void:
	print("test_effective_delay_eleven_coins_doubles_rate")
	# 11 coins → 10 extra → 100% rate boost = half the delay.
	assert_near(_effective(1.5, 0.10, 11), 0.75, 0.0001, "11 coins: half delay")


func test_effective_delay_one_hundred_coins_never_zero() -> void:
	print("test_effective_delay_one_hundred_coins_never_zero")
	# 100 coins → 99 extra → 1.5 / 10.9 (still positive, never zero).
	var v: float = _effective(1.5, 0.10, 100)
	assert_true(v > 0.0, "100 coins: delay still positive")
	assert_near(v, 1.5 / 10.9, 0.0001, "100 coins: 1.5/10.9")


func test_effective_delay_with_null_queue() -> void:
	print("test_effective_delay_with_null_queue")
	# When coin_queue is null, get_effective_drop_delay returns drop_delay unchanged.
	var board := PlinkoBoard.new()
	board.drop_delay = 1.5
	# coin_queue is null because the node has no scene tree / @onready hasn't fired
	assert_near(board.get_effective_drop_delay(), 1.5, 0.0001, "null queue → base delay")
	board.free()


# --- Mid-cycle rescale math ---
# Mirrors PlinkoBoard._on_queue_count_changed:
#   _drop_timer_remaining *= new_effective / _last_effective_delay

func test_rescale_proportional_grow() -> void:
	print("test_rescale_proportional_grow")
	# Player is 33% through a 1.5s timer when the queue grows to 6 coins
	# (effective 1.0s). Remaining (1.0s) rescales to (1.0 / 1.5) * 1.0 ≈ 0.6667.
	var remaining: float = 1.0
	var last_effective: float = 1.5
	var new_effective: float = _effective(1.5, 0.10, 6)  # 1.0
	remaining *= new_effective / last_effective
	assert_near(remaining, 1.0 * (1.0 / 1.5), 0.0001, "33% progress preserved on grow")


func test_rescale_proportional_shrink() -> void:
	print("test_rescale_proportional_shrink")
	# Player at 50% of a 1.0s effective (6 coins) when the queue drains to 0
	# (effective 1.5s). Remaining (0.5s) rescales to (1.5 / 1.0) * 0.5 = 0.75s.
	var remaining: float = 0.5
	var last_effective: float = 1.0
	var new_effective: float = _effective(1.5, 0.10, 0)  # 1.5
	remaining *= new_effective / last_effective
	assert_near(remaining, 0.75, 0.0001, "50% progress preserved on shrink")
