extends Control

@onready var hbox: HBoxContainer = $HBoxContainer
@onready var vbox: VBoxContainer = $HBoxContainer/VBox
@onready var milestone_label: Label = $MilestoneLabel
@onready var progress_label: Control = $ProgressLabel
@onready var progress_base_label: Label = $ProgressLabel/BaseLabel
@onready var progress_fill_clip: Control = $ProgressLabel/FillClip
@onready var progress_fill_label: Label = $ProgressLabel/FillClip/FillLabel
@onready var segments_hbox: HBoxContainer = $HBoxContainer/VBox/Segments

var _segment_panels: Array[Panel] = []
var _segment_styleboxes: Array[StyleBoxFlat] = []
var _segment_clips: Array[Control] = []
var _segment_fills: Array[ColorRect] = []
var _segment_weights: Array[float] = []
var _spacers: Array[Control] = []
var _spacer_visible: Array[bool] = []
var _tier_start_level: int = -1
## Lifecycle of the intro animation, in order:
## _in_intro=true & phase=NONE                 → bar laid out in tier-start
##                                               state (seg 0 full width).
## _waiting_for_rewards=true                   → burst spawned, fade running,
##                                               pre-shrink hold.
## phase=SHRINK / CASCADE                      → squish + cascade tweens.
## phase=DONE                                  → final state, post-cascade.
## They are sequential, never simultaneous.
enum IntroPhase { NONE, SHRINK, CASCADE, DONE }

var _in_intro: bool = false
var _waiting_for_rewards: bool = false  # transition detected, holding for cascade end
var _intro_phase: IntroPhase = IntroPhase.NONE
var _intro_anim_tween: Tween
var _intro_cascade_tween: Tween  # phase-2 tween — stored so _rebuild_bar can kill it
var _intro_held_particles: Array[ColorRect] = []
var _intro_held_targets: Array[Vector2] = []
var _intro_drift_tweens: Array[Tween] = []

# Calibrated so the visual width change distributes more linearly across the
# tween (a huge ratio like 1e6 makes seg 0 stay near 100% width until the
# very last instant — the squish looks slow→fast no matter the easing).
const INTRO_BIG_RATIO: float = 200.0
const INTRO_COLLAPSED_RATIO: float = 0.001
# Once this many milestones are acquired, the merged group is wide enough to
# host the X/Y label inside the bar (fill-bar-style text), so it stops floating
# above the bar. Tuned so the label fits across all the gold thresholds without
# clipping the milestone text on top.
const FILL_BAR_TEXT_MIN_ACTIVE_IDX: int = 3

var _particle_overlay: Control
var _board_manager: Node
var _camera: Camera3D
var _coin_values: Node


func setup(board_manager: Node, cam: Camera3D, coin_values: Node = null) -> void:
	_board_manager = board_manager
	_camera = cam
	_coin_values = coin_values


func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	milestone_label.add_theme_color_override("font_color", t.normal_text_color)
	milestone_label.add_theme_font_size_override("font_size", t.button_font_size)
	progress_base_label.add_theme_color_override("font_color", t.normal_text_color)
	progress_base_label.add_theme_font_size_override("font_size", t.button_font_size)
	progress_fill_label.add_theme_color_override("font_color", t.background_color)
	progress_fill_label.add_theme_font_size_override("font_size", t.button_font_size)

	# Particle overlay — uses top_level to escape layout
	_particle_overlay = Control.new()
	_particle_overlay.top_level = true
	_particle_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_particle_overlay)

	LevelManager.level_changed.connect(_on_level_changed)
	LevelManager.level_up_ready.connect(_on_level_up_ready)
	CurrencyManager.currency_changed.connect(_on_currency_changed)

	# Reposition the progress label when the bar resizes (window resize,
	# initial layout, or stretch-ratio change on rebuild).
	segments_hbox.resized.connect(_position_progress_label)

	_update_display()


func _on_level_changed(_new_level: int) -> void:
	_update_display()
	# If the bar's intro layout is now stale (current_level moved past the
	# tier's start) AND no animation flow took ownership, this signal came
	# from save-load (deserialize emits level_changed without level_up_ready).
	# Rebuild on the next idle frame to clear the intro layout.
	_resolve_stale_intro.call_deferred()


func _resolve_stale_intro() -> void:
	if not _in_intro:
		return
	if LevelManager.current_level <= _tier_start_level:
		return
	if _waiting_for_rewards or _intro_phase != IntroPhase.NONE:
		return  # live intro animation took over — leave it alone
	_rebuild_bar()
	_update_bar()


