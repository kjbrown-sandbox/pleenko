class_name PlinkoBoard
extends Node3D

@export var num_rows: int = 2
var space_between_pegs: float
var vertical_spacing: float
@export var drop_delay: float = 2.0
@export var drop_delay_reduction_factor: float = 0.85
@export var distance_for_advanced_buckets: int = 3 # Before you modify this, know I've tested it and 4 feel awful

## Each coin in the queue (FULL or FILLING) boosts drop rate by this multiplier
## of the base rate. effective_delay = drop_delay / (1 + bonus * queue.count).
## Additive in rate (not delay) keeps the curve self-bounded — delay shrinks
## but never reaches zero. With 1.0, one queued coin doubles the rate, two
## triples it, ten gives 11x the base rate.
const QUEUE_RATE_BONUS_PER_COIN := 0.25

## Pixel offset from the projected spawn point to the top-left of the bonus
## label box. +X pushes the label right of the queue (clear of the drop
## column); -Y centers a single line vertically against the spawn dot.
const QUEUE_BONUS_LABEL_OFFSET := Vector2(40.0, -16.0)

## Delay between each bonus coin in a multi-drop, so they don't all land simultaneously.
const MULTI_DROP_STAGGER := 0.15

const BucketScene: PackedScene = preload("res://entities/bucket/bucket.tscn")
const CoinScene := preload("res://entities/coin/coin.tscn")

@onready var pegs_container: Node3D = $Pegs
@onready var buckets_container: Node3D = $Buckets
@onready var upgrade_section = $UpgradeSection
@onready var drop_section: DropSection = $DropSection
@onready var coin_queue: CoinQueue = $CoinQueue
@onready var _drop_main_column: VBoxContainer = $DropSection/DropButtons/DropMainColumn
@onready var _drop_main = $DropSection/DropButtons/DropMainColumn/DropMain
@onready var _drop_main_label: Label = $DropSection/DropButtons/DropMainColumn/DropMainLabel
@onready var _drop_advanced_column: VBoxContainer = $DropSection/DropButtons/DropAdvancedColumn
@onready var _drop_advanced = $DropSection/DropButtons/DropAdvancedColumn/DropAdvanced
@onready var _drop_advanced_label: Label = $DropSection/DropButtons/DropAdvancedColumn/DropAdvancedLabel
@onready var _drop_tooltip: Tooltip = $DropSection/DropTooltip

var board_type: Enums.BoardType
var advanced_bucket_type: Enums.CurrencyType
var is_waiting: bool = false
var bucket_value_multiplier: int = 1
var advanced_coin_multiplier: float = 2.0
var should_show_advanced_buckets: bool = false
var _has_advanced_drop: bool = false
var _normal_autodroppers_visible: bool = false
var _advanced_autodroppers_visible: bool = false
var _drop_buttons: Dictionary = {}  # StringName -> node (for autodropper lookup)
var _no_room_label: Label3D
var _bucket_markings: Dictionary = {}  # int (bucket index) -> StringName ("hit" | "target" | "forbidden")
# Tracks specific buckets currently singing in drum-layer mode so they survive
# rebuilds. Keyed by bucket world-x scaled to integer millimeters (float → int
# rounded to 1mm). Scale factor must match between insert/lookup/erase.
const BUCKET_POSITION_KEY_SCALE := 1000.0
var _singing_positions: Dictionary = {}  # _bucket_position_key(x) -> true, survives rebuilds
var _upgrade_animating: bool = false
var _upgrade_ripple_tween: Tween
var multi_drop_count: int = -1
@export var hack_space: bool = false
var _coin_z_counter: int = 0  # Increments per coin so later coins render in front
# True while the mouse is hovering either drop button — used by the tooltip
# refresh logic so the persistent "Needs X" message is suppressed in favor of
# the regular cost tooltip during hover.
var _drop_button_hovered: bool = false

## Optional gate: () -> bool. Returns true if drops should be blocked.
## Set externally (e.g. by BoardManager during challenges).
var drop_blocked: Callable

## Optional gate: (upgrade_type: Enums.UpgradeType) -> bool. Returns true if allowed.
## Set externally (e.g. by BoardManager during challenges).
var upgrade_allowed: Callable

# Gameplay target bucket state
const GAMEPLAY_TARGET_DURATION: float = 8.0
const GAMEPLAY_TARGET_FADE_START: float = 1.0  # begin fading with 1s left
var _gameplay_target_enabled: bool = false
var _gameplay_target_index: int = -1
var _gameplay_target_timer: float = 0.0
var _gameplay_target_fading: bool = false

# MultiMesh peg state
var _peg_multimesh_instance: MultiMeshInstance3D
var _peg_positions: PackedVector3Array
var _peg_base_color: Color
var _peg_basis: Basis
var _active_flashes: Dictionary = {}  # peg_index -> { start_color: Color, elapsed: float, duration: float }
var _active_peg_pulses: Dictionary = {}  # peg_index -> { elapsed: float, duration: float }

# MultiMesh coin state
var _coin_multimesh_instance: MultiMeshInstance3D
var _coin_free_indices: Array[int] = []
var _active_coin_indices: Dictionary = {}  # Coin -> int (multimesh index)
var _coin_mesh_basis: Basis = Basis.IDENTITY

signal board_rebuilt
signal autodropper_adjust_requested(button_id: StringName, delta: int)
signal coin_landed(board_type: Enums.BoardType, bucket_index: int, currency_type: Enums.CurrencyType, amount: int, multiplier: float)
signal autodrop_failed(board_type: Enums.BoardType)
signal coin_dropped
signal prestige_coin_landed(coin: Coin, bucket: Bucket)

# Timestamps of recent drop bursts, used to rate-limit emissions to
# drop_burst_max_per_second. Only the last ~1 second of entries are kept.
var _drop_burst_times: Array[float] = []

# MultiMesh drop burst state
var _drop_burst_mm_instance: MultiMeshInstance3D
var _drop_burst_free_indices: Array[int] = []
var _active_drop_bursts: Array[Dictionary] = []

var _drop_timer_remaining: float = 0.0
# Effective delay (after queue bonus) at the time the active timer cycle started
# or was last rescaled. Used to proportionally rescale _drop_timer_remaining
# when the queue's full count changes mid-cycle.
var _last_effective_delay: float = 0.0

# Hold-to-drop rate limiter: enqueues at 10 coins/sec while space (or B) is held.
# The drop timer drains the queue at its own pace; this only controls how fast
# coins enter the queue.
const HOLD_DROP_INTERVAL: float = 0.1
# Primed at HOLD_DROP_INTERVAL so the first frame of a fresh hold fires
# immediately rather than waiting an interval.
var _hold_drop_accumulator: float = HOLD_DROP_INTERVAL

func _ready() -> void:
	space_between_pegs = ThemeProvider.theme.space_between_pegs
	vertical_spacing = space_between_pegs * sqrt(3) / 2 # sqrt because of the 30/60/90 triangle babyyyy
	multi_drop_count = PrestigeManager.get_multi_drop(board_type) + ChallengeProgressManager.get_bonus_multi_drop(board_type)
	AudioManager.chord_changed.connect(_on_chord_changed)
	AudioManager.drum_tier_fired.connect(_on_drum_tier_fired)
	AudioManager.drum_tier_expired.connect(_on_drum_tier_expired)
	ThemeProvider.theme_changed.connect(_on_theme_changed)
	call_deferred("_init_gameplay_target")


func _exit_tree() -> void:
	if AudioManager.chord_changed.is_connected(_on_chord_changed):
		AudioManager.chord_changed.disconnect(_on_chord_changed)
	if AudioManager.drum_tier_fired.is_connected(_on_drum_tier_fired):
		AudioManager.drum_tier_fired.disconnect(_on_drum_tier_fired)
	if AudioManager.drum_tier_expired.is_connected(_on_drum_tier_expired):
		AudioManager.drum_tier_expired.disconnect(_on_drum_tier_expired)
	if ThemeProvider.theme_changed.is_connected(_on_theme_changed):
		ThemeProvider.theme_changed.disconnect(_on_theme_changed)


## Chord advance — buckets now manage their own singing timers, so this is
## a no-op for the standard (non-drum) path.
func _on_chord_changed(_chord_index: int) -> void:
	pass


## Drum beat fired: pulse every bucket at this tier's distance-from-center
## so the player sees the rhythm on the buckets they've activated.
func _on_drum_tier_fired(tier: int) -> void:
	var num_buckets: int = buckets_container.get_child_count()
	var center: int = num_buckets / 2
	for i in num_buckets:
		if absi(i - center) == tier:
			var bucket: Bucket = get_bucket(i)
			if bucket:
				bucket.pulse()


## Theme swap: drop any drum-layer tracking from the old theme. Next theme
## starts with a clean set; stale entries from the previous theme's drums
## don't bleed into rebuilds under the new theme.
func _on_theme_changed() -> void:
	_singing_positions.clear()


## Bucket's singing timer expired — remove from rebuild tracking.
func _on_bucket_stopped_singing(bucket: Bucket) -> void:
	_singing_positions.erase(_bucket_position_key(bucket.position.x + buckets_container.position.x))


