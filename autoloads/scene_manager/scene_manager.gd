extends Node

var _transitioning: bool = false

## Transitions to a new scene with an optional visual fade and theme swap.
## If theme is provided, it is applied at the midpoint (screen fully black)
## so the old scene never shows the new theme and the new scene initializes
## with the correct theme already active.
func set_new_scene(new_scene: PackedScene, instant: bool = false, theme: ThemeProvider.Kind = -1) -> void:
	if _transitioning:
		print("[SceneManager] Transition already in progress — ignoring.")
		return
	_transitioning = true
	SaveManager.save_game()
	var current_scene := get_tree().current_scene

	if instant:
		if theme >= 0:
			ThemeProvider.set_theme(theme)
		var instant_scene := new_scene.instantiate()
		if current_scene:
			current_scene.queue_free()
		get_tree().root.add_child(instant_scene)
		get_tree().current_scene = instant_scene
		_transitioning = false
		return

	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 100
	get_tree().root.add_child(canvas_layer)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(overlay)

	AudioManager.silence(1.0)

	var tween_fade_out := create_tween()
	tween_fade_out.tween_property(overlay, "color:a", 1.0, 1.0) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween_fade_out.tween_callback(func():
		if current_scene:
			current_scene.queue_free()

		if theme >= 0:
			ThemeProvider.set_theme(theme)
		var new_scene_instantiated := new_scene.instantiate()
		get_tree().root.add_child(new_scene_instantiated)
		get_tree().current_scene = new_scene_instantiated
		AudioManager.unsilence()

		var tween_fade_in := create_tween()
		tween_fade_in.tween_property(overlay, "color:a", 0.0, 1.0) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween_fade_in.tween_callback(func():
			canvas_layer.queue_free()
			_transitioning = false
		)
	)
