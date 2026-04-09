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


func _process(_delta: float) -> void:
	if not _shaking:
		set_process(false)
		return
	var t: VisualTheme = ThemeProvider.theme
	var progress: float = LevelManager.get_progress()
	var shake_range: float = (progress - t.level_bar_shake_threshold) / (1.0 - t.level_bar_shake_threshold)
	var min_intensity: float = t.level_bar_shake_max_intensity * t.level_bar_shake_min_pct
	var intensity: float = lerpf(min_intensity, t.level_bar_shake_max_intensity, clampf(shake_range, 0.0, 1.0))
	var dy: float = randf_range(-intensity, intensity)
	hbox.offset_top = _base_offset_top + dy
	hbox.offset_bottom = _base_offset_bottom + dy


func _on_level_changed(_new_level: int) -> void:
	_update_display()


func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _cap: int) -> void:
	_update_display()


func _on_level_up_ready(_level: int, _level_data: LevelData) -> void:
	_stop_shaking()
	_spawn_particles()
	_spawn_shockwave_rings()


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


func _spawn_particles() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var currency: int = LevelManager.get_active_currency()
	var color: Color = t.get_coin_color(currency)
	var bar_global: Vector2 = hbox.global_position
	var bar_width: float = hbox.size.x

	for i in t.level_up_particle_count:
		var particle := ColorRect.new()
		particle.size = Vector2(6, 6)
		particle.color = color
		particle.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var start_x: float = bar_global.x + randf() * bar_width
		var start_y: float = bar_global.y
		particle.position = Vector2(start_x, start_y)
		_particle_overlay.add_child(particle)

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
	var bar_center: Vector2 = hbox.global_position + hbox.size * 0.5
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var uv_center: Vector2 = bar_center / viewport_size
	VfxUtils.spawn_shockwave(self, uv_center,
		ring_count = 1,
		duration = t.prestige_ring_duration / 3.0,
	)