## Drum tier expired: fade every bucket at this tier's distance back to faded.
## Only buckets currently tracked as singing get stopped — avoids touching
## buckets that were never activated this lifetime.
func _on_drum_tier_expired(tier: int) -> void:
	var num_buckets: int = buckets_container.get_child_count()
	var center: int = num_buckets / 2
	for i in num_buckets:
		if absi(i - center) == tier:
			var bucket: Bucket = get_bucket(i)
			if bucket:
				bucket.mark_stop_singing()
				_singing_positions.erase(_bucket_position_key(bucket.position.x + buckets_container.position.x))


func setup(type: Enums.BoardType) -> void:
	board_type = type
	advanced_coin_multiplier = 2.0 + ChallengeProgressManager.get_advanced_coin_multiplier_bonus(board_type)
	multi_drop_count = PrestigeManager.get_multi_drop(board_type) + ChallengeProgressManager.get_bonus_multi_drop(board_type)

	drop_delay = TierRegistry.get_base_drop_delay(board_type)
	var adv: int = TierRegistry.advanced_bucket_currency(board_type)
	if adv >= 0:
		advanced_bucket_type = adv

	# Apply permanent upgrade bonuses from challenge rewards
	bucket_value_multiplier = 1 + ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.BUCKET_VALUE)
	var perm_drop_rate: int = ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.DROP_RATE)
	for i in perm_drop_rate:
		drop_delay *= drop_delay_reduction_factor
	var perm_queue: int = ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.QUEUE)

	_setup_drop_bars()
	_update_drop_fill()
	upgrade_section.setup(self, type)
	build_board()
	coin_queue.setup(Vector3(0, vertical_spacing + 0.2, 0))
	coin_queue.set_capacity(perm_queue)
	coin_queue.count_changed.connect(_on_queue_count_changed)
	drop_section.set_queue_bonus(coin_queue.count, QUEUE_RATE_BONUS_PER_COIN)
	LevelManager.rewards_claimed.connect(_on_rewards_claimed)
	LevelManager.reconcile_reward.connect(_on_reconcile_reward)
	CurrencyManager.currency_changed.connect(_on_currency_changed)


func _setup_drop_bars() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var currency_type: Enums.CurrencyType = TierRegistry.primary_currency(board_type)
	var coin_color: Color = t.get_coin_color(currency_type)
	var coin_color_dark: Color = t.get_coin_color_faded(currency_type)

	# Add spacing in the column to accommodate subtext labels above buttons
	_drop_main_column.add_theme_constant_override("separation", 2)
	_drop_advanced_column.add_theme_constant_override("separation", 2)

	# Main drop bar — non-gold boards drop raw currency, so label accordingly
	var raw: int = TierRegistry.raw_currency(board_type)
	var label_currency: Enums.CurrencyType = (raw as Enums.CurrencyType) if raw >= 0 else currency_type
	_drop_main.setup(coin_color, coin_color_dark)
	_drop_main.update_text("Drop %s" % FormatUtils.currency_name(label_currency))
	_drop_main.main_pressed.connect(func(): request_drop())
	_drop_main.main_mouse_entered.connect(_on_drop_main_hover)
	_drop_main.main_mouse_exited.connect(_on_drop_hover_exit)
	_drop_main.side_button_hover.connect(_on_drop_side_hover)

	# Spacebar shortcut
	var shortcut := Shortcut.new()
	var key_event := InputEventAction.new()
	key_event.action = "drop_coin"
	shortcut.events = [key_event]
	_drop_main.main_button.shortcut = shortcut
	_drop_main.main_button.shortcut_in_tooltip = false

	var normal_id := StringName("%s_NORMAL" % Enums.BoardType.keys()[board_type])
	_drop_buttons[normal_id] = _drop_main

	# Advanced drop bar — hidden until earned
	_drop_advanced_column.visible = false


func update_queue_fill(progress: float, num_advanced: int, num_normal: int) -> void:
	# Hide overflow indicator if queue has room now
	if not coin_queue.is_full():
		_hide_no_room()
	# Ensure the right number of FILLING coins exist for each type
	_sync_filling_coins(num_advanced, true)
	_sync_filling_coins(num_normal, false)
	# Update fill progress on all FILLING coins
	coin_queue.update_filling_progress(progress)


func _sync_filling_coins(wanted: int, is_advanced: bool) -> void:
	var current: int = coin_queue.get_filling_count(is_advanced)
	if current < wanted:
		# Add more filling coins
		var coin_type: Enums.CurrencyType
		var mult: float = 1.0
		if is_advanced:
			coin_type = advanced_bucket_type
			mult = advanced_coin_multiplier
		else:
			coin_type = TierRegistry.primary_currency(board_type)
		for i in wanted - current:
			if coin_queue.is_full():
				if coin_queue.has_queue():
					_show_no_room()
				break
			coin_queue.add_filling_coin(coin_type, is_advanced, mult)
	elif current > wanted:
		# Remove only the excess filling coins
		coin_queue.remove_filling_coins_of_type(is_advanced, current - wanted)


func _show_no_room() -> void:
	if _no_room_label and is_instance_valid(_no_room_label):
		return  # Already showing
	var t: VisualTheme = ThemeProvider.theme
	_no_room_label = Label3D.new()
	_no_room_label.text = "!"
	_no_room_label.font_size = 64
	if t.label_font:
		_no_room_label.font = t.label_font
	_no_room_label.modulate = t.red_main
	_no_room_label.outline_size = 0
	_no_room_label.no_depth_test = true
	_no_room_label.position = coin_queue.get_overflow_position()
	add_child(_no_room_label)

	# Bind tween to the label so it's auto-killed when the label is freed
	var pulse_tween := _no_room_label.create_tween().set_loops(0)
	pulse_tween.tween_property(_no_room_label, "scale", Vector3(1.15, 1.15, 1.15), 0.5) \
		.set_trans(Tween.TRANS_SINE)
	pulse_tween.tween_property(_no_room_label, "scale", Vector3.ONE, 0.5) \
		.set_trans(Tween.TRANS_SINE)


func _hide_no_room() -> void:
	if _no_room_label and is_instance_valid(_no_room_label):
		_no_room_label.queue_free()
		_no_room_label = null


func _format_cost_text(costs: Array) -> String:
	var parts: PackedStringArray = []
	for cost in costs:
		parts.append("%s %s" % [FormatUtils.format_number(cost[1]), FormatUtils.currency_name(cost[0], false)])
	return ", ".join(parts)


func _on_drop_main_hover() -> void:
	_drop_main.pulse_main(1.005)
	_drop_button_hovered = true
	# Hover always shows the regular cost tooltip, overriding any persistent
	# "Needs X" message until the mouse exits.
	_drop_tooltip.update_and_show("Cost: %s\nHotkey: SPACE" % _format_cost_text(_get_drop_costs()))


func _format_missing_cost_text(costs: Array) -> String:
	var parts: PackedStringArray = []
	for cost in costs:
		var balance: int = CurrencyManager.get_balance(cost[0])
		var missing: int = cost[1] - balance
		if missing > 0:
			parts.append("%s %s" % [FormatUtils.format_number(missing), FormatUtils.currency_name(cost[0], false)])
	return ", ".join(parts)


## Persistent "Needs X" tooltip on the normal drop button — visible whenever
## the player can't afford a drop and isn't just waiting on cooldown. Hidden
## while the mouse is hovering either drop button (the hover handler shows
## the regular cost tooltip instead).
func _refresh_needs_tooltip() -> void:
	if _drop_button_hovered:
		return
	var costs := _get_drop_costs()
	if not is_waiting and not _can_afford(costs):
		_drop_tooltip.update_and_show_colored("Needs %s" % _format_missing_cost_text(costs), ThemeProvider.theme.red_main)
	else:
		_drop_tooltip.hide_tooltip()


func _on_drop_advanced_hover() -> void:
	_drop_advanced.pulse_main(1.005)
	_drop_button_hovered = true
	_drop_tooltip.update_and_show("Cost: %s\nHotkey: B" % _format_cost_text(_get_advanced_drop_costs()))


func _on_drop_hover_exit() -> void:
	_drop_button_hovered = false
	_drop_tooltip.hide_tooltip()
	# Re-evaluate the persistent needs message after the hover ends.
	_refresh_needs_tooltip()


func _on_drop_side_hover(text: String) -> void:
	_drop_tooltip.show_or_hide(text)


func _process(delta: float) -> void:
	# TEMP: performance test — spam coins while holding spacebar
	if hack_space and Input.is_action_pressed("drop_coin") and drop_section.visible:
		is_waiting = false
		_drop_timer_remaining = 0.0
		request_drop()
	if is_waiting:
		_drop_timer_remaining = maxf(0.0, _drop_timer_remaining - delta)
		_update_drop_fill()
		if _drop_timer_remaining == 0.0:
			_on_drop_timer_done()

	# Hold-to-drop runs independently of the drop timer so the queue fills
	# at HOLD_DROP_INTERVAL while the drop timer drains it at its own rate.
	var hold_advanced: bool = _is_hold_to_drop_advanced_active()
	var hold_normal: bool = not hold_advanced and _is_hold_to_drop_active()
	if _tick_hold_drop_accumulator(delta, hold_advanced or hold_normal):
		if hold_advanced:
			request_drop(_get_advanced_drop_costs(), advanced_bucket_type)
		else:
			request_drop()

	_update_queue_bonus_label_position()

	if not _active_flashes.is_empty():
		_update_peg_flashes(delta)
	if not _active_peg_pulses.is_empty():
		_update_peg_pulses(delta)

	if not _active_coin_indices.is_empty():
		_sync_coin_multimesh(delta)

	if not _active_drop_bursts.is_empty():
		_sync_drop_burst(delta)

	if _gameplay_target_enabled and _gameplay_target_index >= 0:
		_gameplay_target_timer -= delta
		if _gameplay_target_timer <= GAMEPLAY_TARGET_FADE_START and not _gameplay_target_fading:
			_gameplay_target_fading = true
			var bucket := get_bucket(_gameplay_target_index)
			if bucket:
				bucket.start_gameplay_target_fade(GAMEPLAY_TARGET_FADE_START)
		if _gameplay_target_timer <= 0.0:
			_pick_new_gameplay_target()


