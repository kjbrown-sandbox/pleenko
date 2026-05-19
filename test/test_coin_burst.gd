extends "res://test/test_base.gd"

## CoinBurstField tests — run with:
##   godot --headless --scene res://test/test_coin_burst.tscn
##
## Covers the pure, headless-testable logic: the slot pool (LIFO + graceful
## exhaustion), particle seeding (always downward, within spread/jitter
## bounds), the analytic motion + fade math, the enabled-gate no-op, and the
## AudioManager "coin_burst" VFX override. No rendering / scene tree needed.


func _run_tests() -> void:
	print("\n=== CoinBurstField Tests ===\n")

	test_pool_acquire_is_lifo()
	test_pool_exhausted_returns_minus_one()
	test_pool_release_returns_slot()

	test_seed_velocity_always_downward()
	test_seed_horizontal_within_spread()
	test_seed_duration_within_jitter()

	test_position_at_time_zero_is_start()
	test_position_pure_gravity_drop()
	test_position_full_formula()
	test_position_only_falls_over_time()

	test_alpha_full_at_start()
	test_alpha_zero_at_end()
	test_alpha_monotonic_decreasing()

	test_disabled_spawn_is_noop()
	test_vfx_override_toggles_theme()


# --- Helper ---

func _make_field() -> CoinBurstField:
	# Bare instance: _ready() does NOT run (not in a SceneTree), so no MultiMesh
	# is built. Sufficient for pool + pure-logic tests.
	return CoinBurstField.new()


# --- Slot pool ---

func test_pool_acquire_is_lifo() -> void:
	print("test_pool_acquire_is_lifo")
	var f := _make_field()
	f._free_indices = [0, 1, 2]
	assert_equal(f._acquire_slot(), 2, "pops last (LIFO)")
	assert_equal(f._acquire_slot(), 1, "pops next")
	assert_equal(f._acquire_slot(), 0, "pops first")
	f.free()


func test_pool_exhausted_returns_minus_one() -> void:
	print("test_pool_exhausted_returns_minus_one")
	var f := _make_field()
	f._free_indices = []
	assert_equal(f._acquire_slot(), -1, "exhausted pool returns -1, no crash")
	f.free()


func test_pool_release_returns_slot() -> void:
	print("test_pool_release_returns_slot")
	var f := _make_field()
	f._free_indices = []
	f._release_slot(7)
	assert_equal(f._acquire_slot(), 7, "released slot is reusable")
	f.free()


# --- seed_particle ---

func test_seed_velocity_always_downward() -> void:
	print("test_seed_velocity_always_downward")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var all_down := true
	for i in 200:
		var s: Dictionary = CoinBurstField.seed_particle(rng, 1.6, 0.45, 0.5)
		if (s["vel"] as Vector3).y >= 0.0:
			all_down = false
			break
	assert_true(all_down, "vel.y is always negative (sprays DOWN, never up)")


func test_seed_horizontal_within_spread() -> void:
	print("test_seed_horizontal_within_spread")
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	var within := true
	for i in 200:
		var s: Dictionary = CoinBurstField.seed_particle(rng, 1.6, 0.45, 0.5)
		var v: Vector3 = s["vel"]
		if absf(v.x) > 0.45 + 0.0001 or v.z != 0.0:
			within = false
			break
	assert_true(within, "|vel.x| <= spread and vel.z == 0 (board XY plane)")


func test_seed_duration_within_jitter() -> void:
	print("test_seed_duration_within_jitter")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ok := true
	for i in 200:
		var s: Dictionary = CoinBurstField.seed_particle(rng, 1.6, 0.45, 0.5)
		var d: float = s["duration"]
		# jitter is _DURATION_JITTER_MIN..1.0 of base (0.8..1.0 * 0.5)
		if d < 0.5 * 0.8 - 0.0001 or d > 0.5 + 0.0001:
			ok = false
			break
	assert_true(ok, "duration within [base*0.8, base]")


# --- position_at (analytic kinematics) ---