func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _cap: int) -> void:
	_update_display()


func _on_level_up_ready(_level: int, level_data: LevelData) -> void:
	if not _board_manager:
		LevelManager.claim_rewards()
		return

	_spawn_shockwave_rings()

	var targets: Array[Vector2] = _get_reward_targets(level_data.rewards)
	var is_final_milestone: bool = (
		not level_data.rewards.is_empty()
		and level_data.rewards[0].type == RewardData.RewardType.UNLOCK_ADVANCED_BUCKET
	)
	# Intro-transition flow only fires for the very first milestone crossed
	# from the tier's intro layout — and only via live player progress
	# (level_up_ready emit). Save-load uses level_changed only and is
	# handled by the deferred check in _on_level_changed.
	if _in_intro and LevelManager.current_level > _tier_start_level:
		_waiting_for_rewards = true
		_start_intro_transition(targets)
	elif is_final_milestone:
		# Last milestone of the tier — the whole bar disintegrates into
		# particles that fly to the (about to become "?") end buckets.
		_spawn_bar_explosion(targets)
	else:
		_spawn_particles_with_swoop(targets)


## Intro-transition orchestration. Particles burst immediately at the bar,
## then settle and hang. After burst_duration + 0.5s the shrink animation
## fires; on cascade completion the held particles swoop to the reward
## target (which is what calls LevelManager.claim_rewards).
func _start_intro_transition(targets: Array[Vector2]) -> void:
	_intro_held_particles = _spawn_intro_burst_particles()
	_intro_held_targets = targets

	# Fade both the in-bar numbers AND the milestone label to invisible.
	# Squish fires from the fade's own completion callback so there's no
	# gap between fade-end and shrink-start. Milestone fades back in at
	# phase 3 (cascade end).
	var fade_dur: float = 1.5
	milestone_label.create_tween().tween_property(milestone_label, "modulate:a", 0.0, fade_dur)
	var fade_tween := progress_label.create_tween()
	fade_tween.tween_property(progress_label, "modulate:a", 0.0, fade_dur)
	fade_tween.tween_callback(func():
		if not _waiting_for_rewards:
			return  # interrupted (e.g., tier rebuild)
		progress_label.visible = false
		progress_label.modulate.a = 1.0
		_waiting_for_rewards = false
		_in_intro = false
		_play_intro_to_live_animation()
	)


func _spawn_intro_burst_particles() -> Array[ColorRect]:
	var t: VisualTheme = ThemeProvider.theme
	# Milestone particles match the bar color (not the currency tint).
	var color: Color = t.normal_text_color
	var bar_global: Vector2 = segments_hbox.global_position
	var bar_width: float = segments_hbox.size.x
	var particles: Array[ColorRect] = []
	_intro_drift_tweens.clear()
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
		var burst_tween := particle.create_tween()
		burst_tween.tween_property(particle, "position", Vector2(scatter_x, scatter_y), burst_duration) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

		# After burst, the particle bobs gently around its scatter point so
		# it never feels frozen while the bar squishes + cascade plays.
		var drift_x: float = randf_range(-10.0, 10.0)
		var drift_y: float = randf_range(-10.0, 10.0)
		var drift_dur: float = randf_range(0.55, 0.85)
		var drift_tween := particle.create_tween().set_loops()
		drift_tween.tween_interval(burst_duration)
		drift_tween.tween_property(particle, "position",
			Vector2(scatter_x + drift_x, scatter_y + drift_y), drift_dur) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		drift_tween.tween_property(particle, "position",
			Vector2(scatter_x - drift_x, scatter_y - drift_y), drift_dur * 1.6) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		drift_tween.tween_property(particle, "position",
			Vector2(scatter_x, scatter_y), drift_dur) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		_intro_drift_tweens.append(drift_tween)
	return particles


# ── Segments + labels ─────────────────────────────────────────────────

