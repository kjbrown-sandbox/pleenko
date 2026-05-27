class_name AutodropperIntroAnimator
extends Node

## Plays the first-time autodropper intro: sparkle particles fly from the
## autodropper upgrade row in CoinValues to the gold drop button, the drop
## button transforms to reveal its +/– controls, and the + button pulses until
## the player clicks it.
##
## Wired by Main._setup_normal() via setup(). Not active during challenges.

var _board_manager: BoardManager
var _coin_values: Node
var _canvas_layer: CanvasLayer
var _particle_overlay: Control
var _is_animating: bool = false
var _completed: bool = false
var _plus_pulse_tween: Tween
var _pulsing_drop_bar: HBoxContainer


func setup(board_manager: BoardManager, coin_values: Node, canvas_layer: CanvasLayer) -> void:
	_board_manager = board_manager
	_coin_values = coin_values
	_canvas_layer = canvas_layer
	board_manager.first_autodropper_purchased.connect(_on_first_autodropper_purchased)


func _on_first_autodropper_purchased() -> void:
	if _is_animating:
		return
	_is_animating = true

	var source: Vector2 = _get_source_position()
	var target: Vector2 = _get_target_position()

	if target == Vector2.ZERO:
		# Drop button not yet positioned — skip animation and complete directly.
		_complete_intro()
		return

	_particle_overlay = Control.new()
	_particle_overlay.top_level = true
	_particle_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Add to the CanvasLayer so particles render above the 3D scene.
	_canvas_layer.add_child(_particle_overlay)

	_spawn_particles(source, target)


func _get_source_position() -> Vector2:
	if not is_instance_valid(_coin_values):
		return Vector2.ZERO
	var row: UpgradeRow = _coin_values.get_upgrade_row(Enums.UpgradeType.AUTODROPPER)
	if is_instance_valid(row):
		return row.get_global_rect().get_center()
	# Row not materialized yet — fall back to bottom of CoinValues container.
	var cv := _coin_values as Control
	if cv:
		return cv.get_global_rect().get_center()
	return Vector2.ZERO


func _get_target_position() -> Vector2:
	var gold_board: PlinkoBoard = _find_gold_board()
	if not is_instance_valid(gold_board):
		return Vector2.ZERO
	return gold_board.get_drop_button_screen_center(&"GOLD_NORMAL")


func _find_gold_board() -> PlinkoBoard:
	if not is_instance_valid(_board_manager):
		return null
	for board in _board_manager.get_boards():
		if board.board_type == Enums.BoardType.GOLD:
			return board
	return null


func _spawn_particles(source: Vector2, target: Vector2) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var color: Color = t.get_coin_color(Enums.CurrencyType.GOLD_COIN)
	var particles: Array[ColorRect] = []

	# Phase 1: Burst upward from the source position.
	for i in t.level_up_particle_count:
		var particle := ColorRect.new()
		particle.size = Vector2(6, 6)
		particle.color = color
		particle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		particle.position = source
		_particle_overlay.add_child(particle)
		particles.append(particle)

		var scatter_x: float = source.x + randf_range(-60.0, 60.0)
		var scatter_y: float = source.y - randf_range(80.0, 200.0)
		var burst_duration: float = t.level_up_particle_burst_duration * randf_range(0.7, 1.0)

		var tween := particle.create_tween()
		tween.tween_property(particle, "position", Vector2(scatter_x, scatter_y), burst_duration) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Phase 2: After burst, swoop all particles toward the drop button.
	var swoop_timer := get_tree().create_timer(t.level_up_particle_burst_duration)
	swoop_timer.timeout.connect(func():
		_swoop_particles(particles, target)
	)


func _swoop_particles(particles: Array[ColorRect], target: Vector2) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var arrived := [0]
	var total := particles.size()

	for particle in particles:
		if not is_instance_valid(particle):
			arrived[0] += 1
			if arrived[0] >= total:
				_on_all_particles_arrived()
			continue

		var swoop_duration: float = t.level_up_particle_swoop_duration * randf_range(0.8, 1.2)
		var tween := particle.create_tween()
		tween.tween_property(particle, "position", target, swoop_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(func():
			particle.queue_free()
			arrived[0] += 1
			if arrived[0] >= total:
				_on_all_particles_arrived()
		)


func _on_all_particles_arrived() -> void:
	# Guard against re-entry: per-particle tween_callbacks all race to call
	# this once the counter hits total. The first call completes the intro.
	if _completed:
		return
	_completed = true
	if is_instance_valid(_particle_overlay):
		_particle_overlay.queue_free()
		_particle_overlay = null
	_complete_intro()


func _complete_intro() -> void:
	_is_animating = false

	if not is_instance_valid(_board_manager):
		return

	_board_manager.reveal_autodropper_controls()
	OnboardingProgress.mark_autodropper_intro_seen()
	SaveManager.save_game()

	# Start pulse on the + button and stop it on the player's first + click.
	var gold_board: PlinkoBoard = _find_gold_board()
	if not is_instance_valid(gold_board):
		return

	var drop_bar: HBoxContainer = gold_board.get_drop_button(&"GOLD_NORMAL")
	if not is_instance_valid(drop_bar):
		return

	_pulsing_drop_bar = drop_bar
	_plus_pulse_tween = ThemeProvider.theme.blink_scale_fade(drop_bar.plus_button, 1.05, 0.5)
	drop_bar.plus_pressed.connect(_on_first_plus_pressed, CONNECT_ONE_SHOT)


func _on_first_plus_pressed() -> void:
	if is_instance_valid(_plus_pulse_tween):
		_plus_pulse_tween.kill()
		_plus_pulse_tween = null
	if is_instance_valid(_pulsing_drop_bar):
		# blink_scale_fade leaves the button mid-tween; restore neutral state.
		_pulsing_drop_bar.plus_button.scale = Vector2.ONE
		_pulsing_drop_bar.plus_button.modulate.a = 1.0
	_pulsing_drop_bar = null