func _update_peg_flashes(delta: float) -> void:
	var mm := _peg_multimesh_instance.multimesh
	var finished: PackedInt32Array = []

	for idx: int in _active_flashes:
		var flash: Dictionary = _active_flashes[idx]
		flash.elapsed += delta
		var t_ratio: float = clampf(flash.elapsed / flash.duration, 0.0, 1.0)
		var eased: float = t_ratio * t_ratio  # EASE_IN + TRANS_QUAD
		var color: Color = flash.start_color.lerp(_peg_base_color, eased)
		mm.set_instance_color(idx, color)

		if t_ratio >= 1.0:
			finished.append(idx)

	for idx in finished:
		_active_flashes.erase(idx)


func _update_peg_pulses(delta: float) -> void:
	var mm := _peg_multimesh_instance.multimesh
	var t: VisualTheme = ThemeProvider.theme
	var pulse_scale: float = 1.0 + (t.bucket_pulse_scale - 1.0) * 3.0
	var finished: PackedInt32Array = []

	for idx: int in _active_peg_pulses:
		var pulse: Dictionary = _active_peg_pulses[idx]
		pulse.elapsed += delta
		var t_ratio: float = clampf(pulse.elapsed / pulse.duration, 0.0, 1.0)
		# Scale up then back down: peak at t_ratio=0.4
		var scale: float
		if t_ratio < 0.4:
			scale = lerpf(1.0, pulse_scale, t_ratio / 0.4)
		else:
			scale = lerpf(pulse_scale, 1.0, (t_ratio - 0.4) / 0.6)
		var scaled_basis: Basis = _peg_basis.scaled(Vector3.ONE * scale)
		mm.set_instance_transform(idx, Transform3D(scaled_basis, _peg_positions[idx]))

		if t_ratio >= 1.0:
			finished.append(idx)

	for idx in finished:
		mm.set_instance_transform(idx, Transform3D(_peg_basis, _peg_positions[idx]))
		_active_peg_pulses.erase(idx)


## Pacing for hold-to-drop. Returns true when a drop should fire this frame.
## Resets when not pressed so the next press fires immediately.
func _tick_hold_drop_accumulator(delta: float, is_pressed: bool) -> bool:
	if not is_pressed:
		_hold_drop_accumulator = HOLD_DROP_INTERVAL
		return false
	_hold_drop_accumulator += delta
	if _hold_drop_accumulator >= HOLD_DROP_INTERVAL:
		_hold_drop_accumulator = 0.0
		return true
	return false


func _is_hold_to_drop_active() -> bool:
	return Input.is_action_pressed("drop_coin") \
		and ChallengeProgressManager.is_unlocked(ChallengeRewardData.UnlockType.HOLD_TO_DROP) \
		and drop_section.visible


func _is_hold_to_drop_advanced_active() -> bool:
	return Input.is_action_pressed("drop_unrefined") \
		and ChallengeProgressManager.is_unlocked(ChallengeRewardData.UnlockType.HOLD_TO_DROP) \
		and drop_section.visible \
		and _drop_advanced_column.visible


# --- Coin MultiMesh management ---

func _allocate_coin_multimesh(coin: Coin) -> void:
	if _coin_free_indices.is_empty():
		_grow_coin_multimesh()
	var idx: int = _coin_free_indices.pop_back()
	_active_coin_indices[coin] = idx
	coin.multimesh_index = idx
	coin.set_mesh_visible(false)
	_coin_multimesh_instance.multimesh.set_instance_color(idx, coin.cached_color)


func _release_coin_multimesh(coin: Coin) -> void:
	if coin.multimesh_index < 0:
		return
	var idx: int = coin.multimesh_index
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -9999, 0))
	_coin_multimesh_instance.multimesh.set_instance_transform(idx, hidden)
	_coin_free_indices.append(idx)
	_active_coin_indices.erase(coin)
	coin.multimesh_index = -1


func eject_coin_from_multimesh(coin: Coin) -> void:
	_release_coin_multimesh(coin)
	coin.set_mesh_visible(true)


## Toggles visibility of all coins on this board (in-flight, queued, prestige).
## Pegs and buckets stay visible. Used by BoardManager to hide inactive boards' coins.
func set_coins_visible(vis: bool) -> void:
	if _coin_multimesh_instance:
		_coin_multimesh_instance.visible = vis
	for coin in _active_coin_indices.keys():
		if is_instance_valid(coin):
			coin.visible = vis
	if coin_queue:
		coin_queue.visible = vis


func _grow_coin_multimesh() -> void:
	var mm := _coin_multimesh_instance.multimesh
	var old_count: int = mm.instance_count
	var new_count: int = old_count * 2

	# Save existing data
	var old_transforms: Array[Transform3D] = []
	var old_colors: Array[Color] = []
	for i in old_count:
		old_transforms.append(mm.get_instance_transform(i))
		old_colors.append(mm.get_instance_color(i))

	# Resize
	mm.instance_count = new_count

	# Restore existing data
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -9999, 0))
	for i in old_count:
		mm.set_instance_transform(i, old_transforms[i])
		mm.set_instance_color(i, old_colors[i])
	for i in range(old_count, new_count):
		mm.set_instance_transform(i, hidden)

	# Add new indices to pool (in reverse so pop_back gives lowest first)
	for i in range(new_count - 1, old_count - 1, -1):
		_coin_free_indices.append(i)


func _sync_coin_multimesh(delta: float) -> void:
	var mm := _coin_multimesh_instance.multimesh
	var t: VisualTheme = ThemeProvider.theme
	var impact_duration: float = t.coin_impact_squash_duration
	var impact_peak: Vector3 = t.coin_impact_squash_scale
	var coin_radius: float = t.coin_radius
	for coin: Coin in _active_coin_indices:
		if not is_instance_valid(coin):
			continue
		var idx: int = _active_coin_indices[coin]

		# Impact squash: lerp from peak scale back to identity over the recovery
		# duration. Triggered by Coin._bounce_or_despawn on peg contact.
		var basis: Basis = _coin_mesh_basis
		var pos: Vector3 = coin.position
		if coin.impact_squash_remaining > 0.0 and impact_duration > 0.0:
			coin.impact_squash_remaining = maxf(0.0, coin.impact_squash_remaining - delta)
			var k: float = coin.impact_squash_remaining / impact_duration  # 1=peak, 0=done
			var scale: Vector3 = Vector3.ONE.lerp(impact_peak, k)
			# Apply scale in world space (left-multiply) so the squash flattens
			# along world Y regardless of how _coin_mesh_basis rotates the mesh.
			basis = Basis.IDENTITY.scaled(scale) * _coin_mesh_basis
			# Sink the coin so its bottom edge stays planted on the peg as it
			# squashes — otherwise the squash makes it look like it's hovering.
			pos.y -= coin_radius * (1.0 - scale.y)

		mm.set_instance_transform(idx, Transform3D(basis, pos))
		mm.set_instance_color(idx, coin.cached_color)


func _on_coin_tree_exiting(coin: Coin) -> void:
	_release_coin_multimesh(coin)


func has_in_flight_coins() -> bool:
	return not _active_coin_indices.is_empty()


func request_drop(costs: Array = [], coin_type: int = -1, is_manual: bool = true) -> void:
	if drop_blocked.is_valid() and drop_blocked.call():
		return

	if costs.is_empty():
		costs = _get_drop_costs()
	var drop_coin_type: Enums.CurrencyType = (coin_type as Enums.CurrencyType) if coin_type != -1 else TierRegistry.primary_currency(board_type)

	if not _can_afford(costs):
		return

	var coin: Coin = CoinScene.instantiate()
	coin.coin_type = drop_coin_type
	if drop_coin_type == advanced_bucket_type:
		coin.multiplier = advanced_coin_multiplier

	if coin_queue.has_queue() and not coin_queue.is_full():
		_spend(costs)
		coin_queue.enqueue(coin, drop_coin_type == advanced_bucket_type)
		if not is_waiting:
			_drop_from_queue()
	elif not is_waiting:
		_spend(costs)
		_drop_immediate_coin(coin)
	else:
		return  # Can't drop right now

	if is_manual:
		AudioManager.play_manual_drop_drum(board_type)


## Returns the multi-drop count for a specific coin color, looked up from that
## coin's native board (not necessarily the current board). Raw orange always
## uses orange's multi-drop, even when dropped on gold.
func _get_multi_drop_for_coin_type(coin_type: Enums.CurrencyType) -> int:
	var tier := TierRegistry.get_tier_for_currency(coin_type)
	var native_board: Enums.BoardType = tier.board_type if tier else board_type
	return PrestigeManager.get_multi_drop(native_board) + ChallengeProgressManager.get_bonus_multi_drop(native_board)