func _update_display() -> void:
	var total: int = LevelManager.get_total_levels()
	var current: int = LevelManager.current_level

	var tier_start: int = (current / LevelManager.LEVELS_PER_TIER) * LevelManager.LEVELS_PER_TIER
	# Clamp to a valid tier range when we've maxed out everything available.
	if tier_start >= total and total > 0:
		tier_start = ((total - 1) / LevelManager.LEVELS_PER_TIER) * LevelManager.LEVELS_PER_TIER

	if tier_start != _tier_start_level:
		_tier_start_level = tier_start
		_rebuild_bar()

	_update_bar()

	if current >= total:
		milestone_label.text = "All milestones reached!"
		_set_progress_text("")
	else:
		var next: LevelData = LevelManager.levels[current]
		milestone_label.text = "Next milestone: %s" % _milestone_title(next)
		var threshold: int = next.threshold
		var balance: int = CurrencyManager.get_balance(LevelManager.get_active_currency())
		var currency_name: String = FormatUtils.currency_name(LevelManager.get_active_currency(), false)
		_set_progress_text("%d / %d %s" % [mini(balance, threshold), threshold, currency_name])


func _set_progress_text(s: String) -> void:
	progress_base_label.text = s
	progress_fill_label.text = s
	# Resize/reposition with the new text width so the FillClip doesn't
	# stay sized for the previous (shorter) text and chop off characters.
	_position_progress_label()


func _rebuild_bar() -> void:
	# Kill every tween that targets the bar's child nodes BEFORE we free the
	# children, otherwise tweens keep running against freed objects.
	# Phase-1 shrink (outer) AND phase-2 cascade (inner) are tracked
	# separately because the cascade is created in a tween_callback of the
	# outer tween — killing the outer doesn't stop the inner.
	if _intro_anim_tween:
		_intro_anim_tween.kill()
		_intro_anim_tween = null
	if _intro_cascade_tween:
		_intro_cascade_tween.kill()
		_intro_cascade_tween = null
	for dt in _intro_drift_tweens:
		if dt:
			dt.kill()
	_intro_drift_tweens.clear()
	for c in segments_hbox.get_children():
		segments_hbox.remove_child(c)
		c.queue_free()
	for p in _intro_held_particles:
		if is_instance_valid(p):
			p.queue_free()
	_intro_held_particles.clear()
	_intro_held_targets.clear()
	_intro_phase = IntroPhase.NONE
	_waiting_for_rewards = false
	_segment_panels.clear()
	_segment_styleboxes.clear()
	_segment_clips.clear()
	_segment_fills.clear()
	_segment_weights.clear()
	_spacers.clear()
	_spacer_visible.clear()

	var t: VisualTheme = ThemeProvider.theme
	var seg_color: Color = t.normal_text_color
	var spacer_width: float = 3.0

	# Width-weighted segments: gap between consecutive thresholds. First
	# milestone (7 coins) is tiny vs. the last (100 coins).
	var thresholds: Array[int] = []
	for i in LevelManager.LEVELS_PER_TIER:
		var level_idx: int = _tier_start_level + i
		if level_idx >= LevelManager.levels.size():
			break
		thresholds.append(LevelManager.levels[level_idx].threshold)
	if thresholds.is_empty():
		return

	var prev_threshold: int = 0
	for i in thresholds.size():
		_segment_weights.append(float(thresholds[i] - prev_threshold))
		prev_threshold = thresholds[i]

	var current: int = LevelManager.current_level
	# Intro state: starts ONLY when the player has yet to acquire any
	# milestone in this tier. Segment 0 takes the whole bar; segments 1..N-1
	# are collapsed + alpha 0 until the first milestone triggers the cascade.
	_in_intro = (current == _tier_start_level)

	for i in thresholds.size():
		# Spacer BEFORE this segment (between segment i-1 and segment i).
		# Driven by current_level: hidden when its milestone is acquired,
		# and its neighbouring segments collapse their facing borders.
		if i > 0:
			var spacer_idx: int = i - 1
			var visible_now: bool = (not _in_intro) and current <= _tier_start_level + spacer_idx
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(spacer_width, 0)
			spacer.visible = visible_now
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			segments_hbox.add_child(spacer)
			_spacers.append(spacer)
			_spacer_visible.append(visible_now)

		var seg := Panel.new()
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if _in_intro:
			# Segment 0 takes (almost) the whole bar; others collapse to 0.
			seg.size_flags_stretch_ratio = INTRO_BIG_RATIO if i == 0 else INTRO_COLLAPSED_RATIO
			if i > 0:
				seg.modulate.a = 0.0
		else:
			seg.size_flags_stretch_ratio = maxf(_segment_weights[i], INTRO_COLLAPSED_RATIO)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.TRANSPARENT
		sb.border_color = seg_color
		seg.add_theme_stylebox_override("panel", sb)
		_segment_styleboxes.append(sb)

		var clip := Control.new()
		clip.clip_contents = true
		clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Offsets are set in _apply_segment_styles so the inset collapses
		# on sides facing a merged neighbour (otherwise a 2.5px gap shows
		# through inside the merged group as a vertical bg seam).
		seg.add_child(clip)
		_segment_clips.append(clip)

		var fill_rect := ColorRect.new()
		fill_rect.color = seg_color
		fill_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fill_rect.anchor_right = 0.0
		fill_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(fill_rect)

		segments_hbox.add_child(seg)
		_segment_panels.append(seg)
		_segment_fills.append(fill_rect)

	_apply_segment_styles()
	_position_progress_label.call_deferred()


