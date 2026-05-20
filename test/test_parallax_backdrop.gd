extends "res://test/test_base.gd"

## ParallaxBackdrop pure-math tests — run with:
##   godot --headless --scene res://test/test_parallax_backdrop.tscn
##
## Asserts the static parallax_offset / parallax_scale helpers; the per-frame
## `_process` + Camera3D coupling is visual chrome (not unit-tested).


func _run_tests() -> void:
	print("\n=== ParallaxBackdrop Tests ===\n")
	test_parallax_offset_at_rest()
	test_parallax_offset_factor_zero_glued_to_camera()
	test_parallax_offset_factor_one_world_fixed()
	test_parallax_offset_default_lag()
	test_parallax_offset_xy_only_z_held()
	test_parallax_offset_anchor_preserved_with_camera_offset()
	test_parallax_scale_no_zoom_change()
	test_parallax_scale_full_zoom_passthrough()
	test_parallax_scale_half_zoom_blend()
	test_parallax_scale_rest_zero_guard()


func test_parallax_offset_at_rest() -> void:
	print("test_parallax_offset_at_rest")
	# Wrapper anchored at origin; camera at rest → wrapper sits at anchor.
	var anchor := Vector3(0.0, 0.0, 0.0)
	var cam_rest := Vector3(0.0, -1.72, 6.98)
	var p := ParallaxBackdrop.parallax_offset(cam_rest, cam_rest, anchor, 0.20)
	assert_near(p.x, anchor.x, 0.0001, "x at anchor")
	assert_near(p.y, anchor.y, 0.0001, "y at anchor")
	assert_near(p.z, anchor.z, 0.0001, "z at anchor")


func test_parallax_offset_factor_zero_glued_to_camera() -> void:
	print("test_parallax_offset_factor_zero_glued_to_camera")
	# factor=0 → wrapper follows the camera XY delta 1:1 from its anchor.
	var anchor := Vector3(0.0, 0.0, 0.0)
	var cam_rest := Vector3(0.0, 0.0, 7.0)
	var cam := Vector3(10.0, 4.0, 7.0)
	var p := ParallaxBackdrop.parallax_offset(cam, cam_rest, anchor, 0.0)
	assert_near(p.x, anchor.x + 10.0, 0.0001, "factor=0 → wrapper x follows full delta")
	assert_near(p.y, anchor.y + 4.0, 0.0001, "factor=0 → wrapper y follows full delta")


func test_parallax_offset_factor_one_world_fixed() -> void:
	print("test_parallax_offset_factor_one_world_fixed")
	# factor=1 → wrapper stays at anchor regardless of camera movement.
	var anchor := Vector3(0.0, 0.0, 0.0)
	var cam_rest := Vector3(0.0, 0.0, 7.0)
	var cam := Vector3(10.0, 4.0, 7.0)
	var p := ParallaxBackdrop.parallax_offset(cam, cam_rest, anchor, 1.0)
	assert_near(p.x, anchor.x, 0.0001, "factor=1 → wrapper world-fixed on x")
	assert_near(p.y, anchor.y, 0.0001, "factor=1 → wrapper world-fixed on y")


func test_parallax_offset_default_lag() -> void:
	print("test_parallax_offset_default_lag")
	# Camera moved +10 on x with factor 0.20 → wrapper moves 80% of delta = 8.0.
	var anchor := Vector3(0.0, 0.0, 0.0)
	var cam_rest := Vector3(0.0, 0.0, 7.0)
	var cam := Vector3(10.0, 0.0, 7.0)
	var p := ParallaxBackdrop.parallax_offset(cam, cam_rest, anchor, 0.20)
	assert_near(p.x, anchor.x + 8.0, 0.0001, "factor=0.20 → x lag at 80% of delta")
	assert_near(p.y, anchor.y, 0.0001, "y unchanged")


func test_parallax_offset_xy_only_z_held() -> void:
	print("test_parallax_offset_xy_only_z_held")
	# Z always stays at anchor.z — the camera's Z is deliberately ignored so
	# the wrapper doesn't drift forward and push triangles in front of pegs.
	var anchor := Vector3(0.0, 0.0, 0.0)
	var cam_rest := Vector3(0.0, 0.0, 7.0)
	var cam := Vector3(0.0, 0.0, 99.0)
	var p := ParallaxBackdrop.parallax_offset(cam, cam_rest, anchor, 0.20)
	assert_near(p.z, anchor.z, 0.0001, "z stays at anchor.z (no camera Z parallax)")


func test_parallax_offset_anchor_preserved_with_camera_offset() -> void:
	print("test_parallax_offset_anchor_preserved_with_camera_offset")
	# Even with the gameplay's offset camera (X=0, Y=-1.72, Z=7), wrapper at
	# anchor (0,0,0) with camera at rest must sit at the anchor — NOT at the
	# camera position. This is the regression that put triangles in front of pegs.
	var anchor := Vector3(0.0, 0.0, 0.0)
	var cam_rest := Vector3(0.0, -1.72, 6.98)
	var p := ParallaxBackdrop.parallax_offset(cam_rest, cam_rest, anchor, 0.20)
	assert_near(p.x, 0.0, 0.0001, "wrapper x stays at anchor, not camera x")
	assert_near(p.y, 0.0, 0.0001, "wrapper y stays at anchor, not camera y")
	assert_near(p.z, 0.0, 0.0001, "wrapper z stays at anchor, not camera z")


func test_parallax_scale_no_zoom_change() -> void:
	print("test_parallax_scale_no_zoom_change")
	var s := ParallaxBackdrop.parallax_scale(11.0, 11.0, 0.5)
	assert_near(s, 1.0, 0.0001, "cam_size == rest_size → 1.0")


func test_parallax_scale_full_zoom_passthrough() -> void:
	print("test_parallax_scale_full_zoom_passthrough")
	# zoom_factor=1.0 → scale tracks ratio fully
	var s := ParallaxBackdrop.parallax_scale(22.0, 11.0, 1.0)
	assert_near(s, 2.0, 0.0001, "factor=1.0 → scale = ratio")


func test_parallax_scale_half_zoom_blend() -> void:
	print("test_parallax_scale_half_zoom_blend")
	# zoom_factor=0.5 → halfway between 1.0 and ratio (=2.0) → 1.5
	var s := ParallaxBackdrop.parallax_scale(22.0, 11.0, 0.5)
	assert_near(s, 1.5, 0.0001, "factor=0.5 → blend halfway")
	# zoom_factor=0.0 → no scale response
	var s_off := ParallaxBackdrop.parallax_scale(22.0, 11.0, 0.0)
	assert_near(s_off, 1.0, 0.0001, "factor=0.0 → scale locked at 1.0")


func test_parallax_scale_rest_zero_guard() -> void:
	print("test_parallax_scale_rest_zero_guard")
	var s := ParallaxBackdrop.parallax_scale(22.0, 0.0, 0.5)
	assert_near(s, 1.0, 0.0001, "rest_size=0 → safe fallback 1.0")
	var s_neg := ParallaxBackdrop.parallax_scale(22.0, -1.0, 0.5)
	assert_near(s_neg, 1.0, 0.0001, "rest_size<0 → safe fallback 1.0")
