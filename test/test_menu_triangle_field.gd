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
