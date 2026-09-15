extends "res://test/test_base.gd"

## Tilt slider layout regression — run with:
##   godot --headless --scene res://test/test_tilt_slider_layout.tscn
##
## The slider shipped once resolving to (-140, -70), entirely off the top-left of
## the screen. A Control parented to a Node3D anchors against the VIEWPORT, so an
## unanchored root is a 0x0 rect at the origin and every child resolves against
## THAT — copying DropSection's child layout without also copying its instance
## anchor override in plinko_board.tscn reproduces the bug exactly.
##
## Note a zero-HEIGHT root is fine and is what DropSection does too: the instance
## override pins a single y, and the contents grow around it. What matters is
## where the contents land, which is what this asserts.


func _run_tests() -> void:
	print("\n=== Tilt Slider Layout Tests ===\n")
	var board: PlinkoBoard = preload("res://entities/plinko_board/plinko_board.tscn").instantiate()
	add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame

	var slider: Control = board.get_node("TiltSlider")
	var vbox: Control = slider.get_node("VBox")
	var viewport: Vector2 = get_viewport().get_visible_rect().size

	print("viewport:    %s" % viewport)
	print("TiltSlider:  P %s  S %s" % [slider.global_position, slider.size])
	print("VBox:        P %s  S %s" % [vbox.global_position, vbox.size])

	assert_true(vbox.size.x > 0.0 and vbox.size.y > 0.0,
		"the slider contents have a real rect")
	assert_true(vbox.global_position.x >= 0.0 and vbox.global_position.y >= 0.0,
		"the contents are not off the top-left of the screen")
	assert_true(vbox.global_position.x + vbox.size.x <= viewport.x,
		"and not off the right edge")
	assert_true(vbox.global_position.y + vbox.size.y <= viewport.y,
		"and not off the bottom edge")

	# Horizontally centred, like the drop buttons above it.
	var centre_x: float = vbox.global_position.x + vbox.size.x / 2.0
	assert_near(centre_x, viewport.x / 2.0, 1.0, "the slider is centred on screen")

	# Below the drop buttons rather than overlapping them.
	var drop: Control = board.get_node("DropSection/DropButtons")
	assert_true(vbox.global_position.y >= drop.global_position.y + drop.size.y,
		"the slider sits below the drop buttons")

	board.queue_free()
	print("\n=== Done ===\n")
