extends "res://test/test_base.gd"

## RefinedBaselineButton pure-logic tests — the hover/press colour resolution
## (the feature's visible feedback) and the draw-mode → state mapping. The
## interaction tweens / styleboxes are visual and exercised in-game, not here.
## Run with:
##   godot --headless --scene res://test/test_refined_baseline_button.tscn


func _run_tests() -> void:
	print("\n=== RefinedBaselineButton Tests ===\n")
	test_shade_normal_unchanged()
	test_shade_hover_lightens()
	test_shade_pressed_darkens()
	test_state_for_draw_modes()
	test_equalize_widths_snaps_all_to_widest()
	test_action_box_solid_fill_matches_tint()


func _make_button() -> RefinedBaselineButton:
	# Bare instance — _shade_for_state / _state_for touch no child nodes and the
	# property setters no-op out of tree, so we never add it to the tree.
	return RefinedBaselineButton.new()


func test_shade_normal_unchanged() -> void:
	print("test_shade_normal_unchanged")
	var b := _make_button()
	var tint := Color(0.4, 0.3, 0.2)
	assert_equal(b._shade_for_state(tint, RefinedBaselineButton.BtnState.NORMAL), tint,
		"NORMAL returns the tint unchanged")
	b.free()


func test_shade_hover_lightens() -> void:
	print("test_shade_hover_lightens")
	var b := _make_button()
	var tint := Color(0.4, 0.3, 0.2)
	assert_equal(b._shade_for_state(tint, RefinedBaselineButton.BtnState.HOVER),
		tint.lightened(RefinedBaselineButton.HOVER_LIGHTEN), "HOVER lightens by HOVER_LIGHTEN")
	b.free()


func test_shade_pressed_darkens() -> void:
	print("test_shade_pressed_darkens")
	var b := _make_button()
	var tint := Color(0.4, 0.3, 0.2)
	assert_equal(b._shade_for_state(tint, RefinedBaselineButton.BtnState.PRESSED),
		tint.darkened(RefinedBaselineButton.PRESS_DARKEN), "PRESSED darkens by PRESS_DARKEN")
	b.free()


func test_state_for_draw_modes() -> void:
	print("test_state_for_draw_modes")
	var b := _make_button()
	assert_equal(b._state_for("hover"), RefinedBaselineButton.BtnState.HOVER, "hover → HOVER")
	assert_equal(b._state_for("pressed"), RefinedBaselineButton.BtnState.PRESSED, "pressed → PRESSED")
	assert_equal(b._state_for("normal"), RefinedBaselineButton.BtnState.NORMAL, "normal → NORMAL")
	# disabled deliberately maps to the resting look, never a hover/press tint.
	assert_equal(b._state_for("disabled"), RefinedBaselineButton.BtnState.NORMAL,
		"disabled → NORMAL (resting)")
	b.free()


func test_equalize_widths_snaps_all_to_widest() -> void:
	print("test_equalize_widths_snaps_all_to_widest")
	# Bare instances — equalize_widths only reads/writes custom_minimum_size.x,
	# no tree or child nodes needed.
	var a := RefinedBaselineButton.new()
	var b := RefinedBaselineButton.new()
	var c := RefinedBaselineButton.new()
	a.custom_minimum_size = Vector2(100.0, 48.0)
	b.custom_minimum_size = Vector2(250.0, 48.0)
	c.custom_minimum_size = Vector2(180.0, 48.0)
	RefinedBaselineButton.equalize_widths([a, b, c])
	assert_equal(a.custom_minimum_size.x, 250.0, "narrow button widens to the max")
	assert_equal(b.custom_minimum_size.x, 250.0, "widest button keeps its width")
	assert_equal(c.custom_minimum_size.x, 250.0, "middle button widens to the max")
	assert_equal(a.custom_minimum_size.y, 48.0, "height untouched")
	a.free()
	b.free()
	c.free()


func test_action_box_solid_fill_matches_tint() -> void:
	print("test_action_box_solid_fill_matches_tint")
	# Dropdowns reuse this for a look identical to the action button: solid fill,
	# matching border, capless corner radius.
	var tint := Color(0.4, 0.3, 0.2)
	var box := RefinedBaselineButton._action_box(tint)
	assert_equal(box.bg_color, tint, "fill bg = tint")
	assert_equal(box.border_color, tint, "border = tint")
	assert_equal(box.corner_radius_top_left, RefinedBaselineButton.RADIUS_PX,
		"corner radius matches the bar")
	assert_equal(box.border_width_left, RefinedBaselineButton.BORDER_PX,
		"border width matches the bar")