## Segments 0..current_level merge into one continuous pill — facing borders
## between adjacent acquired segments collapse to 0. Corner radii are only
## ever applied at the very ends of the whole bar (segment 0 left, last
## segment right); every middle corner stays square no matter what.
func _apply_segment_styles() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var bw: int = t.button_border_width
	var fill_inset: float = float(bw) - 0.5
	var r: int = t.button_border_radius
	var group_end: int = LevelManager.current_level - _tier_start_level
	var last_idx: int = _segment_styleboxes.size() - 1
	# During intro / pre-anim hold / phase-1 shrink, seg 0 is the only
	# visible segment and should render as a fully rounded standalone pill
	# (the "original level bar" look) regardless of current_level.
	var seg0_standalone: bool = _in_intro or _waiting_for_rewards or _intro_phase == IntroPhase.SHRINK

	for i in _segment_styleboxes.size():
		var in_group: bool = i <= group_end
		var left_exposed: bool
		var right_exposed: bool
		if in_group:
			left_exposed = (i == 0)
			right_exposed = (i == group_end)
		else:
			left_exposed = true
			right_exposed = true
		if seg0_standalone and i == 0:
			left_exposed = true
			right_exposed = true
		var sb: StyleBoxFlat = _segment_styleboxes[i]
		sb.border_width_top = bw
		sb.border_width_bottom = bw
		sb.border_width_left = bw if left_exposed else 0
		sb.border_width_right = bw if right_exposed else 0
		sb.corner_radius_top_left = r if i == 0 else 0
		sb.corner_radius_bottom_left = r if i == 0 else 0
		sb.corner_radius_top_right = r if (i == last_idx or (seg0_standalone and i == 0)) else 0
		sb.corner_radius_bottom_right = r if (i == last_idx or (seg0_standalone and i == 0)) else 0

		# Clip inset collapses on sides facing a merged neighbour. On those
		# sides we even extend the clip 1 px past the seam so adjacent fills
		# overlap and the sub-pixel layout gap can never show through as a
		# visible vertical line.
		var clip: Control = _segment_clips[i]
		var seam_overlap: float = 1.0
		clip.offset_left = fill_inset if left_exposed else -seam_overlap
		clip.offset_top = fill_inset
		clip.offset_right = -fill_inset if right_exposed else seam_overlap
		clip.offset_bottom = -fill_inset


func _update_bar() -> void:
	var current: int = LevelManager.current_level
	var balance: int = CurrencyManager.get_balance(LevelManager.get_active_currency())

	# Per-segment fill: fill grows/shrinks with balance through its threshold span.
	var prev_threshold: int = 0
	for i in _segment_fills.size():
		var level_idx: int = _tier_start_level + i
		if level_idx >= LevelManager.levels.size():
			break
		var threshold: int = LevelManager.levels[level_idx].threshold
		var span: int = threshold - prev_threshold
		var fill: float = clampf(float(balance - prev_threshold) / float(span), 0.0, 1.0) if span > 0 else 0.0
		_segment_fills[i].anchor_right = fill
		prev_threshold = threshold

	# Hold the bar in its intro layout while the intro animation flow runs
	# (set by _on_level_up_ready, cleared at phase 3). Skip spacer/style
	# updates so the seg-0-huge / others-alpha-0 layout stays put.
	if _waiting_for_rewards:
		_position_progress_label()
		return

	# Spacer i sits between segment i and i+1; hides the instant its
	# milestone is acquired. Burst on visible→hidden transition.
	# Skip during phase 1 of the intro animation so the spacers don't
	# snap-show ahead of the cascade.
	if _intro_phase != IntroPhase.SHRINK:
		for i in _spacers.size():
			var should_be_visible: bool = current <= _tier_start_level + i
			if _spacer_visible[i] and not should_be_visible:
				_spawn_seam_burst(_spacers[i])
			_spacers[i].visible = should_be_visible
			_spacer_visible[i] = should_be_visible

		_apply_segment_styles()
	_position_progress_label()


