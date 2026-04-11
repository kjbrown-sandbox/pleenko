extends Control

@onready var hbox: HBoxContainer = $HBoxContainer
@onready var progress_bar: HBoxContainer = $HBoxContainer/ProgressBar
@onready var level_label: Label = $HBoxContainer/LevelLabel

var max_value: int = 0
var value: int = 0

var _shaking := false
var _base_offset_top: float
var _base_offset_bottom: float
var _particle_overlay: Control
var _board_manager: Node
var _camera: Camera3D

# Shake re-roll throttle: hold the same offset for this many seconds before
# generating a new one. Lower frequency = less jittery, more readable.
const SHAKE_REROLL_INTERVAL: float = 0.06
var _shake_reroll_accum: float = 0.0
var _shake_dy: float = 0.0


func setup(board_manager: Node, cam: Camera3D) -> void:
	_board_manager = board_manager
	_camera = cam


func _ready() -> void:
	set_process(false)

	var t: VisualTheme = ThemeProvider.theme
	level_label.add_theme_color_override("font_color", t.normal_text_color)
	progress_bar.setup(t.button_enabled_color, t.button_disabled_color)
	progress_bar.main_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.apply_fill_colors(false)

	# Particle overlay — uses top_level to escape layout
	_particle_overlay = Control.new()
	_particle_overlay.top_level = true
	_particle_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_particle_overlay)

	LevelManager.level_changed.connect(_on_level_changed)
	LevelManager.level_up_ready.connect(_on_level_up_ready)
	CurrencyManager.currency_changed.connect(_on_currency_changed)

	_update_display()
	_store_base_offsets.call_deferred()


func _store_base_offsets() -> void:
	_base_offset_top = hbox.offset_top
	_base_offset_bottom = hbox.offset_bottom


func _process(delta: float) -> void:
	if not _shaking:
		set_process(false)
		return
	_shake_reroll_accum += delta
	if _shake_reroll_accum >= SHAKE_REROLL_INTERVAL:
		_shake_reroll_accum = 0.0
		var t: VisualTheme = ThemeProvider.theme
		var progress: float = LevelManager.get_progress()
		var shake_range: float = (progress - t.level_bar_shake_threshold) / (1.0 - t.level_bar_shake_threshold)
		var min_intensity: float = t.level_bar_shake_max_intensity * t.level_bar_shake_min_pct
		var intensity: float = lerpf(min_intensity, t.level_bar_shake_max_intensity, clampf(shake_range, 0.0, 1.0))
		_shake_dy = randf_range(-intensity, intensity)
	hbox.offset_top = _base_offset_top + _shake_dy
	hbox.offset_bottom = _base_offset_bottom + _shake_dy


func _on_level_changed(_new_level: int) -> void:
	_update_display()


func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _cap: int) -> void:
	_update_display()


func _on_level_up_ready(_level: int, level_data: LevelData) -> void:
	if not _board_manager:
		# Not set up yet (e.g. during save load) — claim immediately
		LevelManager.claim_rewards()
		return

	_stop_shaking()
	_spawn_shockwave_rings()

	var targets: Array[Vector2] = _get_reward_targets(level_data.rewards)
	_spawn_particles_with_swoop(targets)


func _stop_shaking() -> void:
	_shaking = false
	hbox.offset_top = _base_offset_top
	hbox.offset_bottom = _base_offset_bottom
	set_process(false)


func _update_display() -> void:
	var total := LevelManager.get_total_levels()
	level_label.text = "LVL %d/%d" % [LevelManager.current_level + 1, total + 1]

	var threshold: int = LevelManager.get_next_threshold()
	if threshold <= 0:
		progress_bar.set_fill(1.0)
		progress_bar.update_text("MAX")
	else:
		var currency := LevelManager.get_active_currency()
		var balance := CurrencyManager.get_balance(currency)
		max_value = threshold
		value = mini(balance, threshold)
		progress_bar.set_fill(float(value) / float(threshold))
		progress_bar.update_text("%d/%d %s" % [balance, threshold, FormatUtils.currency_name(currency)])

	# Check if we should start shaking
	var progress: float = LevelManager.get_progress()
	var t: VisualTheme = ThemeProvider.theme
	if progress >= t.level_bar_shake_threshold and progress < 1.0:
		if not _shaking:
			_shaking = true
			set_process(true)
	elif _shaking:
		_stop_shaking()