## Returns the costs to drop a normal coin on this board.
func _get_drop_costs() -> Array:
	return TierRegistry.get_drop_costs(board_type)


## Returns the cost to drop an advanced coin (1 raw currency of the next tier).
func _get_advanced_drop_costs() -> Array:
	return [[advanced_bucket_type, 1]]


func _can_afford(costs: Array) -> bool:
	for cost in costs:
		if not CurrencyManager.can_afford(cost[0], cost[1]):
			return false
	return true


func _spend(costs: Array) -> void:
	for cost in costs:
		CurrencyManager.spend(cost[0], cost[1])


func _launch_coin(coin: Coin) -> void:
	coin.board = self
	_coin_z_counter += 1
	coin.position = Vector3(0, vertical_spacing + 0.2, _coin_z_counter * 0.001)
	add_child(coin)
	_allocate_coin_multimesh(coin)
	coin.tree_exiting.connect(_on_coin_tree_exiting.bind(coin), CONNECT_ONE_SHOT)
	coin.landed.connect(on_coin_landed)
	coin.final_bounce_started.connect(_on_final_bounce_started)
	coin.start(Vector3(0, 0.2, 0))
	coin_dropped.emit()
	AudioManager.on_coin_dropped()


func _drop_immediate_coin(coin: Coin) -> void:
	_launch_coin(coin)
	_spawn_multi_drop_bonus_coins(coin)
	_start_drop_timer()


## Called when a coin actually launches onto the board. Spawns N-1 bonus coins
## (staggered) if multi-drop is active for this coin type, and fires burst VFX.
func _spawn_multi_drop_bonus_coins(coin: Coin) -> void:
	var coin_multi_drop: int = _get_multi_drop_for_coin_type(coin.coin_type)
	_try_emit_drop_burst(coin.coin_type)

	if coin_multi_drop <= 1:
		return

	var mult: float = coin.multiplier
	for i in range(1, coin_multi_drop):
		var tween := create_tween()
		tween.tween_interval(i * MULTI_DROP_STAGGER)
		tween.tween_callback(force_drop_coin.bind(coin.coin_type, mult, true))

	_show_multi_drop_label(coin_multi_drop)


## Spawns a 3D drop burst at the drop point if the per-second rate limit hasn't
## been hit. Called once per successful drop (not per multi-drop bonus coin).
func _try_emit_drop_burst(drop_coin_type: Enums.CurrencyType) -> void:
	var t: VisualTheme = ThemeProvider.theme
	if not t.drop_burst_enabled:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	# Prune entries older than 1 second
	while not _drop_burst_times.is_empty() and now - _drop_burst_times[0] >= 1.0:
		_drop_burst_times.remove_at(0)
	if _drop_burst_times.size() >= t.drop_burst_max_per_second:
		return
	_drop_burst_times.append(now)
	var local_pos := Vector3(0, vertical_spacing + 0.2, 0)
	_spawn_drop_burst_3d(local_pos, t.get_coin_color(drop_coin_type))


## Radial burst of small quads scattering outward in the board's XY plane.
## Seeds slots in the shared drop burst MultiMesh; _sync_drop_burst animates them.
func _spawn_drop_burst_3d(local_pos: Vector3, color: Color) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var particle_size: float = t.drop_burst_particle_size
	var count: int = t.drop_burst_particle_count

	for i in count:
		if _drop_burst_free_indices.is_empty():
			return
		var idx: int = _drop_burst_free_indices.pop_back()

		var angle: float = randf() * TAU
		var distance: float = t.drop_burst_spread * randf_range(0.5, 1.0)
		var target: Vector3 = local_pos + Vector3(cos(angle) * distance, sin(angle) * distance, 0.0)
		var duration: float = t.drop_burst_duration * randf_range(0.7, 1.0)

		_active_drop_bursts.append({
			"idx": idx,
			"start": local_pos,
			"target": target,
			"elapsed": 0.0,
			"duration": duration,
			"size": particle_size,
			"color": color,
		})


func _sync_drop_burst(delta: float) -> void:
	var mm := _drop_burst_mm_instance.multimesh
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -9999, 0))
	var i: int = 0
	while i < _active_drop_bursts.size():
		var p: Dictionary = _active_drop_bursts[i]
		p.elapsed += delta
		if p.elapsed < 0.0:
			mm.set_instance_transform(p.idx, hidden)
			i += 1
			continue
		var k: float = clampf(p.elapsed / p.duration, 0.0, 1.0)

		if k >= 1.0:
			mm.set_instance_transform(p.idx, hidden)
			_drop_burst_free_indices.append(p.idx)
			_active_drop_bursts.remove_at(i)
			continue

		var eased_pos: float = 1.0 - (1.0 - k) * (1.0 - k)  # ease-out quad
		var pos: Vector3 = (p.start as Vector3).lerp(p.target, eased_pos)
		var alpha: float = 1.0 - k * k  # ease-in quad fade

		var size: float = p.size
		var basis := Basis.IDENTITY.scaled(Vector3(size, size, size))
		mm.set_instance_transform(p.idx, Transform3D(basis, pos))
		var c: Color = p.color
		c.a = alpha
		mm.set_instance_color(p.idx, c)

		i += 1


## Spawns a stream of particles traveling from center to a target bucket
## position, arriving in travel_time seconds. Reuses the drop burst MultiMesh.
func _spawn_ripple_particles(from: Vector3, to: Vector3, travel_time: float, color: Color, t: VisualTheme) -> void:
	var count: int = 3
	var particle_size: float = t.drop_burst_particle_size * 0.8
	for i in count:
		if _drop_burst_free_indices.is_empty():
			return
		var idx: int = _drop_burst_free_indices.pop_back()
		# Stagger particles slightly and add perpendicular scatter
		var stagger: float = float(i) / float(count) * travel_time * 0.3
		var dir: Vector3 = (to - from).normalized()
		var perp: Vector3 = Vector3(-dir.y, dir.x, 0.0)
		var scatter: float = randf_range(-0.15, 0.15)
		var scattered_target: Vector3 = to + perp * scatter
		_active_drop_bursts.append({
			"idx": idx,
			"start": from,
			"target": scattered_target,
			"elapsed": -stagger,
			"duration": travel_time,
			"size": particle_size,
			"color": color,
		})


## Firework splash at the edge buckets. direction is -1 (left) or +1 (right).
## 10 particles burst in all directions from the edge bucket.
func _spawn_edge_splash(origin: Vector3, _direction: float, delay: float, color: Color, t: VisualTheme) -> void:
	var count: int = 10
	var particle_size: float = t.drop_burst_particle_size
	var spread: float = t.drop_burst_spread * 1.5
	var duration: float = 0.4
	for i in count:
		if _drop_burst_free_indices.is_empty():
			return
		var idx: int = _drop_burst_free_indices.pop_back()
		var angle: float = randf() * TAU
		var dist: float = spread * randf_range(0.5, 1.0)
		var target: Vector3 = origin + Vector3(
			cos(angle) * dist,
			sin(angle) * dist,
			0.0
		)
		_active_drop_bursts.append({
			"idx": idx,
			"start": origin,
			"target": target,
			"elapsed": -delay - randf_range(0.0, 0.05),
			"duration": duration * randf_range(0.8, 1.0),
			"size": particle_size,
			"color": color,
		})


func _drop_from_queue() -> void:
	if coin_queue.is_empty():
		return

	var coin: Coin = coin_queue.dequeue_full()
	if not coin:
		return  # Only FILLING coins in queue, not ready yet
	_launch_coin(coin)
	_spawn_multi_drop_bonus_coins(coin)
	_start_drop_timer()


func _start_drop_timer() -> void:
	is_waiting = true
	_last_effective_delay = get_effective_drop_delay()
	_drop_timer_remaining = _last_effective_delay


## Drop delay after applying the queue's rate bonus. Each queued coin (FULL or
## FILLING) adds QUEUE_RATE_BONUS_PER_COIN to the effective rate (rate = 1/delay),
## which is equivalent to dividing the delay by (1 + bonus * queue.count).
## Naturally bounded — delay shrinks but never reaches zero.
func get_effective_drop_delay() -> float:
	if coin_queue == null:
		return drop_delay
	var bonus_mult: float = 1.0 + QUEUE_RATE_BONUS_PER_COIN * float(coin_queue.count)
	return drop_delay / bonus_mult


func _on_queue_count_changed(_new_count: int) -> void:
	# Rescale the active drop timer proportionally so the player sees an
	# immediate speed-up/slow-down when the queue fills or drains, matching
	# the precedent in decrease_drop_delay().
	if is_waiting and _drop_timer_remaining > 0.0 and _last_effective_delay > 0.0:
		var new_effective: float = get_effective_drop_delay()
		_drop_timer_remaining *= new_effective / _last_effective_delay
		_last_effective_delay = new_effective
	drop_section.set_queue_bonus(coin_queue.count, QUEUE_RATE_BONUS_PER_COIN)


## Cached so we don't re-walk the viewport every frame. Refreshed on demand
## if it's freed (theme swap / scene reload).
var _cached_camera: Camera3D