## Plays once when the player crosses the very first milestone of a tier.
## Phase 1: every segment's stretch_ratio tweens to its proportional weight
## in parallel — segment 0 visibly shrinks to the left, segments 1..N-1
## grow their layout slots invisibly (alpha 0). Borders on seg 0 stay
## "standalone" (fully bordered + rounded) for the duration.
## Phase 2: segments 1..N-1 cascade-fade in (alpha 0→1), spacers fade in
## alongside, borders re-resolve to the merged appearance.
func _play_intro_to_live_animation() -> void:
	if _intro_anim_tween:
		_intro_anim_tween.kill()
	var phase1_dur: float = 1.15
	var phase2_dur: float = 2.0
	var stagger: float = 0.1

	_intro_phase = IntroPhase.SHRINK
	_intro_anim_tween = create_tween().set_parallel()
	for i in _segment_panels.size():
		_intro_anim_tween.tween_property(_segment_panels[i], "size_flags_stretch_ratio", _segment_weights[i], phase1_dur) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Repositions the label while seg 0 is shrinking so the inside/above
	# decision tracks the active segment's actual width.
	_intro_anim_tween.chain().tween_callback(func():
		_intro_phase = IntroPhase.CASCADE
		_apply_segment_styles()
		# Stored on the instance so _rebuild_bar can kill it before the
		# segment panels it targets get freed.
		_intro_cascade_tween = create_tween().set_parallel()
		for i in range(1, _segment_panels.size()):
			var delay: float = stagger * (i - 1)
			_intro_cascade_tween.tween_property(_segment_panels[i], "modulate:a", 1.0, phase2_dur) \
				.set_delay(delay).set_ease(Tween.EASE_OUT)
		for i in _spacers.size():
			var should_be_visible: bool = LevelManager.current_level <= _tier_start_level + i
			if should_be_visible:
				_spacers[i].visible = true
				_spacers[i].modulate.a = 0.0
				_spacer_visible[i] = true
				var delay: float = stagger * (i + 1)
				_intro_cascade_tween.tween_property(_spacers[i], "modulate:a", 1.0, phase2_dur) \
					.set_delay(delay).set_ease(Tween.EASE_OUT)
		# Fire the swoop 0.5s after the final segment BEGINS spawning in.
		var last_seg_start: float = stagger * (_segment_panels.size() - 2)
		var swoop_delay: float = last_seg_start + 0.5
		_intro_cascade_tween.tween_callback(func():
			_intro_phase = IntroPhase.DONE
			_position_progress_label()
			# Milestone label fades back in now that the bar has settled.
			milestone_label.create_tween().tween_property(milestone_label, "modulate:a", 1.0, 0.4)
			if not _intro_held_particles.is_empty():
				# Stop the drift loops before handing the particles to the
				# swoop pipeline (otherwise both tweens fight over position).
				for dt in _intro_drift_tweens:
					if dt:
						dt.kill()
				_intro_drift_tweens.clear()
				var particles: Array[ColorRect] = _intro_held_particles
				var targets: Array[Vector2] = _intro_held_targets
				_intro_held_particles = []
				_intro_held_targets = []
				if targets.is_empty():
					_fade_and_claim(particles)
				else:
					_swoop_particles_to_targets(particles, targets)
		).set_delay(swoop_delay)
	)