# ── Reward target resolution ───────────────────────────────────────
# Returns an array of targets. Empty = scatter only (no swoop).
# One target = all particles converge. Two targets = particles split evenly.

func _get_reward_targets(rewards: Array[RewardData]) -> Array[Vector2]:
	for reward in rewards:
		match reward.type:
			RewardData.RewardType.DROP_COINS:
				return [_get_coin_drop_target(reward.target_board)]
			RewardData.RewardType.UNLOCK_UPGRADE:
				# In challenges where this upgrade is blocked, the board drops a
				# coin instead — aim particles at the coin spawn instead of the
				# (hidden) upgrade section.
				if ChallengeManager.is_active_challenge and not ChallengeManager.is_upgrade_allowed(reward.upgrade_type):
					return [_get_coin_drop_target(reward.board_type)]
				return [_get_upgrade_section_target(reward.upgrade_type)]
			RewardData.RewardType.UNLOCK_AUTODROPPER, \
			RewardData.RewardType.UNLOCK_ADVANCED_AUTODROPPER:
				return [_get_upgrade_section_target()]
			RewardData.RewardType.UNLOCK_ADVANCED_BUCKET:
				return _get_advanced_bucket_targets(reward.target_board)
	return []


## If upgrade_type is provided and the row already exists (e.g., a level-up that
## upgrades an existing row rather than unlocking a new one), target that row's
## center. Otherwise target the bottom of the upgrades container, which is where
## the next new row will materialize.
func _get_upgrade_section_target(upgrade_type: int = -1) -> Vector2:
	var board = _board_manager.get_active_board()
	var section = board.upgrade_section
	if upgrade_type >= 0 and section._rows.has(upgrade_type):
		var row: Control = section._rows[upgrade_type]
		return row.global_position + row.size * 0.5
	var container: VBoxContainer = section.upgrades_container
	return container.global_position + Vector2(container.size.x * 0.5, container.size.y)


func _get_coin_drop_target(target_board_type: int) -> Vector2:
	for board in _board_manager.get_boards():
		if board.board_type == target_board_type:
			var spawn_pos: Vector3 = board.global_position + Vector3(0, board.vertical_spacing + 0.2, 0)
			return _camera.unproject_position(spawn_pos)
	return Vector2(get_viewport().get_visible_rect().size.x * 0.5, 100)


func _get_advanced_bucket_targets(target_board_type: int) -> Array[Vector2]:
	# If the board has enough rows, target the two edge buckets.
	# Otherwise, scatter only (empty array).
	for board in _board_manager.get_boards():
		if board.board_type == target_board_type:
			var num_buckets: int = board.num_rows + 1
			var half: int = num_buckets / 2
			if half < board.distance_for_advanced_buckets:
				return []  # Not enough rows — scatter only
			# First and last bucket positions
			var buckets = board.buckets_container.get_children()
			if buckets.size() < 2:
				return []
			var left_pos: Vector2 = _camera.unproject_position(buckets[0].global_position)
			var right_pos: Vector2 = _camera.unproject_position(buckets[buckets.size() - 1].global_position)
			return [left_pos, right_pos]
	return []


# ── Two-phase particle animation ──────────────────────────────────

