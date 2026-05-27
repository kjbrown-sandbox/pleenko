extends "res://test/test_base.gd"

## MenuHoverArpeggiator tests — pure state-machine logic for the main-menu
## hover audio arpeggio. Run with:
##   godot --headless --scene res://test/test_menu_hover_arpeggiator.tscn


func _run_tests() -> void:
	print("\n=== MenuHoverArpeggiator Tests ===\n")
	test_floor_on_first_call()
	test_ascend_through_indices()
	test_reverse_at_peak()
	test_descend_back_to_floor()
	test_reverse_at_floor()
	test_reset_after_decay_window()
	test_decay_window_inclusive_boundary()
	test_pitch_mult_at_chord_bed_octave()
	test_pitch_mult_octave_up()
	test_pitch_mult_octave_down()
	test_pitch_mult_clamps_out_of_range_note()
	test_pitch_mult_empty_chord_returns_unity()


func _make_arpeggiator(decay_ms: int = MenuHoverArpeggiator.DEFAULT_DECAY_MS) -> MenuHoverArpeggiator:
	var a := MenuHoverArpeggiator.new()
	a.decay_ms = decay_ms
	return a


# --- advance() state machine ---

func test_floor_on_first_call() -> void:
	print("test_floor_on_first_call")
	var a := _make_arpeggiator()
	# First call ever — decay branch fires (now_ms = 0 is way past the
	# sentinel _last_hover_ms = -decay-1), so the index resets to 0 and
	# octave_offset = OCTAVE_FLOOR.
	var note := a.advance(0)
	assert_equal(note.x, 0, "first call returns note 0")
	assert_equal(note.y, MenuHoverArpeggiator.OCTAVE_FLOOR, "first call sits on the octave floor")


func test_ascend_through_indices() -> void:
	print("test_ascend_through_indices")
	var a := _make_arpeggiator()
	a.advance(0)  # warm to floor
	# Within the decay window — subsequent calls climb.
	for expected_note in [1, 2, 3]:
		var note := a.advance(50)
		assert_equal(note.x, expected_note, "ascent step %d" % expected_note)


func test_reverse_at_peak() -> void:
	print("test_reverse_at_peak")
	var a := _make_arpeggiator()
	# OCTAVE_SPAN = 1 (4 positions: 0..3). Climb to peak then test the bounce.
	a.advance(0)
	for ms in [10, 20, 30]:
		a.advance(ms)  # now at index 3 (MAX_INDEX)
	var bounced := a.advance(40)
	assert_equal(bounced.x, 2, "bounce off peak descends to index 2")


func test_descend_back_to_floor() -> void:
	print("test_descend_back_to_floor")
	var a := _make_arpeggiator()
	a.advance(0)
	# Climb to peak: 0 → 1 → 2 → 3
	for ms in [10, 20, 30]:
		a.advance(ms)
	# Bounce + descend: 2 → 1 → 0
	var expected := [2, 1, 0]
	for i in range(expected.size()):
		var note := a.advance(40 + i * 10)
		assert_equal(note.x, expected[i], "descent step → %d" % expected[i])


func test_reverse_at_floor() -> void:
	print("test_reverse_at_floor")
	var a := _make_arpeggiator()
	# Climb 0→3, descend 3→0, then advance once more.
	a.advance(0)
	for ms in [10, 20, 30, 40, 50, 60]:
		a.advance(ms)
	var bounced := a.advance(70)
	assert_equal(bounced.x, 1, "bounce off floor ascends to index 1")


func test_reset_after_decay_window() -> void:
	print("test_reset_after_decay_window")
	var a := _make_arpeggiator(1500)
	a.advance(0)
	a.advance(100)  # at index 1
	a.advance(200)  # at index 2
	# Wait long enough for decay — next advance must reset to floor.
	var note := a.advance(2000)
	assert_equal(note.x, 0, "post-decay advance returns to floor")
	assert_equal(note.y, MenuHoverArpeggiator.OCTAVE_FLOOR, "post-decay sits on the octave floor")


func test_decay_window_inclusive_boundary() -> void:
	print("test_decay_window_inclusive_boundary")
	# Exactly at the decay boundary — still considered "rapid" (no reset).
	# Advance(t1) - advance(t0) == decay_ms → don't reset.
	var a := _make_arpeggiator(1000)
	a.advance(0)         # _last_hover_ms = 0, index = 0
	var note := a.advance(1000)  # diff == decay_ms, > false → climb
	assert_equal(note.x, 1, "at-boundary call still ascends (not yet decayed)")


# --- pitch_mult_for(): pure helper ---

func test_pitch_mult_at_chord_bed_octave() -> void:
	print("test_pitch_mult_at_chord_bed_octave")
	var chord := PackedFloat32Array([1.0, 1.25, 1.5, 1.875])
	assert_near(MenuHoverArpeggiator.pitch_mult_for(0, 0, chord), 1.0, 0.0001,
		"note 0, octave 0 → chord[0]")
	assert_near(MenuHoverArpeggiator.pitch_mult_for(2, 0, chord), 1.5, 0.0001,
		"note 2, octave 0 → chord[2]")


func test_pitch_mult_octave_up() -> void:
	print("test_pitch_mult_octave_up")
	var chord := PackedFloat32Array([1.0, 1.25])
	assert_near(MenuHoverArpeggiator.pitch_mult_for(0, 1, chord), 2.0, 0.0001,
		"octave +1 doubles pitch")
	assert_near(MenuHoverArpeggiator.pitch_mult_for(1, 2, chord), 5.0, 0.0001,
		"octave +2 × chord[1] = 1.25 × 4")


func test_pitch_mult_octave_down() -> void:
	print("test_pitch_mult_octave_down")
	var chord := PackedFloat32Array([1.0])
	assert_near(MenuHoverArpeggiator.pitch_mult_for(0, -1, chord), 0.5, 0.0001,
		"octave -1 halves pitch")


func test_pitch_mult_clamps_out_of_range_note() -> void:
	print("test_pitch_mult_clamps_out_of_range_note")
	var chord := PackedFloat32Array([1.0, 1.25])
	# note_idx beyond the chord's note count clamps to the last note rather
	# than panicking — defensive against caller drift.
	assert_near(MenuHoverArpeggiator.pitch_mult_for(99, 0, chord), 1.25, 0.0001,
		"clamps note_idx to last available")


func test_pitch_mult_empty_chord_returns_unity() -> void:
	print("test_pitch_mult_empty_chord_returns_unity")
	var empty := PackedFloat32Array()
	assert_near(MenuHoverArpeggiator.pitch_mult_for(0, 0, empty), 1.0, 0.0001,
		"empty chord defaults to unity pitch")