## Project the spawn point (slot 0 of the queue) into screen space and tell
## the DropSection to anchor its bonus label there. Skipped when the section
## is hidden (non-active board) — saves the unproject + assignment cost.
func _update_queue_bonus_label_position() -> void:
	if not drop_section.visible:
		return
	if not is_instance_valid(coin_queue):
		return
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d()
		if _cached_camera == null:
			return
	var spawn_world: Vector3 = coin_queue.global_position + coin_queue.start_position
	var screen_pos: Vector2 = _cached_camera.unproject_position(spawn_world)
	drop_section.set_queue_bonus_position(screen_pos + QUEUE_BONUS_LABEL_OFFSET)


func _on_drop_timer_done() -> void:
	is_waiting = false
	_drop_timer_remaining = 0.0
	_update_drop_fill()
	if coin_queue.has_queue() and not coin_queue.is_empty():
		_drop_from_queue()


func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
	if not _has_advanced_drop and TierRegistry.has_next_tier(board_type) \
			and _type == advanced_bucket_type and _new_balance > 0:
		_show_advanced_drop_bar()
	_update_drop_fill()


func _update_drop_fill() -> void:
	var can_queue: bool = coin_queue.has_queue() and not coin_queue.is_full()
	var show_cooldown: bool = is_waiting and not can_queue

	var fill_pct: float
	if show_cooldown:
		fill_pct = 1.0 - (_drop_timer_remaining / drop_delay) if drop_delay > 0 else 1.0
	else:
		fill_pct = 1.0

	# Normal drop bar
	_drop_main.set_fill(fill_pct)
	var can_drop_normal: bool = _can_afford(_get_drop_costs()) and not show_cooldown
	_drop_main.set_main_disabled(not can_drop_normal)
	_drop_main.apply_fill_colors(not can_drop_normal)

	# Advanced drop bar
	if _drop_advanced_column.visible:
		_drop_advanced.set_fill(fill_pct)
		var can_drop_advanced: bool = _can_afford(_get_advanced_drop_costs()) and not show_cooldown
		_drop_advanced.set_main_disabled(not can_drop_advanced)
		_drop_advanced.apply_fill_colors(not can_drop_advanced)

	_refresh_needs_tooltip()


func on_coin_landed(coin: Coin) -> void:
	var bucket = get_nearest_bucket(coin.global_position.x)
	finalize_coin_landing(coin, bucket)


## Completes the normal landing flow: adds currency, emits signal, cleans up coin.
## Prestige coins skip currency add and queue_free — the PrestigeAnimator handles them.
func finalize_coin_landing(coin: Coin, bucket: Bucket) -> void:
	# Safety net: if the board rebuilt between final_bounce_started and landing,
	# the predicted bucket may have been normal but the actual bucket is advanced.
	# Catch this and route through the prestige path (skips slow-mo, starts at freeze).
	if not coin.is_prestige_coin and _will_trigger_prestige(bucket.currency_type):
		prestige_coin_landed.emit(coin, bucket)
		if coin.is_prestige_coin:
			return

	var t: VisualTheme = ThemeProvider.theme
	var bucket_idx := _get_bucket_index(bucket)
	var target_multiplier: float = 1.0
	if _gameplay_target_enabled and bucket_idx == _gameplay_target_index:
		target_multiplier = 2.0
		_pick_new_gameplay_target()
	var amount: int = roundi(bucket.value * coin.multiplier * target_multiplier)
	var was_already_singing := bucket.is_singing()
	var singing_bonus: int = 1 if was_already_singing else 0
	if not coin.is_prestige_coin:
		CurrencyManager.add(bucket.currency_type, amount + singing_bonus)
		coin_landed.emit(board_type, bucket_idx, bucket.currency_type, amount + singing_bonus, coin.multiplier)
	bucket.pulse()
	var num_buckets: int = buckets_container.get_child_count()
	var bucket_distance: int = absi(bucket_idx - num_buckets / 2)
	var is_advanced: bool = coin.coin_type == advanced_bucket_type
	# Suppress singing during upgrade ripple — the ripple owns the arpeggio.
	# If bucket is already singing, skip audio — it keeps its original timer.
	if not _upgrade_animating and not was_already_singing:
		if AudioManager.request_bucket_play(board_type, bucket_idx, bucket_distance, is_advanced):
			bucket.mark_singing()
			_singing_positions[_bucket_position_key(bucket.position.x + buckets_container.position.x)] = true
	AudioManager.on_coin_landed()
	var effective_multiplier := coin.multiplier * target_multiplier
	var has_multiplier_text := effective_multiplier > 1.0 and not coin.is_prestige_coin
	if has_multiplier_text:
		_show_floating_text(coin.global_position, effective_multiplier, amount)
	if was_already_singing and not coin.is_prestige_coin:
		_show_bonus_text(coin.global_position, 0.1 if has_multiplier_text else 0.0)
	if not coin.is_prestige_coin:
		coin.queue_free()


## Called when a coin starts its final bounce and we can predict which bucket it will land in.
## If this landing would trigger a prestige, emit prestige_coin_landed so the animator can take over.
func _on_final_bounce_started(coin: Coin, predicted_bucket: Bucket) -> void:
	if _will_trigger_prestige(predicted_bucket.currency_type):
		prestige_coin_landed.emit(coin, predicted_bucket)


## Checks if earning this currency type would trigger a prestige for a new board.
func _will_trigger_prestige(currency_type: Enums.CurrencyType) -> bool:
	for i in range(1, TierRegistry.get_tier_count()):
		var tier := TierRegistry.get_tier_by_index(i)
		if tier.raw_currency == currency_type:
			return PrestigeManager.can_prestige(tier.board_type)
	return false


func _get_bucket_index(bucket: Bucket) -> int:
	var children := buckets_container.get_children()
	return children.find(bucket)


func get_bucket(index: int) -> Bucket:
	var children := buckets_container.get_children()
	if index >= 0 and index < children.size():
		return children[index]
	return null


## Stable integer key for a bucket's world x-position. Survives board rebuilds
## because x-positions are geometry-derived (they stay the same for the same
## board slot even as bucket_idx shifts when rows are added).
func _bucket_position_key(world_x: float) -> int:
	return roundi(world_x * BUCKET_POSITION_KEY_SCALE)


func mark_bucket_hit(index: int) -> void:
	_bucket_markings[index] = &"hit"
	var bucket := get_bucket(index)
	if bucket:
		bucket.mark_hit()


func mark_bucket_target(index: int) -> void:
	_bucket_markings[index] = &"target"
	var bucket := get_bucket(index)
	if bucket:
		bucket.mark_target()


func mark_bucket_forbidden(index: int) -> void:
	_bucket_markings[index] = &"forbidden"
	var bucket := get_bucket(index)
	if bucket:
		bucket.mark_forbidden()


func unmark_bucket(index: int) -> void:
	_bucket_markings.erase(index)
	var bucket := get_bucket(index)
	if bucket:
		bucket.mark_unhit()


func clear_all_markings() -> void:
	for index in _bucket_markings:
		var bucket := get_bucket(index)
		if bucket:
			bucket.mark_unhit()
	_bucket_markings.clear()


## Gameplay target: picks a new random bucket, avoiding the current one.
func _pick_new_gameplay_target() -> void:
	var num_buckets := buckets_container.get_child_count()
	if num_buckets <= 0:
		return
	# Clear old target
	if _gameplay_target_index >= 0 and _gameplay_target_index < num_buckets:
		var old_bucket := get_bucket(_gameplay_target_index)
		if old_bucket:
			old_bucket.stop_gameplay_target()
	# Pick new index, avoiding the current one
	var new_index: int = _gameplay_target_index
	if num_buckets > 1:
		while new_index == _gameplay_target_index:
			new_index = randi_range(0, num_buckets - 1)
	else:
		new_index = 0
	_gameplay_target_index = new_index
	_gameplay_target_timer = GAMEPLAY_TARGET_DURATION
	_gameplay_target_fading = false
	var bucket := get_bucket(_gameplay_target_index)
	if bucket:
		bucket.mark_gameplay_target()


func set_gameplay_target_enabled(enabled: bool) -> void:
	if _gameplay_target_enabled == enabled:
		return
	_gameplay_target_enabled = enabled
	if not enabled:
		if _gameplay_target_index >= 0:
			var bucket := get_bucket(_gameplay_target_index)
			if bucket:
				bucket.stop_gameplay_target()
		_gameplay_target_index = -1
	else:
		_pick_new_gameplay_target()


func _init_gameplay_target() -> void:
	# 2x bonus bucket is main-mode only — disabled for every challenge.
	set_gameplay_target_enabled(not ChallengeManager.is_active_challenge)


func force_drop_coin(type: Enums.CurrencyType, mult: float = 1.0, show_burst: bool = false) -> void:
	var coin = CoinScene.instantiate()
	coin.coin_type = type
	coin.multiplier = mult
	_launch_coin(coin)
	if show_burst:
		_try_emit_drop_burst(type)


