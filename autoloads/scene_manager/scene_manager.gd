extends Node

# signal upgrade_purchased(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType, new_level: int)
# signal 


func set_new_scene(new_scene: PackedScene) -> void:
	var current_scene = get_tree().current_scene
	
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100
	add_child(canvas_layer)     

	var overlay = ColorRect.new()	
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(overlay)

	var new_scene_instantiated = new_scene.instantiate()
	
	var tween_fade_out := create_tween()
	tween_fade_out.tween_property(overlay, "color:a", 1.0, 1.0) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween_fade_out.tween_callback(func():
		if current_scene:
			current_scene.queue_free()
		
		get_tree().root.add_child(new_scene_instantiated)     
		get_tree().current_scene = new_scene_instantiated

		var tween_fade_in = create_tween()

		tween_fade_in.tween_property(overlay, "color:a", 0.0, 1.0) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween_fade_in.tween_callback(func():
			
			canvas_layer.queue_free()
		))





