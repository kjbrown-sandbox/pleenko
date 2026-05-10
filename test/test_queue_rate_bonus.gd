extends "res://test/test_base.gd"

## Queue rate bonus tests — run with:
##   godot --headless --scene res://test/test_queue_rate_bonus.tscn
##
## Verifies the math behind get_effective_drop_delay() and the proportional
## timer rescale that fires when the queue's full count changes mid-cycle.


func _run_tests() -> void:
	print("\n=== Queue Rate Bonus Tests ===\n")

	test_effective_delay_zero_full_coins()
	test_effective_delay_one_full_coin()
	test_effective_delay_five_full_coins()
	test_effective_delay_ten_full_coins_doubles_rate()
	test_effective_delay_one_hundred_full_coins_never_zero()
	test_effective_delay_with_null_queue()
	test_rescale_proportional_grow()
	test_rescale_proportional_shrink()


# --- Helpers ---

## Pure math: effective = base / (1 + bonus * N)
func _effective(base_delay: float, bonus_per_coin: float, full_count: int) -> float:
	return base_delay / (1.0 + bonus_per_coin * float(full_count))


# --- Effective delay math ---

func test_effective_delay_zero_full_coins() -> void:
	print("test_effective_delay_zero_full_coins")
	# 0 coins → unchanged
	assert_near(_effective(1.5, 0.10, 0), 1.5, 0.0001, "0 coins gives base delay")


func test_effective_delay_one_full_coin() -> void:
	print("test_effective_delay_one_full_coin")
	# 1 coin → 1.5 / 1.1 ≈ 1.3636
	assert_near(_effective(1.5, 0.10, 1), 1.5 / 1.1, 0.0001, "1 coin: 1.5/1.1")


func test_effective_delay_five_full_coins() -> void:
	print("test_effective_delay_five_full_coins")
	# 5 coins → 1.5 / 1.5 = 1.0 (50% rate boost)
	assert_near(_effective(1.5, 0.10, 5), 1.0, 0.0001, "5 coins: 1.5/1.5 = 1.0")


func test_effective_delay_ten_full_coins_doubles_rate() -> void:
	print("test_effective_delay_ten_full_coins_doubles_rate")
	# 10 coins → 100% rate boost = half the delay
	assert_near(_effective(1.5, 0.10, 10), 0.75, 0.0001, "10 coins: half delay")


func test_effective_delay_one_hundred_full_coins_never_zero() -> void:
	print("test_effective_delay_one_hundred_full_coins_never_zero")
	# 100 coins → 1.5 / 11 ≈ 0.1364 (still positive, never zero)
	var v: float = _effective(1.5, 0.10, 100)
	assert_true(v > 0.0, "100 coins: delay still positive")
	assert_near(v, 1.5 / 11.0, 0.0001, "100 coins: 1.5/11")


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
	# Player is 33% through a 1.5s timer when queue grows to 5 coins (effective 1.0s).
	# Remaining (1.0s) should rescale to (1.0 / 1.5) * 1.0 ≈ 0.6667.
	var remaining: float = 1.0
	var last_effective: float = 1.5
	var new_effective: float = _effective(1.5, 0.10, 5)  # 1.0
	remaining *= new_effective / last_effective
	assert_near(remaining, 1.0 * (1.0 / 1.5), 0.0001, "33% progress preserved on grow")


func test_rescale_proportional_shrink() -> void:
	print("test_rescale_proportional_shrink")
	# Player at 50% of a 1.0s effective (5 coins) when queue drains to 0 (effective 1.5s).
	# Remaining (0.5s) should rescale to (1.5 / 1.0) * 0.5 = 0.75s.
	var remaining: float = 0.5
	var last_effective: float = 1.0
	var new_effective: float = _effective(1.5, 0.10, 0)  # 1.5
	remaining *= new_effective / last_effective
	assert_near(remaining, 0.75, 0.0001, "50% progress preserved on shrink")