## ProgressLabel rides above the bar (left-aligned with the bar's left edge)
## while the active segment is too narrow to host it. Once the active segment
## is wider than the label, the label moves INSIDE the segment, centered —
## i.e., behaves like a normal fill-bar text. MilestoneLabel sits top-right,
## right-aligned with the bar's right edge.
func _position_progress_label() -> void:
	_position_milestone_label()
	var current: int = LevelManager.current_level
	var active_idx: int = current - _tier_start_level
	# Hidden during the squish + cascade (the wait period uses an alpha
	# fade instead, handled in _start_intro_transition).
	var hide_progress: bool = _intro_phase == IntroPhase.SHRINK or _intro_phase == IntroPhase.CASCADE
	if hide_progress or active_idx < 0 or active_idx >= _segment_panels.size():
		progress_label.visible = false
		return
	var seg: Panel = _segment_panels[active_idx]
	if seg.size.x <= 0.0 or segments_hbox.size.x <= 0.0:
		# Layout not ready yet — hide so the label doesn't sit at the
		# top-left while the first layout pass runs. The resized signal
		# will re-fire this once the bar has a real size.
		progress_label.visible = false
		return
	progress_label.visible = true
	# Measure the text via the font directly — Label.get_minimum_size() is
	# sometimes stale right after a text change, which caused the trailing
	# character to clip.
	var label_size: Vector2 = _measure_label_text(progress_base_label)
	var label_w: float = label_size.x
	var label_h: float = label_size.y

	# Size the container + both labels + clip to the text's minimum size.
	progress_label.size = label_size
	progress_base_label.position = Vector2.ZERO
	progress_base_label.size = label_size
	progress_fill_clip.position = Vector2.ZERO
	progress_fill_clip.size = label_size
	progress_fill_label.position = Vector2.ZERO
	progress_fill_label.size = label_size

	var label_padding: float = 12.0
	var fill_extent: float = 0.0  # how much of label_w is covered by bar fill
	# Once the 3rd milestone is acquired, the merged group is treated as a
	# normal fill bar — text centered on it, fill_label clipped by the
	# global bar fill position.
	var fill_bar_mode: bool = active_idx >= FILL_BAR_TEXT_MIN_ACTIVE_IDX
	var fits_inside: bool = (not fill_bar_mode) and seg.size.x >= label_w + label_padding

	if fill_bar_mode:
		progress_base_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		progress_fill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Merged group spans seg 0 through the active segment (inclusive).
		var merged_left: float = _segment_panels[0].global_position.x
		var merged_right: float = seg.global_position.x + seg.size.x
		var merged_center_x: float = (merged_left + merged_right) * 0.5
		var seg_center_y: float = seg.global_position.y + seg.size.y * 0.5
		progress_label.position = Vector2(merged_center_x - label_w * 0.5, seg_center_y - label_h * 0.5)
		# Visual fill end = the rightmost x reached by any segment's fill_rect
		# (not just the active seg's — when balance has been spent below the
		# previous threshold, the active seg shows 0 and the visible fill
		# actually ends inside an earlier segment).
		var fill_right_global: float = merged_left
		for fr in _segment_fills:
			if fr.anchor_right > 0.0:
				var end_x: float = fr.get_global_rect().end.x
				if end_x > fill_right_global:
					fill_right_global = end_x
		fill_extent = clampf(fill_right_global - progress_label.position.x, 0.0, label_w)
	elif fits_inside:
		# Centered inside the active segment.
		progress_base_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		progress_fill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var seg_center_x: float = seg.global_position.x + seg.size.x * 0.5
		var seg_center_y: float = seg.global_position.y + seg.size.y * 0.5
		progress_label.position = Vector2(seg_center_x - label_w * 0.5, seg_center_y - label_h * 0.5)
		var fill_rect: ColorRect = _segment_fills[active_idx]
		var fill_right_global: float = fill_rect.get_global_rect().end.x
		fill_extent = clampf(fill_right_global - progress_label.position.x, 0.0, label_w)
	else:
		# Above the bar, left-aligned with the segments_hbox left edge.
		progress_base_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		progress_fill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		progress_label.position = Vector2(
			segments_hbox.global_position.x,
			seg.global_position.y - label_h - 2.0
		)
		fill_extent = 0.0

	progress_fill_clip.size = Vector2(fill_extent, label_h)


func _measure_label_text(label: Label) -> Vector2:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	if font == null or font_size <= 0:
		return label.get_minimum_size()
	# Text width + a few pixels of padding to dodge any sub-pixel clip.
	var sz: Vector2 = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	return Vector2(ceil(sz.x) + 8.0, ceil(sz.y))


func _position_milestone_label() -> void:
	milestone_label.size = milestone_label.get_minimum_size()
	if segments_hbox.size.x <= 0.0:
		return
	var right_padding: float = 4.0
	var bar_right: float = segments_hbox.global_position.x + segments_hbox.size.x
	milestone_label.position = Vector2(
		bar_right - milestone_label.size.x - right_padding,
		segments_hbox.global_position.y - milestone_label.size.y - 2.0
	)