func _spawn_particles_with_swoop(targets: Array[Vector2]) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var currency: int = LevelManager.get_active_currency()
	var color: Color = t.get_coin_color(currency)
	var bar_global: Vector2 = hbox.global_position
	var bar_width: float = hbox.size.x
	var particles: Array[ColorRect] = []

	# Phase 1: Burst upward from the bar
	for i in t.level_up_particle_count:
		var particle := ColorRect.new()
		particle.size = Vector2(6, 6)
		particle.color = color
		particle.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var start_x: float = bar_global.x + randf() * bar_width
		var start_y: float = bar_global.y
		particle.position = Vector2(start_x, start_y)
		_particle_overlay.add_child(particle)
		particles.append(particle)

		var scatter_x: float = start_x + randf_range(-60.0, 60.0)
		var scatter_y: float = start_y - randf_range(80.0, 200.0)
		var burst_duration: float = t.level_up_particle_burst_duration * randf_range(0.7, 1.0)

		var tween := particle.create_tween()
		tween.tween_property(particle, "position", Vector2(scatter_x, scatter_y), burst_duration) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Phase 2: After burst, swoop or fade
	var swoop_timer := get_tree().create_timer(t.level_up_particle_burst_duration)
	swoop_timer.timeout.connect(func():
		if targets.is_empty():
			_fade_and_claim(particles)
		else:
			_swoop_particles_to_targets(particles, targets)
	)


func _swoop_particles_to_targets(particles: Array[ColorRect], targets: Array[Vector2]) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var state := [0]  # [arrived_count]
	var total := particles.size()

	for i in particles.size():
		var particle := particles[i]
		if not is_instance_valid(particle):
			state[0] += 1
			if state[0] >= total:
				LevelManager.claim_rewards()
			continue

		# Split particles across targets (e.g. left/right for advanced buckets)
		var target: Vector2 = targets[i % targets.size()]
		var swoop_duration: float = t.level_up_particle_swoop_duration * randf_range(0.8, 1.2)

		var tween := particle.create_tween()
		tween.tween_property(particle, "position", target, swoop_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(func():
			particle.queue_free()
			state[0] += 1
			if state[0] >= total:
				LevelManager.claim_rewards()
		)


## Radial burst at a world-space point, used for coin drop feedback. Unlike the
## level-up burst, particles scatter outward in all directions and fade out.
## Rate limiting is handled by the board before emission.
func spawn_drop_burst(world_pos: Vector3, color: Color) -> void:
	if not _camera:
		return
	var t: VisualTheme = ThemeProvider.theme
	var screen_pos: Vector2 = _camera.unproject_position(world_pos)
	var particle_size := Vector2(5, 5)
	var half_size: Vector2 = particle_size * 0.5

	for i in t.drop_burst_particle_count:
		var particle := ColorRect.new()
		particle.size = particle_size
		particle.color = color
		particle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		particle.position = screen_pos - half_size
		_particle_overlay.add_child(particle)

		var angle: float = randf() * TAU
		var distance: float = t.drop_burst_spread * randf_range(0.5, 1.0)
		var target: Vector2 = screen_pos + Vector2.from_angle(angle) * distance - half_size
		var duration: float = t.drop_burst_duration * randf_range(0.7, 1.0)

		var tween := particle.create_tween().set_parallel()
		tween.tween_property(particle, "position", target, duration) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(particle, "modulate:a", 0.0, duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.chain().tween_callback(particle.queue_free)


## No swoop target — particles fade out, then claim immediately.
func _fade_and_claim(particles: Array[ColorRect]) -> void:
	for particle in particles:
		if is_instance_valid(particle):
			var tween := particle.create_tween()
			tween.tween_property(particle, "modulate:a", 0.0, 0.4) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tween.tween_callback(particle.queue_free)
	# Claim after a short delay (don't wait for fade to finish)
	var claim_timer := get_tree().create_timer(0.2)
	claim_timer.timeout.connect(LevelManager.claim_rewards)


# ── Shockwave ─────────────────────────────────────────────────────

func _spawn_shockwave_rings() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var bar_center: Vector2 = hbox.global_position + hbox.size * 0.5
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var uv_center: Vector2 = bar_center / viewport_size
	VfxUtils.spawn_shockwave(self, uv_center, { "ring_count": 1, "duration": t.prestige_ring_duration / 3.0 })
