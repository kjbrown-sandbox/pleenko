extends "res://test/test_base.gd"

## MenuTriangleField pure fade-curve tests — run with:
##   godot --headless --scene res://test/test_menu_triangle_field.tscn
##
## Only the pure `compute_alpha(elapsed, fade, hold)` curve is asserted (the
## rest of the field is _process/MultiMesh visual chrome — not unit-tested).

const FADE := 2.0
const HOLD := 5.0


func _run_tests() -> void:
	print("\n=== MenuTriangleField Tests ===\n")
	test_compute_alpha_curve()
	test_spawn_rect_centered()
	test_spawn_rect_menu_legacy_values()


func test_compute_alpha_curve() -> void:
	print("test_compute_alpha_curve")
	var f := FADE
	var h := HOLD
	var total := f + h + f
	assert_equal(MenuTriangleField.compute_alpha(-1.0, f, h), 0.0, "before start → 0")
	assert_equal(MenuTriangleField.compute_alpha(0.0, f, h), 0.0, "t=0 → 0")
	assert_near(MenuTriangleField.compute_alpha(f * 0.5, f, h), 0.5, 0.0001,
		"mid fade-in → 0.5")
	assert_equal(MenuTriangleField.compute_alpha(f, f, h), 1.0, "fade-in end → 1")
	assert_equal(MenuTriangleField.compute_alpha(f + h * 0.5, f, h), 1.0, "hold → 1")
	assert_equal(MenuTriangleField.compute_alpha(f + h, f, h), 1.0, "hold end → 1")
	assert_near(MenuTriangleField.compute_alpha(f + h + f * 0.5, f, h), 0.5, 0.0001,
		"mid fade-out → 0.5")
	assert_equal(MenuTriangleField.compute_alpha(total, f, h), 0.0, "life end → 0")
	assert_equal(MenuTriangleField.compute_alpha(total + 1.0, f, h), 0.0,
		"after life → 0")


func test_spawn_rect_centered() -> void:
	print("test_spawn_rect_centered")
	# pad 1.15 → half_w 23.0, half_h 18.4; rect = (-23, -18.4, 46, 36.8)
	var r := MenuTriangleField.spawn_rect_for(Vector2(0, 0), Vector2(20, 16), 1.15)
	assert_near(r.position.x, -23.0, 0.001, "x left = -half_w * pad")
	assert_near(r.position.y, -18.4, 0.001, "y top = -half_h * pad")
	assert_near(r.size.x, 46.0, 0.001, "width = 2 * half_w * pad")
	assert_near(r.size.y, 36.8, 0.001, "height = 2 * half_h * pad")


func test_spawn_rect_menu_legacy_values() -> void:
	print("test_spawn_rect_menu_legacy_values")
	# Original menu values: center=(0,-17), half_extent=(34,28), pad=1.15
	var r := MenuTriangleField.spawn_rect_for(Vector2(0, -17), Vector2(34, 28), 1.15)
	assert_near(r.position.x, -39.1, 0.001, "legacy menu rect x")
	assert_near(r.position.y, -17.0 - 28.0 * 1.15, 0.001, "legacy menu rect y")
	assert_near(r.size.x, 78.2, 0.001, "legacy menu rect width")
	assert_near(r.size.y, 64.4, 0.001, "legacy menu rect height")