func _spawn_seam_burst(sep: Control) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var center: Vector2 = sep.global_position + sep.size * 0.5
	var color: Color = t.normal_text_color
	var count: int = 14
	for i in count:
		var p := ColorRect.new()
		p.size = Vector2(4, 4)
		p.color = color
		p.position = center - Vector2(2, 2)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_particle_overlay.add_child(p)

		var angle: float = randf() * TAU
		var distance: float = randf_range(30.0, 75.0)
		var target: Vector2 = center + Vector2(cos(angle), sin(angle)) * distance - Vector2(2, 2)
		var dur: float = randf_range(0.35, 0.6)

		var tween := p.create_tween().set_parallel()
		tween.tween_property(p, "position", target, dur) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(p, "modulate:a", 0.0, dur) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.chain().tween_callback(p.queue_free)


func _milestone_title(level_data: LevelData) -> String:
	if level_data.rewards.is_empty():
		return "Keep going!"
	var r: RewardData = level_data.rewards[0]
	match r.type:
		RewardData.RewardType.UNLOCK_UPGRADE:
			# upgrade_name returns lowercase ("add row"); sentence-case it.
			var s: String = FormatUtils.upgrade_name(r.upgrade_type)
			return s[0].to_upper() + s.substr(1) if not s.is_empty() else s
		RewardData.RewardType.UNLOCK_AUTODROPPER:
			return "Autodropper"
		RewardData.RewardType.UNLOCK_ADVANCED_AUTODROPPER:
			return "Advanced autodropper"
		RewardData.RewardType.UNLOCK_ADVANCED_BUCKET:
			# Advanced buckets show the next-tier name. But if landing in
			# one would trigger prestige (the next tier hasn't been
			# permanently unlocked yet), call them "prestige buckets".
			var next_tier: TierData = TierRegistry.get_next_tier(r.target_board)
			if next_tier == null:
				return "Buckets"
			if not PrestigeManager.is_board_unlocked_permanently(next_tier.board_type):
				return "Prestige buckets"
			return "%s buckets" % FormatUtils.board_name(next_tier.board_type)
		RewardData.RewardType.DROP_COINS:
			return "%s coin drop" % FormatUtils.currency_name(r.coin_type)
	return "Keep going!"


# ── Reward target resolution ───────────────────────────────────────
# Returns an array of targets. Empty = scatter only (no swoop).
# One target = all particles converge. Two targets = particles split evenly.

func _get_reward_targets(rewards: Array[RewardData]) -> Array[Vector2]:
	for reward in rewards:
		match reward.type:
			RewardData.RewardType.DROP_COINS:
				return [_get_coin_drop_target(reward.target_board)]
			RewardData.RewardType.UNLOCK_UPGRADE:
				if ChallengeManager.is_active_challenge and not ChallengeManager.is_upgrade_allowed(reward.upgrade_type):
					return [_get_coin_drop_target(reward.board_type)]
				return [_get_upgrade_section_target(reward.upgrade_type)]
			RewardData.RewardType.UNLOCK_AUTODROPPER:
				return [_get_hud_upgrade_target(Enums.UpgradeType.AUTODROPPER)]
			RewardData.RewardType.UNLOCK_ADVANCED_AUTODROPPER:
				return [_get_hud_upgrade_target(Enums.UpgradeType.ADVANCED_AUTODROPPER)]
			RewardData.RewardType.UNLOCK_ADVANCED_BUCKET:
				return _get_advanced_bucket_targets(reward.target_board)
	return []


func _get_upgrade_section_target(upgrade_type: int = -1) -> Vector2:
	var board: PlinkoBoard = _board_manager.get_active_board()
	var section: UpgradeSection = board.upgrade_section
	if upgrade_type >= 0:
		var row: Control = section.get_upgrade_row(upgrade_type)
		if row:
			return row.global_position + row.size * 0.5
	var container: VBoxContainer = section.upgrades_container
	return container.global_position + Vector2(container.size.x * 0.5, container.size.y)


func _get_hud_upgrade_target(upgrade_type: Enums.UpgradeType) -> Vector2:
	if _coin_values:
		var row: Control = _coin_values.get_upgrade_row(upgrade_type)
		if row:
			return row.global_position + row.size * 0.5
		var cv: Control = _coin_values as Control
		return cv.global_position + Vector2(cv.size.x * 0.5, cv.size.y)
	return _get_upgrade_section_target()


func _get_coin_drop_target(target_board_type: int) -> Vector2:
	for board in _board_manager.get_boards():
		if board.board_type == target_board_type:
			var spawn_pos: Vector3 = board.global_position + Vector3(0, board.vertical_spacing + 0.2, 0)
			return _camera.unproject_position(spawn_pos)
	return Vector2(get_viewport().get_visible_rect().size.x * 0.5, 100)