func _on_rewards_claimed(_level: int, rewards: Array[RewardData]) -> void:
	for reward in rewards:
		if reward.type == RewardData.RewardType.DROP_COINS and reward.target_board == board_type:
			var mult: float = advanced_coin_multiplier if reward.coin_type == advanced_bucket_type else 1.0
			for i in reward.coin_count:
				force_drop_coin(reward.coin_type, mult)
		elif reward.type == RewardData.RewardType.UNLOCK_UPGRADE and reward.board_type == board_type:
			if upgrade_allowed.is_valid() and not upgrade_allowed.call(reward.upgrade_type):
				# Drop an advanced coin instead of unlocking a blocked upgrade
				if advanced_bucket_type >= 0:
					force_drop_coin(advanced_bucket_type, advanced_coin_multiplier)
				else:
					force_drop_coin(TierRegistry.primary_currency(board_type), advanced_coin_multiplier)
		elif reward.type == RewardData.RewardType.UNLOCK_ADVANCED_BUCKET and reward.target_board == board_type:
			should_show_advanced_buckets = true
			build_board()


func _on_reconcile_reward(reward: RewardData) -> void:
	if reward.type == RewardData.RewardType.UNLOCK_ADVANCED_BUCKET \
			and reward.target_board == board_type \
			and not should_show_advanced_buckets:
		should_show_advanced_buckets = true
		build_board()


func _show_advanced_drop_bar() -> void:
	if _has_advanced_drop:
		return
	_has_advanced_drop = true
	var t: VisualTheme = ThemeProvider.theme
	var adv_color: Color = t.get_coin_color(advanced_bucket_type)
	var adv_color_dark: Color = t.get_coin_color_faded(advanced_bucket_type)
	_drop_advanced.setup(adv_color, adv_color_dark)
	_drop_advanced.update_text("Drop %s" % FormatUtils.currency_name(advanced_bucket_type))
	_drop_advanced.main_pressed.connect(func(): request_drop(_get_advanced_drop_costs(), advanced_bucket_type))
	_drop_advanced.main_mouse_entered.connect(_on_drop_advanced_hover)
	_drop_advanced.main_mouse_exited.connect(_on_drop_hover_exit)
	_drop_advanced.side_button_hover.connect(_on_drop_side_hover)

	# B key shortcut for advanced drop
	var adv_shortcut := Shortcut.new()
	var adv_key := InputEventAction.new()
	adv_key.action = "drop_unrefined"
	adv_shortcut.events = [adv_key]
	_drop_advanced.main_button.shortcut = adv_shortcut
	_drop_advanced.main_button.shortcut_in_tooltip = false

	_drop_advanced_column.visible = true
	var adv_id := StringName("%s_ADVANCED" % Enums.BoardType.keys()[board_type])
	_drop_buttons[adv_id] = _drop_advanced
	if _advanced_autodroppers_visible:
		_setup_autodropper_buttons(adv_id)


func get_nearest_bucket(x_position: float) -> Bucket:
	for bucket in buckets_container.get_children():
		if abs(bucket.global_position.x - x_position) < 0.5:
			return bucket
	return buckets_container.get_children()[0]

func build_board() -> void:
	# Kill any in-flight upgrade ripple — its bucket references become stale.
	if _upgrade_ripple_tween and _upgrade_ripple_tween.is_valid():
		_upgrade_ripple_tween.kill()
	_upgrade_animating = false

	# Clear old pegs (MultiMesh)
	if _peg_multimesh_instance:
		_peg_multimesh_instance.queue_free()
		_peg_multimesh_instance = null
	_active_flashes.clear()
	for child in pegs_container.get_children():
		child.queue_free()

	for child in buckets_container.get_children():
		buckets_container.remove_child(child)
		child.queue_free()

	var t: VisualTheme = ThemeProvider.theme
	_peg_base_color = t.peg_color

	# Calculate peg positions
	var total_pegs: int = num_rows * (num_rows + 1) / 2
	_peg_positions = PackedVector3Array()
	_peg_positions.resize(total_pegs)

	var idx := 0
	for i in range(num_rows):
		var x_offset = -i * space_between_pegs / 2
		var y = -vertical_spacing * i
		for j in range(i + 1):
			_peg_positions[idx] = Vector3(x_offset + (j * space_between_pegs), y, 0)
			idx += 1

	# Build MultiMesh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = total_pegs
	mm.mesh = t.make_peg_mesh()

	_peg_basis = Basis.IDENTITY
	if t.peg_shape == VisualTheme.PegShape.CYLINDER:
		_peg_basis = Basis.from_euler(Vector3(PI / 2, 0, 0))

	for i in total_pegs:
		mm.set_instance_transform(i, Transform3D(_peg_basis, _peg_positions[i]))
		mm.set_instance_color(i, _peg_base_color)

	_peg_multimesh_instance = MultiMeshInstance3D.new()
	_peg_multimesh_instance.multimesh = mm
	_peg_multimesh_instance.material_override = t.make_peg_shader_material()
	pegs_container.add_child(_peg_multimesh_instance)

	# --- Coin MultiMesh (only created once, persists across rebuilds) ---
	if not _coin_multimesh_instance:
		var coin_capacity := 64
		var coin_mm := MultiMesh.new()
		coin_mm.transform_format = MultiMesh.TRANSFORM_3D
		coin_mm.use_colors = true
		coin_mm.mesh = t.make_coin_mesh()
		coin_mm.instance_count = coin_capacity

		var hidden_xform := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -9999, 0))
		for i in coin_capacity:
			coin_mm.set_instance_transform(i, hidden_xform)

		_coin_multimesh_instance = MultiMeshInstance3D.new()
		_coin_multimesh_instance.multimesh = coin_mm
		var coin_mat := ShaderMaterial.new()
		coin_mat.shader = preload("res://entities/coin/coin_multimesh.gdshader")
		_coin_multimesh_instance.material_override = coin_mat
		add_child(_coin_multimesh_instance)

		for i in range(coin_capacity - 1, -1, -1):
			_coin_free_indices.append(i)

	# --- Drop burst MultiMesh (only created once, persists across rebuilds) ---
	if not _drop_burst_mm_instance:
		var burst_capacity := 64
		var burst_mesh := QuadMesh.new()
		burst_mesh.size = Vector2.ONE  # scaled per-instance via transform basis

		var burst_mm := MultiMesh.new()
		burst_mm.transform_format = MultiMesh.TRANSFORM_3D
		burst_mm.use_colors = true
		burst_mm.mesh = burst_mesh
		burst_mm.instance_count = burst_capacity

		var hidden_burst_xform := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -9999, 0))
		for i in burst_capacity:
			burst_mm.set_instance_transform(i, hidden_burst_xform)

		_drop_burst_mm_instance = MultiMeshInstance3D.new()
		_drop_burst_mm_instance.multimesh = burst_mm
		var burst_mat := ShaderMaterial.new()
		burst_mat.shader = preload("res://entities/plinko_board/drop_burst_multimesh.gdshader")
		_drop_burst_mm_instance.material_override = burst_mat
		add_child(_drop_burst_mm_instance)

		for i in range(burst_capacity - 1, -1, -1):
			_drop_burst_free_indices.append(i)

	if t.coin_shape == VisualTheme.CoinShape.CYLINDER:
		_coin_mesh_basis = Basis.from_euler(Vector3(PI / 2, 0, 0))
	else:
		_coin_mesh_basis = Basis.IDENTITY

	var num_buckets = num_rows + 1
	var bucket_x_offset = -space_between_pegs * (num_buckets - 1) / 2
	var bucket_y_offset = -vertical_spacing * num_rows + (vertical_spacing / 3)
	buckets_container.position = Vector3(bucket_x_offset, bucket_y_offset, 0)
	
	for i in range(num_buckets):
		var bucket = BucketScene.instantiate()

		@warning_ignore("integer_division")

		var distance_from_center = (abs(i - floor(num_buckets / 2))) 

		var bucket_currency: Enums.CurrencyType = TierRegistry.primary_currency(board_type)
		if distance_from_center >= distance_for_advanced_buckets and should_show_advanced_buckets:
			bucket_currency = advanced_bucket_type

		var value: int = _bucket_value_for_distance(distance_from_center)
		bucket.is_prestige_bucket = _will_trigger_prestige(bucket_currency)
		buckets_container.add_child(bucket)
		bucket.setup(bucket_currency, Vector3(i * space_between_pegs, 0, 0), value)
		bucket.stopped_singing.connect(_on_bucket_stopped_singing.bind(bucket))

	# Re-apply stored markings after rebuild
	for index in _bucket_markings:
		var bucket := get_bucket(index)
		if bucket:
			match _bucket_markings[index]:
				&"hit": bucket.mark_hit()
				&"target": bucket.mark_target()
				&"forbidden": bucket.mark_forbidden()

	# Re-apply singing visuals for buckets that were singing before the rebuild
	# (matched by world x-position so they survive index shifts from row adds).
	if not _singing_positions.is_empty():
		for child in buckets_container.get_children():
			if child is Bucket:
				var key: int = _bucket_position_key(child.position.x + buckets_container.position.x)
				if _singing_positions.has(key):
					child.mark_singing()

	# Re-apply gameplay target after rebuild
	if _gameplay_target_enabled and _gameplay_target_index >= 0:
		var bucket_count := buckets_container.get_child_count()
		if _gameplay_target_index >= bucket_count:
			_pick_new_gameplay_target()
		else:
			var target_bucket := get_bucket(_gameplay_target_index)
			if target_bucket:
				if _gameplay_target_fading:
					target_bucket.start_gameplay_target_fade(_gameplay_target_timer)
				else:
					target_bucket.mark_gameplay_target()

	board_rebuilt.emit()


