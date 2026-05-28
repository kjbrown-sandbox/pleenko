extends "res://test/test_base.gd"

## MenuTitle / MenuBoard.get_live_coin_positions tests — run with:
##   godot --headless --scene res://test/test_menu_title.tscn
##
## Pure-logic tests on MenuTitle's static helpers and MenuBoard's new public
## accessor. No scene tree, no Camera3D, no Tween machinery.


func _run_tests() -> void:
	print("\n=== MenuTitle Tests ===\n")
	test_letter_hit_at_screen_pos_empty_array()
	test_letter_hit_at_screen_pos_single_rect()
	test_letter_hit_at_screen_pos_returns_first_match()
	test_letter_hit_at_screen_pos_miss_returns_minus_one()
	test_menu_board_get_live_coin_positions_empty_when_no_coins_node()


# --- MenuTitle.letter_hit_at_screen_pos ---

func test_letter_hit_at_screen_pos_empty_array() -> void:
	print("test_letter_hit_at_screen_pos_empty_array")
	var empty: Array[Rect2] = []
	assert_equal(MenuTitle.letter_hit_at_screen_pos(empty, Vector2(10, 10)), -1,
		"empty rect array returns -1")


func test_letter_hit_at_screen_pos_single_rect() -> void:
	print("test_letter_hit_at_screen_pos_single_rect")
	var rects: Array[Rect2] = [Rect2(100, 100, 50, 80)]
	assert_equal(MenuTitle.letter_hit_at_screen_pos(rects, Vector2(125, 140)), 0,
		"point inside rect returns 0")
	assert_equal(MenuTitle.letter_hit_at_screen_pos(rects, Vector2(99, 140)), -1,
		"point left of rect returns -1")
	assert_equal(MenuTitle.letter_hit_at_screen_pos(rects, Vector2(151, 140)), -1,
		"point right of rect returns -1")
	assert_equal(MenuTitle.letter_hit_at_screen_pos(rects, Vector2(125, 99)), -1,
		"point above rect returns -1")
	assert_equal(MenuTitle.letter_hit_at_screen_pos(rects, Vector2(125, 181)), -1,
		"point below rect returns -1")


func test_letter_hit_at_screen_pos_returns_first_match() -> void:
	print("test_letter_hit_at_screen_pos_returns_first_match")
	# Overlapping rects: the first one wins (linear walk, early return).
	var rects: Array[Rect2] = [
		Rect2(0, 0, 100, 100),
		Rect2(50, 50, 100, 100),
	]
	assert_equal(MenuTitle.letter_hit_at_screen_pos(rects, Vector2(75, 75)), 0,
		"overlap region resolves to the first matching rect")
	assert_equal(MenuTitle.letter_hit_at_screen_pos(rects, Vector2(125, 125)), 1,
		"second rect's exclusive region returns 1")


func test_letter_hit_at_screen_pos_miss_returns_minus_one() -> void:
	print("test_letter_hit_at_screen_pos_miss_returns_minus_one")
	var rects: Array[Rect2] = [
		Rect2(0, 0, 10, 10),
		Rect2(20, 0, 10, 10),
		Rect2(40, 0, 10, 10),
	]
	assert_equal(MenuTitle.letter_hit_at_screen_pos(rects, Vector2(15, 5)), -1,
		"point in gap between rects returns -1")
	assert_equal(MenuTitle.letter_hit_at_screen_pos(rects, Vector2(45, 5)), 2,
		"point in third rect returns 2")


# --- MenuBoard.get_live_coin_positions ---

func test_menu_board_get_live_coin_positions_empty_when_no_coins_node() -> void:
	# Bare MenuBoard.new() has no @onready children resolved — the accessor
	# must early-return an empty array rather than crash. Documents the
	# safety branch the docstring promises.
	print("test_menu_board_get_live_coin_positions_empty_when_no_coins_node")
	var mb := MenuBoard.new()
	var positions: PackedVector3Array = mb.get_live_coin_positions()
	assert_equal(positions.size(), 0,
		"get_live_coin_positions() returns empty array on bare instance")
	mb.free()
