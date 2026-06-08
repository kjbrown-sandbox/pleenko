extends "res://test/test_base.gd"

## DropGate state-machine tests — run with:
##   godot --headless --scene res://test/test_drop_gate.tscn
##
## Exercises the open/close swing logic WITHOUT building the meshes: the node is
## never added to the tree, so _ready/_build don't run and _apply_angle's null
## pivot guards keep it crash-free. _process is pumped directly to integrate the
## swing the way the engine would.


func _run_tests() -> void:
	print("\n=== DropGate Tests ===\n")
	test_starts_open()
	test_close_settles_closed()
	test_open_settles_open()
	test_close_during_open_defers_to_full_swing()


## Pump _process in small steps so the swing integrates like a frame loop.
func _advance(gate: DropGate, seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		gate._process(0.016)
		elapsed += 0.016


func test_starts_open() -> void:
	print("test_starts_open")
	var gate := DropGate.new()
	assert_equal(gate._state, DropGate.State.OPEN, "starts OPEN (idle, waiting for a coin)")
	assert_near(gate._angle, 1.0, 0.0001, "starts fully open")
	gate.free()


func test_close_settles_closed() -> void:
	print("test_close_settles_closed")
	var gate := DropGate.new()
	gate.close()
	assert_equal(gate._state, DropGate.State.CLOSING, "close() from OPEN -> CLOSING")
	_advance(gate, 0.5)
	assert_equal(gate._state, DropGate.State.CLOSED, "settles CLOSED")
	assert_near(gate._angle, 0.0, 0.0001, "fully closed (flat bar)")
	gate.free()


func test_open_settles_open() -> void:
	print("test_open_settles_open")
	var gate := DropGate.new()
	gate.close()
	_advance(gate, 0.5)  # now CLOSED
	gate.open()
	assert_equal(gate._state, DropGate.State.OPENING, "open() from CLOSED -> OPENING")
	_advance(gate, 0.5)
	assert_equal(gate._state, DropGate.State.OPEN, "settles OPEN")
	assert_near(gate._angle, 1.0, 0.0001, "fully open (vertical)")
	gate.free()


func test_close_during_open_defers_to_full_swing() -> void:
	print("test_close_during_open_defers_to_full_swing")
	# A drop calls open() (ready) then close() (coin passed) on the same frame.
	# The gate must reach vertical before closing, so the player sees the full
	# down-then-up swing rather than an instant snap-back.
	var gate := DropGate.new()
	gate.close()
	_advance(gate, 0.5)  # CLOSED
	gate.open()
	gate.close()  # requested mid-open
	assert_equal(gate._state, DropGate.State.OPENING, "stays OPENING until vertical")
	_advance(gate, 1.0)  # plenty to open then close
	assert_equal(gate._state, DropGate.State.CLOSED, "ends CLOSED after the full swing")
	gate.free()