## Returns the bounding rect of this board in local space.
## Used by BoardManager to frame the camera.
func get_bounds() -> Rect2:
	var top := vertical_spacing + 0.5
	var bottom := -vertical_spacing * num_rows + (vertical_spacing / 3) - 0.5
	var half_width := (num_rows / 2.0) * space_between_pegs + 0.5
	return Rect2(-half_width, bottom, half_width * 2.0, top - bottom)


func add_two_rows() -> void:
	num_rows += 2
	build_board()

## Computes the value for a bucket at a given distance from center.
## Used by both build_board() and the upgrade ripple to keep the formula in one place.
func _bucket_value_for_distance(distance: int) -> int:
	var effective_distance: int = distance
	if distance >= distance_for_advanced_buckets and should_show_advanced_buckets:
		effective_distance = distance - distance_for_advanced_buckets
	var val: int = 1 + effective_distance * bucket_value_multiplier
	var pct_bonus := ChallengeProgressManager.get_bucket_value_percent_bonus(board_type)
	if pct_bonus > 0.0:
		val = roundi(val * (1.0 + pct_bonus))
	return val


func increase_bucket_values() -> void:
	bucket_value_multiplier += 1
	_play_bucket_value_upgrade_ripple()


## Animates bucket value changes as a center-outward ripple with split pulse,
## ticket-counter labels, and a harp arpeggio at half BUCKET_WAIT intervals.
func _play_bucket_value_upgrade_ripple() -> void:
	_upgrade_animating = true
	if _upgrade_ripple_tween and _upgrade_ripple_tween.is_valid():
		_upgrade_ripple_tween.kill()

	var num_buckets: int = buckets_container.get_child_count()
	@warning_ignore("integer_division")
	var center: int = num_buckets / 2
	var max_distance: int = center

	# Group buckets by distance from center, compute new values
	var distance_groups: Dictionary = {}  # int -> Array[Dictionary]
	for i in num_buckets:
		var bucket: Bucket = get_bucket(i)
		if not bucket:
			continue
		var distance: int = absi(i - center)
		if not distance_groups.has(distance):
			distance_groups[distance] = []

		var is_adv: bool = distance >= distance_for_advanced_buckets and should_show_advanced_buckets
		var new_value: int = _bucket_value_for_distance(distance)

		distance_groups[distance].append({
			"bucket": bucket,
			"index": i,
			"distance": distance,
			"old_value": bucket.value,
			"new_value": new_value,
			"is_advanced": is_adv,
		})

	var t: VisualTheme = ThemeProvider.theme
	var ripple_interval: float = AudioManager.BUCKET_WAIT / 2.0
	var label_duration: float = ripple_interval * 0.8
	var pulse_down_duration: float = t.bucket_pulse_duration * 0.25 if t else 0.05

	# Particle wavefront: spawn bursts from center toward each distance tier,
	# timed so particles arrive when the tier activates.
	var center_bucket: Bucket = get_bucket(center)
	var center_pos: Vector3 = buckets_container.position + center_bucket.position if center_bucket else buckets_container.position
	var ripple_color: Color = t.get_coin_color(TierRegistry.primary_currency(board_type))
	for distance in range(1, max_distance + 1):
		if not distance_groups.has(distance):
			continue
		var group_for_particles: Array = distance_groups[distance]
		var travel_time: float = ripple_interval * distance
		for entry in group_for_particles:
			var bucket: Bucket = entry["bucket"]
			var target_pos: Vector3 = buckets_container.position + bucket.position
			_spawn_ripple_particles(center_pos, target_pos, travel_time, ripple_color, t)

	# Splash at the edges: when the wavefront reaches the outermost buckets,
	# particles burst outward like water hitting the end of a pipe.
	var splash_delay: float = ripple_interval * max_distance
	var left_bucket: Bucket = get_bucket(0)
	var right_bucket: Bucket = get_bucket(num_buckets - 1)
	if left_bucket:
		var left_pos: Vector3 = buckets_container.position + left_bucket.position
		_spawn_edge_splash(left_pos, -1.0, splash_delay, ripple_color, t)
	if right_bucket:
		var right_pos: Vector3 = buckets_container.position + right_bucket.position
		_spawn_edge_splash(right_pos, 1.0, splash_delay, ripple_color, t)

	_upgrade_ripple_tween = create_tween()
	_upgrade_ripple_tween.bind_node(self)

	for distance in range(0, max_distance + 1):
		if not distance_groups.has(distance):
			continue
		var group: Array = distance_groups[distance]

		# Fire all buckets at this distance simultaneously
		_upgrade_ripple_tween.tween_callback(func() -> void:
			for entry in group:
				var bucket: Bucket = entry["bucket"]
				var old_val: int = entry["old_value"]
				var new_val: int = entry["new_value"]
				var idx: int = entry["index"]
				var d: int = entry["distance"]
				var is_adv: bool = entry["is_advanced"]

				bucket.value = new_val
				bucket.pulse_down()
				bucket.animate_value_upgrade(old_val, new_val, label_duration)
				AudioManager.force_play_bucket(board_type, idx, d, is_adv)
				bucket.mark_singing()
		)

		# Wait for the press to bottom out, then spring back up
		_upgrade_ripple_tween.tween_interval(pulse_down_duration)
		var group_ref: Array = group
		_upgrade_ripple_tween.tween_callback(func() -> void:
			for entry in group_ref:
				entry["bucket"].pulse_up()
		)

		# Wait the remainder of the ripple interval before the next group
		if distance < max_distance:
			var remaining: float = ripple_interval - pulse_down_duration
			if remaining > 0.0:
				_upgrade_ripple_tween.tween_interval(remaining)

	# Clean up after the full ripple
	_upgrade_ripple_tween.tween_callback(func() -> void:
		_upgrade_animating = false
	)

func decrease_drop_delay() -> void:
	var old_delay := drop_delay
	drop_delay *= drop_delay_reduction_factor
	# If currently waiting, scale remaining time proportionally so the player
	# doesn't have to wait the full old duration. The queue bonus multiplier is
	# unchanged here, so the same scale factor applies to the effective delay.
	if is_waiting and old_delay > 0.0:
		_drop_timer_remaining *= drop_delay / old_delay
		_last_effective_delay = get_effective_drop_delay()
	board_rebuilt.emit()

func _show_floating_text(pos: Vector3, multiplier: float, total: int) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var label := Label3D.new()
	if multiplier == floorf(multiplier):
		label.text = "x%d = %s" % [int(multiplier), FormatUtils.format_number(total)]
	else:
		label.text = "x%.1f = %s" % [multiplier, FormatUtils.format_number(total)]
	label.font_size = t.floating_text_font_size
	label.outline_size = t.label_outline_size
	if t.label_font:
		label.font = t.label_font
	label.modulate = t.normal_text_color
	var local_pos := to_local(pos)
	label.position = Vector3(local_pos.x, local_pos.y + 0.3, local_pos.z + 0.05)
	if multiplier >= 9:
		label.modulate = t.high_multiplier_color
	add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y + t.floating_text_rise, t.floating_text_duration)
	tween.parallel().tween_property(label, "modulate:a", 0.0, t.floating_text_duration * 0.5) \
		.set_delay(t.floating_text_duration * 0.5)
	tween.tween_callback(label.queue_free)


func _show_bonus_text(pos: Vector3, delay: float = 0.0) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var label := Label3D.new()
	label.text = "Recency bonus +1"
	label.font_size = t.floating_text_font_size
	label.outline_size = t.label_outline_size
	if t.label_font:
		label.font = t.label_font
	label.modulate = t.normal_text_color
	label.modulate.a = 0.0 if delay > 0.0 else 1.0
	var local_pos := to_local(pos)
	label.position = Vector3(local_pos.x + 0.15, local_pos.y + 0.3, local_pos.z + 0.05)
	add_child(label)
	var tween := create_tween()
	if delay > 0.0:
		tween.tween_property(label, "modulate:a", 1.0, 0.05).set_delay(delay)
	tween.tween_property(label, "position:y", label.position.y + t.floating_text_rise, t.floating_text_duration)
	tween.parallel().tween_property(label, "modulate:a", 0.0, t.floating_text_duration * 0.5) \
		.set_delay(t.floating_text_duration * 0.5)
	tween.tween_callback(label.queue_free)


