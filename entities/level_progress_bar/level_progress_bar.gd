extends HBoxContainer

var level_label: Label
var progress_bar: ProgressBar
var progress_label: Label

var _shaking := false
var _base_offset_left: float
var _base_offset_right: float
var _base_offset_top: float
var _base_offset_bottom: float
var _particle_overlay: Control
var _shockwave_layers: Array[CanvasLayer] = []


func _ready() -> void:
	set_process(false)

	# Anchor to bottom of screen, full width
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_top = -30
	offset_bottom = 0
	offset_left = 10
	offset_right = -10

	# Level label: "LVL 0/10"
	level_label = Label.new()
	level_label.text = "LVL 0"
	level_label.custom_minimum_size.x = 80
	add_child(level_label)

	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.show_percentage = false
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.value = 0.0
	progress_bar.custom_minimum_size.y = 20
	add_child(progress_bar)

	# Progress text: "0/10"
	progress_label = Label.new()
	progress_label.custom_minimum_size.x = 80
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(progress_label)

	# Particle overlay — uses top_level to escape HBoxContainer layout
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
	_base_offset_left = offset_left
	_base_offset_right = offset_right
	_base_offset_top = offset_top
	_base_offset_bottom = offset_bottom


func _process(_delta: float) -> void:
	if not _shaking:
		set_process(false)
		return
	var t: VisualTheme = ThemeProvider.theme
	var progress: float = LevelManager.get_progress()
	var shake_range: float = (progress - t.level_bar_shake_threshold) / (1.0 - t.level_bar_shake_threshold)
	var intensity: float = lerpf(0.0, t.level_bar_shake_max_intensity, clampf(shake_range, 0.0, 1.0))
	# Use offsets for shaking (anchored controls ignore position changes)
	var dx: float = randf_range(-intensity, intensity)
	var dy: float = randf_range(-intensity, intensity)
	offset_left = _base_offset_left + dx
	offset_right = _base_offset_right + dx
	offset_top = _base_offset_top + dy
	offset_bottom = _base_offset_bottom + dy


func _on_level_changed(_new_level: int) -> void:
	_update_display()


func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _cap: int) -> void:
	_update_display()


func _on_level_up_ready(_level: int, _level_data: LevelData) -> void:
	# Stop shaking and reset offsets
	_stop_shaking()
	_spawn_particles()
	_spawn_shockwave_rings()


func _stop_shaking() -> void:
	_shaking = false
	offset_left = _base_offset_left
	offset_right = _base_offset_right
	offset_top = _base_offset_top
	offset_bottom = _base_offset_bottom
	set_process(false)


func _update_display() -> void:
	var total: int = LevelManager.get_total_levels()
	level_label.text = "LVL %d/%d" % [LevelManager.current_level + 1, total]

	var threshold: int = LevelManager.get_next_threshold()
	if threshold <= 0:
		progress_bar.value = 1.0
		progress_label.text = "MAX"
	else:
		var currency: int = LevelManager.get_active_currency()
		var balance: int = CurrencyManager.get_balance(currency)
		progress_bar.max_value = threshold
		progress_bar.value = mini(balance, threshold)
		progress_label.text = "%d/%d" % [balance, threshold]

	# Check if we should start shaking
	var progress: float = LevelManager.get_progress()
	var t: VisualTheme = ThemeProvider.theme
	if progress >= t.level_bar_shake_threshold and progress < 1.0:
		if not _shaking:
			_shaking = true
			set_process(true)
	elif _shaking:
		_stop_shaking()


func _spawn_particles() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var currency: int = LevelManager.get_active_currency()
	var color: Color = t.get_coin_color(currency)
	var bar_global: Vector2 = global_position
	var bar_width: float = size.x

	for i in t.level_up_particle_count:
		var particle := ColorRect.new()
		particle.size = Vector2(6, 6)
		particle.color = color
		particle.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Random horizontal position across the bar (global coords since overlay is top_level)
		var start_x: float = bar_global.x + randf() * bar_width
		var start_y: float = bar_global.y
		particle.position = Vector2(start_x, start_y)
		_particle_overlay.add_child(particle)

		# Tween upward with random spread and fade out
		var end_x: float = start_x + randf_range(-40.0, 40.0)
		var end_y: float = start_y - randf_range(80.0, 200.0)
		var duration: float = t.level_up_particle_duration * randf_range(0.7, 1.0)

		var tween := particle.create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "position", Vector2(end_x, end_y), duration) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(particle, "modulate:a", 0.0, duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.chain().tween_callback(particle.queue_free)


func _spawn_shockwave_rings() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var bar_center: Vector2 = global_position + size * 0.5
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var uv_center: Vector2 = bar_center / viewport_size

	for i in t.prestige_ring_count:
		_spawn_single_ring(uv_center, t, i * t.prestige_ring_stagger)


func _spawn_single_ring(uv_center: Vector2, t: VisualTheme, delay: float) -> void:
	var shockwave_shader: Shader = preload("res://entities/prestige_vfx/shockwave.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shockwave_shader
	mat.set_shader_parameter("center", uv_center)
	mat.set_shader_parameter("radius", 0.0)
	mat.set_shader_parameter("ring_width", 0.06)
	mat.set_shader_parameter("distortion_strength", 0.008)

	var canvas := CanvasLayer.new()
	canvas.layer = 90
	get_tree().root.add_child(canvas)

	var rect := ColorRect.new()
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(rect)
	_shockwave_layers.append(canvas)

	var tween := create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_method(func(r: float): mat.set_shader_parameter("radius", r), 0.0, 1.5, t.prestige_ring_duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func():
		_shockwave_layers.erase(canvas)
		canvas.queue_free()
	)