func _get_advanced_bucket_targets(target_board_type: int) -> Array[Vector2]:
	for board in _board_manager.get_boards():
		if board.board_type == target_board_type:
			var num_buckets: int = board.num_rows + 1
			var half: int = num_buckets / 2
			if half < board.distance_for_advanced_buckets:
				return []
			var buckets = board.buckets_container.get_children()
			if buckets.size() < 2:
				return []
			var left_pos: Vector2 = _camera.unproject_position(buckets[0].global_position)
			var right_pos: Vector2 = _camera.unproject_position(buckets[buckets.size() - 1].global_position)
			return [left_pos, right_pos]
	return []


# ── Two-phase particle animation ──────────────────────────────────

## Final-milestone disintegration: many particles spawn distributed across
## the bar's full surface (not just the top edge), the bar segments fade
## to invisible during the burst, then particles swoop to the targets
## (advanced-bucket positions) and call claim_rewards on arrival.
func _spawn_bar_explosion(targets: Array[Vector2]) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var color: Color = t.normal_text_color
	var bar_global: Vector2 = segments_hbox.global_position
	var bar_size: Vector2 = segments_hbox.size
	var burst_duration: float = t.level_up_particle_burst_duration
	var particle_count: int = t.level_up_particle_count * 3  # denser explosion
	var particles: Array[ColorRect] = []

	for i in particle_count:
		var p := ColorRect.new()
		p.size = Vector2(6, 6)
		p.color = color
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var start_x: float = bar_global.x + randf() * bar_size.x
		var start_y: float = bar_global.y + randf() * bar_size.y
		p.position = Vector2(start_x, start_y)
		_particle_overlay.add_child(p)
		particles.append(p)

		var angle: float = randf() * TAU
		var distance: float = randf_range(60.0, 160.0)
		var scatter: Vector2 = Vector2(cos(angle), sin(angle)) * distance
		var indiv_dur: float = burst_duration * randf_range(0.7, 1.0)
		var tween := p.create_tween()
		tween.tween_property(p, "position", p.position + scatter, indiv_dur) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Fade the bar (segments + labels) out as the particles burst.
	for seg in _segment_panels:
		seg.create_tween().tween_property(seg, "modulate:a", 0.0, burst_duration)
	milestone_label.create_tween().tween_property(milestone_label, "modulate:a", 0.0, burst_duration)
	progress_label.create_tween().tween_property(progress_label, "modulate:a", 0.0, burst_duration)

	var swoop_timer := get_tree().create_timer(burst_duration)
	swoop_timer.timeout.connect(func():
		if targets.is_empty():
			_fade_and_claim(particles)
		else:
			_swoop_particles_to_targets(particles, targets)
	)


func _spawn_particles_with_swoop(targets: Array[Vector2]) -> void:
	var t: VisualTheme = ThemeProvider.theme
	# Milestone particles match the bar color (not the currency tint).
	var color: Color = t.normal_text_color
	var bar_global: Vector2 = segments_hbox.global_position
	var bar_width: float = segments_hbox.size.x
	var particles: Array[ColorRect] = []

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

	var swoop_timer := get_tree().create_timer(t.level_up_particle_burst_duration)
	swoop_timer.timeout.connect(func():
		if targets.is_empty():
			_fade_and_claim(particles)
		else:
			_swoop_particles_to_targets(particles, targets)
	)


func _swoop_particles_to_targets(particles: Array[ColorRect], targets: Array[Vector2]) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var state := [0]
	var total := particles.size()

	for i in particles.size():
		var particle := particles[i]
		if not is_instance_valid(particle):
			state[0] += 1
			if state[0] >= total:
				LevelManager.claim_rewards()
			continue

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


func _fade_and_claim(particles: Array[ColorRect]) -> void:
	for particle in particles:
		if is_instance_valid(particle):
			var tween := particle.create_tween()
			tween.tween_property(particle, "modulate:a", 0.0, 0.4) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tween.tween_callback(particle.queue_free)
	var claim_timer := get_tree().create_timer(0.2)
	claim_timer.timeout.connect(LevelManager.claim_rewards)


# ── Shockwave ─────────────────────────────────────────────────────

func _spawn_shockwave_rings() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var bar_center: Vector2 = segments_hbox.global_position + segments_hbox.size * 0.5
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var uv_center: Vector2 = bar_center / viewport_size
	VfxUtils.spawn_shockwave(self, uv_center, { "ring_count": 1, "duration": t.prestige_ring_duration / 3.0 })