func _show_multi_drop_label(count: int) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var label := Label3D.new()
	label.text = "x%d" % count
	label.font_size = t.multi_drop_font_size
	label.outline_size = t.label_outline_size
	if t.label_font:
		label.font = t.label_font
	label.modulate = t.normal_text_color
	label.position = Vector3(0, vertical_spacing + 0.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y + 0.5, 0.6)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func flash_nearest_peg(coin_pos: Vector3, currency_type: int) -> void:
	if _peg_positions.is_empty():
		return
	if not AudioManager.is_active_board(board_type):
		return

	var t: VisualTheme = ThemeProvider.theme
	var local_pos := to_local(coin_pos)
	var closest_idx := -1
	var closest_dist := INF
	var threshold := space_between_pegs * 0.8

	for i in _peg_positions.size():
		var dist := local_pos.distance_to(_peg_positions[i])
		if dist < closest_dist and dist < threshold:
			closest_dist = dist
			closest_idx = i

	if closest_idx < 0:
		return

	var glow_color := t.get_coin_color(currency_type)
	var is_sparkle: bool = AudioManager.should_sparkle(board_type)

	if is_sparkle:
		AudioManager.play_peg_sparkle(board_type)

	if t.peg_flash_enabled:
		_peg_multimesh_instance.multimesh.set_instance_color(closest_idx, glow_color)
		_active_flashes[closest_idx] = {
			"start_color": glow_color,
			"elapsed": 0.0,
			"duration": t.peg_glow_duration,
		}

	# Pulse fires on every peg hit so the player always gets a scale-pop cue
	# on contact. The expanding coin-colored ring below is the sparkle cue.
	if t.peg_pulse_enabled:
		_active_peg_pulses[closest_idx] = {
			"elapsed": 0.0,
			"duration": t.peg_pulse_duration,
		}

	if t.peg_glow_halo_enabled:
		_spawn_peg_halo(_peg_positions[closest_idx], glow_color, t)
	# Ring is the sparkle visual — coin-colored so it reads as a rewarding
	# accent rather than a generic ripple.
	if t.peg_ring_enabled and is_sparkle:
		_spawn_peg_ring(_peg_positions[closest_idx], glow_color, t)


func _spawn_peg_halo(peg_local_pos: Vector3, glow_color: Color, t: VisualTheme) -> void:
	var halo_shader: Shader = preload("res://entities/coin/coin_halo.gdshader")
	var halo := MeshInstance3D.new()
	var halo_mesh := QuadMesh.new()
	halo_mesh.size = Vector2(t.peg_glow_halo_radius, t.peg_glow_halo_radius)
	halo.mesh = halo_mesh
	var halo_mat := ShaderMaterial.new()
	halo_mat.shader = halo_shader
	var halo_color := glow_color
	halo_color.a = t.peg_glow_halo_opacity
	halo_mat.set_shader_parameter("glow_color", halo_color)
	halo_mat.set_shader_parameter("opacity_mult", 1.0)
	halo.material_override = halo_mat
	halo.position = Vector3(peg_local_pos.x, peg_local_pos.y, peg_local_pos.z - 0.05)
	add_child(halo)
	var halo_tween := create_tween()
	halo_tween.tween_property(halo_mat, "shader_parameter/opacity_mult", 0.0, t.peg_glow_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	halo_tween.tween_callback(halo.queue_free)


func _spawn_peg_ring(peg_local_pos: Vector3, ring_color: Color, t: VisualTheme) -> void:
	var ring_shader: Shader = preload("res://entities/plinko_board/peg_ring.gdshader")
	var ring := MeshInstance3D.new()
	var ring_mesh := QuadMesh.new()
	var quad_size: float = t.peg_ring_max_radius * 2.0
	ring_mesh.size = Vector2(quad_size, quad_size)
	ring.mesh = ring_mesh
	var mat := ShaderMaterial.new()
	mat.shader = ring_shader
	mat.set_shader_parameter("ring_color", ring_color)
	mat.set_shader_parameter("ring_thickness", t.peg_ring_thickness)
	mat.set_shader_parameter("ring_radius", 0.0)
	mat.set_shader_parameter("opacity_mult", 0.0)
	ring.material_override = mat
	ring.position = Vector3(peg_local_pos.x, peg_local_pos.y, peg_local_pos.z - 0.04)
	add_child(ring)

	var duration: float = t.peg_ring_duration
	var max_opacity: float = t.peg_ring_max_opacity
	var tween := create_tween()
	tween.tween_method(
		func(p: float) -> void:
			mat.set_shader_parameter("ring_radius", p)
			mat.set_shader_parameter("opacity_mult", sin(p * PI) * max_opacity),
		0.0, 1.0, duration)
	tween.tween_callback(ring.queue_free)


func increase_queue_capacity() -> void:
	coin_queue.set_capacity(coin_queue.capacity + 1)


func try_autodrop(is_advanced: bool) -> void:
	var costs: Array = _get_advanced_drop_costs() if is_advanced else _get_drop_costs()
	if not _can_afford(costs):
		autodrop_failed.emit(board_type)
		return
	# Atomically: complete FILLING → move to FULL section → add replacement FILLING.
	# Single slide pass avoids overlapping tweens that caused position glitches.
	var coin: Coin = coin_queue.complete_and_requeue_filling(is_advanced)
	if coin:
		_spend(costs)
		# Trigger a drop if the board isn't on cooldown
		if not is_waiting:
			_drop_from_queue()
	else:
		# No FILLING coin found — fallback to normal request_drop
		var coin_type: int = advanced_bucket_type if is_advanced else -1
		request_drop(costs, coin_type, false)


func set_normal_autodroppers_visible(vis: bool) -> void:
	_normal_autodroppers_visible = vis
	if vis:
		for bid in _drop_buttons:
			if not (bid as String).ends_with("_ADVANCED"):
				_setup_autodropper_buttons(bid)


func set_advanced_autodroppers_visible(vis: bool) -> void:
	_advanced_autodroppers_visible = vis
	if vis:
		for bid in _drop_buttons:
			if (bid as String).ends_with("_ADVANCED"):
				_setup_autodropper_buttons(bid)


func _setup_autodropper_buttons(bid: StringName) -> void:
	var bar = _drop_buttons[bid]
	var currency_name: String = _get_currency_name_for_button(bid)
	var captured_bid: StringName = bid
	var is_adv: bool = (bid as String).ends_with("_ADVANCED")
	var pool_board: Enums.BoardType = Enums.BoardType.RED if is_adv else Enums.BoardType.ORANGE
	var pool_type: Enums.UpgradeType = Enums.UpgradeType.ADVANCED_AUTODROPPER if is_adv else Enums.UpgradeType.AUTODROPPER
	var label: String = "advanced autodropper" if is_adv else "autodropper"

	bar.setup_minus(
		func(): autodropper_adjust_requested.emit(captured_bid, -1),
		func() -> String:
			var total: int = UpgradeManager.get_level(pool_board, pool_type)
			return "Decrease %s for %s\nTotal: %d" % [label, currency_name, total],
	)

	bar.setup_plus(
		func(): autodropper_adjust_requested.emit(captured_bid, 1),
		func() -> String:
			var total: int = UpgradeManager.get_level(pool_board, pool_type)
			return "Increase %s for %s\nTotal: %d" % [label, currency_name, total],
	)


func _get_currency_name_for_button(bid: StringName) -> String:
	if (bid as String).ends_with("_ADVANCED"):
		return FormatUtils.currency_name(advanced_bucket_type, false)
	return FormatUtils.currency_name(TierRegistry.primary_currency(board_type), false)


func update_autodropper_buttons(assignments: Dictionary, normal_free: int, advanced_free: int) -> void:
	for bid in _drop_buttons:
		var bar = _drop_buttons[bid]
		var assigned: int = assignments.get(bid, 0)
		var free: int = advanced_free if (bid as String).ends_with("_ADVANCED") else normal_free
		bar.set_minus_disabled(assigned <= 0)
		bar.set_minus_filled(assigned > 0)
		bar.set_plus_disabled(free <= 0)
		bar.set_plus_filled(free > 0)


func get_drop_button(btn_id: StringName):
	return _drop_buttons.get(btn_id)


func get_drop_button_ids() -> Array:
	return _drop_buttons.keys()


func set_drop_subtext(button_id: StringName, text: String) -> void:
	var bar: FillBar = _drop_buttons.get(button_id)
	if not bar:
		return
	var label: Label
	if bar == _drop_main:
		label = _drop_main_label
	elif bar == _drop_advanced:
		label = _drop_advanced_label
	else:
		return
	if not label.has_meta("styled"):
		var t: VisualTheme = ThemeProvider.theme
		label.add_theme_font_size_override("font_size", maxi(t.button_font_size - 4, 8))
		label.add_theme_color_override("font_color", t.normal_text_color)
		var btn_font: Font = t.button_font if t.button_font else preload("res://style_lab/VendSans-Bold.ttf")
		label.add_theme_font_override("font", btn_font)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.set_meta("styled", true)
	label.text = text


## Applies saved upgrade state to this board without going through buy logic.
## Permanent challenge bonuses are added on top of player-bought upgrade levels.
func apply_saved_state(upgrade_state: Dictionary) -> void:
	var add_row_level: int = upgrade_state.get("ADD_ROW", 0)
	num_rows = 2 + add_row_level * 2

	var perm_bv: int = ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.BUCKET_VALUE)
	bucket_value_multiplier = 1 + upgrade_state.get("BUCKET_VALUE", 0) + perm_bv

	var base_acm: float = upgrade_state.get("advanced_coin_multiplier", 2.0)
	var bonus_acm: float = ChallengeProgressManager.get_advanced_coin_multiplier_bonus(board_type)
	advanced_coin_multiplier = base_acm + bonus_acm

	var drop_rate_level: int = upgrade_state.get("DROP_RATE", 0)
	var perm_dr: int = ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.DROP_RATE)
	for i in drop_rate_level + perm_dr:
		drop_delay *= drop_delay_reduction_factor

	var queue_level: int = upgrade_state.get("QUEUE", 0)
	var perm_q: int = ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.QUEUE)
	coin_queue.set_capacity(queue_level + perm_q)

	if upgrade_state.get("show_advanced_buckets", false):
		should_show_advanced_buckets = true
	if upgrade_state.get("has_advanced_drop", false):
		_show_advanced_drop_bar()

	build_board()
