class_name DropSection
extends Control

@onready var _drop_rate_label: RichTextLabel = $DropRateLabel

## True while the first-queue-purchase intro owns the rate label (particles in
## flight + typewriter rolling out). Normal set_drop_rate_text calls are ignored
## until it finishes so the rollout isn't clobbered.
var _rate_intro_active: bool = false
var _rate_intro_text_started: bool = false
var _rate_intro_overlay: Control


func _ready() -> void:
	_apply_theme()
	ThemeProvider.theme_changed.connect(_apply_theme)


func _exit_tree() -> void:
	if ThemeProvider.theme_changed.is_connected(_apply_theme):
		ThemeProvider.theme_changed.disconnect(_apply_theme)


func _apply_theme() -> void:
	if not _drop_rate_label:
		return
	var t: VisualTheme = ThemeProvider.theme
	var fallback_font: Font = preload("res://style_lab/VendSans-Bold.ttf")
	var btn_font: Font = t.button_font if t.button_font else fallback_font
	# Font SIZE is driven separately by PlinkoBoard (set_rate_font_size) to match
	# the "no auto room" label, so it isn't set here (would clobber the match).
	_drop_rate_label.add_theme_color_override("default_color", t.normal_text_color)
	_drop_rate_label.add_theme_font_override("normal_font", btn_font)


## Drop-rate readout (bbcode) shown to the right of the gate. Caller (PlinkoBoard)
## builds the text via FormatUtils.drop_rate_text so the decomposition + bolding
## live in one place. Empty text hides the label.
func set_drop_rate_text(text: String) -> void:
	if not _drop_rate_label:
		return
	if _rate_intro_active:
		return  # the queue-unlock intro owns the label until its typewriter ends
	_drop_rate_label.text = text
	_drop_rate_label.visible_characters = -1  # show all (clears any prior reveal)
	_drop_rate_label.visible = not text.is_empty()


## Anchor the rate label to a screen-space point (the projected spawn point of
## the active board). Caller is responsible for any offset.
func set_drop_rate_position(viewport_pos: Vector2) -> void:
	if _drop_rate_label:
		_drop_rate_label.global_position = viewport_pos


## Rate readout font size (px), driven by PlinkoBoard to match the on-screen
## height of the 3D "no auto room" label at the current camera zoom.
func set_rate_font_size(px: int) -> void:
	if not _drop_rate_label:
		return
	_drop_rate_label.add_theme_font_size_override("normal_font_size", px)
	# Pull the two lines closer together (negative separation, scaled to size).
	_drop_rate_label.add_theme_constant_override("line_separation", -int(round(px * 0.2)))


## First-queue-purchase flourish: particles burst from `source` (the queue
## upgrade button) and swoop to the new queue slot (`target`), both in viewport
## coords. The old readout stays put during the flight; once the particles land,
## `new_text` rolls out letter by letter. `on_done` is called when the rollout
## completes (or if the intro can't run), re-enabling normal updates upstream.
func play_queue_unlock(source: Vector2, target: Vector2, new_text: String, particle_color: Color, on_done: Callable) -> void:
	if not _drop_rate_label or _rate_intro_active:
		on_done.call()
		return
	_rate_intro_active = true
	_rate_intro_text_started = false
	_spawn_rate_intro_particles(source, target, particle_color, new_text, on_done)


func _spawn_rate_intro_particles(source: Vector2, target: Vector2, color: Color, new_text: String, on_done: Callable) -> void:
	var t: VisualTheme = ThemeProvider.theme
	_rate_intro_overlay = Control.new()
	_rate_intro_overlay.top_level = true
	_rate_intro_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rate_intro_overlay)

	var particles: Array[ColorRect] = []
	for i in t.level_up_particle_count:
		var particle := ColorRect.new()
		particle.size = Vector2(6, 6)
		particle.color = color
		particle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		particle.position = source
		_rate_intro_overlay.add_child(particle)
		particles.append(particle)

		var scatter := source + Vector2(randf_range(-60.0, 60.0), -randf_range(80.0, 200.0))
		var burst_duration: float = t.level_up_particle_burst_duration * randf_range(0.7, 1.0)
		var tween := particle.create_tween()
		tween.tween_property(particle, "position", scatter, burst_duration) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# After the burst, swoop everything to the new queue slot.
	var swoop_timer := get_tree().create_timer(t.level_up_particle_burst_duration)
	swoop_timer.timeout.connect(func(): _swoop_rate_intro_particles(particles, target, new_text, on_done))


func _swoop_rate_intro_particles(particles: Array[ColorRect], target: Vector2, new_text: String, on_done: Callable) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var arrived := [0]
	var total := particles.size()
	for particle in particles:
		if not is_instance_valid(particle):
			arrived[0] += 1
			if arrived[0] >= total:
				_on_rate_intro_arrived(new_text, on_done)
			continue
		var swoop_duration: float = t.level_up_particle_swoop_duration * randf_range(0.8, 1.2)
		var tween := particle.create_tween()
		tween.tween_property(particle, "position", target, swoop_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(func():
			particle.queue_free()
			arrived[0] += 1
			if arrived[0] >= total:
				_on_rate_intro_arrived(new_text, on_done)
		)


## Once every particle lands (guarded against the per-particle callback race),
## tear down the overlay and type the new readout out letter by letter.
func _on_rate_intro_arrived(new_text: String, on_done: Callable) -> void:
	if _rate_intro_text_started:
		return
	_rate_intro_text_started = true
	if is_instance_valid(_rate_intro_overlay):
		_rate_intro_overlay.queue_free()
		_rate_intro_overlay = null
	if not _drop_rate_label:
		_rate_intro_active = false
		on_done.call()
		return
	# Reveal via visible_characters (not substring) so the bbcode [b] tags stay
	# intact — substringing would slice a tag mid-reveal.
	_drop_rate_label.text = new_text
	_drop_rate_label.visible = true
	_drop_rate_label.visible_characters = 0
	var total_chars: int = _drop_rate_label.get_total_character_count()
	if total_chars <= 0:
		_drop_rate_label.visible_characters = -1
		_rate_intro_active = false
		on_done.call()
		return
	var char_delay: float = ThemeProvider.theme.typewriter_char_delay
	var tween := create_tween()
	for i in total_chars:
		tween.tween_callback(func(): _drop_rate_label.visible_characters = i + 1)
		tween.tween_interval(char_delay)
	tween.tween_callback(func():
		_drop_rate_label.visible_characters = -1
		_rate_intro_active = false
		on_done.call()
	)
