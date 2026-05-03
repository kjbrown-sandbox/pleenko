extends "res://test/test_base.gd"

## PlinkoBoard tests — run with:
##   godot --headless --scene res://test/test_plinko_board.tscn
##
## Tests pure-logic functions on a bare PlinkoBoard instance (no scene tree,
## no @onready nodes). We set member vars directly and call the functions.


func _run_tests() -> void:
	print("\n=== PlinkoBoard Tests ===\n")

	test_bucket_value_basic()
	test_bucket_value_with_multiplier()
	test_bucket_value_advanced_offset()
	test_bucket_value_below_advanced_threshold()
	test_bucket_position_key_positive()
	test_bucket_position_key_negative()
	test_bucket_position_key_zero()
	test_get_bounds_geometry()
	test_has_in_flight_coins_empty()


# --- Helper ---

## Creates a bare PlinkoBoard with no scene tree. Only member vars are
## available — @onready fields are null. Sufficient for pure-logic tests.
func _make_board(overrides: Dictionary = {}) -> PlinkoBoard:
	var board := PlinkoBoard.new()
	board.board_type = overrides.get("board_type", Enums.BoardType.GOLD)
	board.num_rows = overrides.get("num_rows", 4)
	board.bucket_value_multiplier = overrides.get("bucket_value_multiplier", 1)
	board.distance_for_advanced_buckets = overrides.get("distance_for_advanced_buckets", 3)
	board.should_show_advanced_buckets = overrides.get("should_show_advanced_buckets", false)
	board.space_between_pegs = overrides.get("space_between_pegs", 1.0)
	board.vertical_spacing = overrides.get("vertical_spacing", 1.0)
	return board


# --- Bucket value tests ---

func test_bucket_value_basic() -> void:
	print("test_bucket_value_basic")
	# multiplier=1, distance=2, no advanced buckets
	# val = 1 + 2 * 1 = 3
	var board := _make_board()
	assert_equal(board._bucket_value_for_distance(2), 3, "1 + 2*1 = 3")
	board.free()


func test_bucket_value_with_multiplier() -> void:
	print("test_bucket_value_with_multiplier")
	# multiplier=3, distance=2
	# val = 1 + 2 * 3 = 7
	var board := _make_board({"bucket_value_multiplier": 3})
	assert_equal(board._bucket_value_for_distance(2), 7, "1 + 2*3 = 7")
	board.free()


func test_bucket_value_advanced_offset() -> void:
	print("test_bucket_value_advanced_offset")
	# distance=4, advanced_distance=3, show_advanced=true, multiplier=1
	# effective_distance = 4 - 3 = 1, val = 1 + 1*1 = 2
	var board := _make_board({
		"distance_for_advanced_buckets": 3,
		"should_show_advanced_buckets": true,
	})
	assert_equal(board._bucket_value_for_distance(4), 2, "advanced offset: 1 + (4-3)*1 = 2")
	board.free()


func test_bucket_value_below_advanced_threshold() -> void:
	print("test_bucket_value_below_advanced_threshold")
	# distance=2, advanced_distance=3, show_advanced=true
	# distance < advanced_distance, so no offset
	# val = 1 + 2 * 1 = 3
	var board := _make_board({
		"distance_for_advanced_buckets": 3,
		"should_show_advanced_buckets": true,
	})
	assert_equal(board._bucket_value_for_distance(2), 3, "below threshold: no offset")
	board.free()


# --- Bucket position key tests ---

func test_bucket_position_key_positive() -> void:
	print("test_bucket_position_key_positive")
	var board := _make_board()
	# 1.234 * 1000 = 1234
	assert_equal(board._bucket_position_key(1.234), 1234, "positive x -> 1234")
	board.free()


func test_bucket_position_key_negative() -> void:
	print("test_bucket_position_key_negative")
	var board := _make_board()
	# -0.5 * 1000 = -500
	assert_equal(board._bucket_position_key(-0.5), -500, "negative x -> -500")
	board.free()


func test_bucket_position_key_zero() -> void:
	print("test_bucket_position_key_zero")
	var board := _make_board()
	assert_equal(board._bucket_position_key(0.0), 0, "zero x -> 0")
	board.free()


# --- Bounds geometry test ---

func test_get_bounds_geometry() -> void:
	print("test_get_bounds_geometry")
	# num_rows=4, vertical_spacing=1.0, space_between_pegs=1.0
	# top = 1.0 + 0.5 = 1.5
	# bottom = -1.0 * 4 + (1.0/3) - 0.5 = -4 + 0.333 - 0.5 = -4.167
	# half_width = (4/2.0) * 1.0 + 0.5 = 2.5
	# Rect2(-2.5, -4.167, 5.0, 5.667)
	var board := _make_board({"num_rows": 4, "vertical_spacing": 1.0, "space_between_pegs": 1.0})
	var bounds: Rect2 = board.get_bounds()
	assert_near(bounds.position.x, -2.5, 0.01, "bounds x")
	assert_near(bounds.size.x, 5.0, 0.01, "bounds width")
	assert_true(bounds.position.y < 0.0, "bounds bottom is negative")
	assert_true(bounds.size.y > 0.0, "bounds height is positive")
	board.free()


# --- In-flight coins test ---

func test_has_in_flight_coins_empty() -> void:
	print("test_has_in_flight_coins_empty")
	var board := _make_board()
	assert_false(board.has_in_flight_coins(), "no coins in flight on fresh board")
	board.free()
