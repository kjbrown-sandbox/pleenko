extends Node

## Shared test runner base — individual test files extend this.
## Each test is a .tscn scene with this script (or a subclass) attached.
## Run with:
##   godot --headless --scene res://test/test_whatever.tscn

var _pass_count := 0
var _fail_count := 0


func _run_tests() -> void:
	push_error("Subclass must override _run_tests()")


func _ready() -> void:
	# Await covers tests that use `await` internally (e.g. for coroutine flows);
	# pure-sync test suites pay a single extra idle-frame delay, no behavior change.
	await _run_tests()

	print("\n--- Results: %d passed, %d failed ---" % [_pass_count, _fail_count])
	if _fail_count > 0:
		printerr("SOME TESTS FAILED")
	get_tree().quit(1 if _fail_count > 0 else 0)


# --- Assertion helpers ---

func assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		_pass_count += 1
	else:
		_fail_count += 1
		printerr("  FAIL: %s — expected %s, got %s" % [label, expected, actual])


func assert_true(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		printerr("  FAIL: %s — expected true, got false" % label)


func assert_false(condition: bool, label: String) -> void:
	if not condition:
		_pass_count += 1
	else:
		_fail_count += 1
		printerr("  FAIL: %s — expected false, got true" % label)


func assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) <= tolerance:
		_pass_count += 1
	else:
		_fail_count += 1
		printerr("  FAIL: %s — expected ~%s (±%s), got %s" % [label, expected, tolerance, actual])
