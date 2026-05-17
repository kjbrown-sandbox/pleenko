class_name DeflectorIntroAnimator
extends Node

## Plays the first-time Deflector intro: sparkle particles fly from the
## Deflector upgrade row on the orange board to the peg field, signalling that
## the player can now click pegs to place deflectors. The editor itself is
## already enabled (PlinkoBoard reacts to UpgradeManager.upgrade_purchased), so
## this animator is purely the discoverability cue.
##
## Wired by Main._setup_normal() via setup(). Not active during challenges.

var _board_manager: BoardManager
var _coin_values: Node
var _canvas_layer: CanvasLayer
var _particle_overlay: Control
var _is_animating: bool = false
var _completed: bool = false


func setup(board_manager: BoardManager, coin_values: Node, canvas_layer: CanvasLayer) -> void:
	_board_manager = board_manager
	_coin_values = coin_values
	_canvas_layer = canvas_layer
	board_manager.first_deflector_purchased.connect(_on_first_deflector_purchased)


func _on_first_deflector_purchased() -> void:
	if _is_animating or _completed:
		return
	_is_animating = true

	var source: Vector2 = _get_source_position()
	var target: Vector2 = _get_target_position()

	if source == Vector2.ZERO or target == Vector2.ZERO:
		# Positions not ready yet — bail WITHOUT marking it seen so the next
		# Deflector purchase retries the intro (don't burn the one-shot).
		_is_animating = false
		return

	_particle_overlay = Control.new()
	_particle_overlay.top_level = true
	_particle_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_particle_overlay)

	_spawn_particles(source, target)


# Deflector is a universal upgrade — sparkle to / hint on whatever board the
# player is currently looking at, not a fixed one (they may not be on orange).
func _target_board() -> PlinkoBoard:
	if not is_instance_valid(_board_manager):
		return null
	return _board_manager.get_active_board()


func _get_source_position() -> Vector2:
	# Deflector is a universal upgrade — its row lives in the CoinValues HUD.
	if not is_instance_valid(_coin_values):
		return Vector2.ZERO
	var row: UpgradeRow = _coin_values.get_upgrade_row(Enums.UpgradeType.PEG_DEFLECTOR)
	if is_instance_valid(row):
		return row.get_global_rect().get_center()
	var cv := _coin_values as Control
	if cv:
		return cv.get_global_rect().get_center()
	return Vector2.ZERO


func _get_target_position() -> Vector2:
	var board := _target_board()
	if not is_instance_valid(board):
		return Vector2.ZERO
	return board.get_center_peg_screen_position()


func _spawn_particles(source: Vector2, target: Vector2) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var board := _target_board()
	var currency := TierRegistry.primary_currency(board.board_type) if board \
		else Enums.CurrencyType.GOLD_COIN
	var color: Color = t.get_coin_color(currency)
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

	# Phase 2: After the burst, swoop all particles toward the peg field.
	var swoop_timer := get_tree().create_timer(t.level_up_particle_burst_duration)
	swoop_timer.timeout.connect(func() -> void:
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
		tween.tween_callback(func() -> void:
			particle.queue_free()
			arrived[0] += 1
			if arrived[0] >= total:
				_on_all_particles_arrived()
		)


func _on_all_particles_arrived() -> void:
	# Per-particle tween_callbacks all race here; the first one wins.
	if _completed:
		return
	if is_instance_valid(_particle_overlay):
		_particle_overlay.queue_free()
		_particle_overlay = null
	_complete_intro()


func _complete_intro() -> void:
	if _completed:
		return
	_completed = true
	_is_animating = false
	# Leave a pulsing hint on the center peg until the player places one.
	var board := _target_board()
	if is_instance_valid(board):
		board.start_deflector_center_hint()
	OnboardingProgress.mark_deflector_intro_seen()
	SaveManager.save_game()