func test_position_at_time_zero_is_start() -> void:
	print("test_position_at_time_zero_is_start")
	var start := Vector3(1, 2, 0)
	var pos := CoinBurstField.position_at(start, Vector3(3, -2, 0), 6.0, 0.0)
	assert_true(pos.is_equal_approx(start), "t=0 → exactly the start position")


func test_position_pure_gravity_drop() -> void:
	print("test_position_pure_gravity_drop")
	# No initial velocity: y = -½ g t²  →  -0.5 * 6 * 1² = -3
	var pos := CoinBurstField.position_at(Vector3.ZERO, Vector3.ZERO, 6.0, 1.0)
	assert_near(pos.y, -3.0, 0.0001, "pure gravity drop matches -½gt²")


func test_position_full_formula() -> void:
	print("test_position_full_formula")
	# start=(1,1,0), vel=(2,-1,0), g=10, t=0.2
	# x = 1 + 2*0.2 = 1.4 ; y = 1 + (-1)*0.2 - 0.5*10*0.04 = 1 - 0.2 - 0.2 = 0.6
	var pos := CoinBurstField.position_at(Vector3(1, 1, 0), Vector3(2, -1, 0), 10.0, 0.2)
	assert_near(pos.x, 1.4, 0.0001, "x = start + vx*t")
	assert_near(pos.y, 0.6, 0.0001, "y = start + vy*t - ½gt²")


func test_position_only_falls_over_time() -> void:
	print("test_position_only_falls_over_time")
	# Even with zero initial vertical velocity, gravity makes y strictly decrease.
	var prev := CoinBurstField.position_at(Vector3.ZERO, Vector3(1, 0, 0), 6.0, 0.0).y
	var falls := true
	for i in range(1, 10):
		var y := CoinBurstField.position_at(Vector3.ZERO, Vector3(1, 0, 0), 6.0, i * 0.1).y
		if y >= prev:
			falls = false
			break
		prev = y
	assert_true(falls, "y strictly decreases over time (always falling)")


# --- alpha_at (fade) ---

func test_alpha_full_at_start() -> void:
	print("test_alpha_full_at_start")
	assert_near(CoinBurstField.alpha_at(0.0, 0.5), 1.0, 0.0001, "fully opaque at spawn")


func test_alpha_zero_at_end() -> void:
	print("test_alpha_zero_at_end")
	assert_near(CoinBurstField.alpha_at(0.5, 0.5), 0.0, 0.0001, "fully faded at end of life")


func test_alpha_monotonic_decreasing() -> void:
	print("test_alpha_monotonic_decreasing")
	var prev := CoinBurstField.alpha_at(0.0, 1.0)
	var mono := true
	for i in range(1, 11):
		var a := CoinBurstField.alpha_at(i * 0.1, 1.0)
		if a > prev + 0.0001:
			mono = false
			break
		prev = a
	assert_true(mono, "alpha never increases over a particle's life")


# --- enabled gate ---

func test_disabled_spawn_is_noop() -> void:
	print("test_disabled_spawn_is_noop")
	var f := _make_field()
	var prev: bool = ThemeProvider.theme.coin_burst_enabled
	ThemeProvider.theme.coin_burst_enabled = false
	f.spawn(Vector3.ZERO, Color.WHITE)
	assert_true(f._active.is_empty(), "disabled → spawn enqueues nothing")
	ThemeProvider.theme.coin_burst_enabled = prev
	f.free()


# --- AudioManager VFX override ---

func test_vfx_override_toggles_theme() -> void:
	print("test_vfx_override_toggles_theme")
	var prev_flag: bool = ThemeProvider.theme.coin_burst_enabled
	var prev_overrides: Dictionary = AudioManager._vfx_overrides.duplicate(true)
	AudioManager.set_vfx_override("coin_burst", false)
	assert_false(ThemeProvider.theme.coin_burst_enabled, "override flips theme flag off")
	AudioManager.set_vfx_override("coin_burst", true)
	assert_true(ThemeProvider.theme.coin_burst_enabled, "override flips theme flag on")
	AudioManager._vfx_overrides = prev_overrides
	ThemeProvider.theme.coin_burst_enabled = prev_flag
