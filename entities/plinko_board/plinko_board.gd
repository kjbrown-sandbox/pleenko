class_name PlinkoBoard
extends Node3D

@export var num_rows: int = 2
var space_between_pegs: float
var vertical_spacing: float
@export var drop_delay: float = 2.0
@export var drop_delay_reduction_factor: float = 0.75
@export var distance_for_advanced_buckets: int = 3 # Before you modify this, know I've tested it and 4 feel awful

## Delay between each bonus coin in a multi-drop, so they don't all land simultaneously.
const MULTI_DROP_STAGGER := 0.15

const BucketScene: PackedScene = preload("res://entities/bucket/bucket.tscn")
const CoinScene := preload("res://entities/coin/coin.tscn")

@onready var pegs_container: Node3D = $Pegs
@onready var buckets_container: Node3D = $Buckets
@onready var upgrade_section = $UpgradeSection
@onready var drop_section = $DropSection
@onready var coin_queue: CoinQueue = $CoinQueue
@onready var _drop_main = $DropSection/DropButtons/DropMain
@onready var _drop_advanced = $DropSection/DropButtons/DropAdvanced
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
var _bucket_markings: Dictionary = {}  # int (bucket index) -> StringName ("hit" | "target" | "forbidden")
var multi_drop_count: int = -1
var _coin_z_counter: int = 0  # Increments per coin so later coins render in front
# True while the mouse is hovering either drop button — used by the tooltip
# refresh logic so the persistent "Needs X" message is suppressed in favor of
# the regular cost tooltip during hover.
var _drop_button_hovered: bool = false

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

func _ready() -> void:
	space_between_pegs = ThemeProvider.theme.space_between_pegs
	vertical_spacing = space_between_pegs * sqrt(3) / 2 # sqrt because of the 30/60/90 triangle babyyyy
	multi_drop_count = PrestigeManager.get_multi_drop(board_type) + ChallengeProgressManager.get_bonus_multi_drop(board_type)


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
	LevelManager.rewards_claimed.connect(_on_rewards_claimed)
	CurrencyManager.currency_changed.connect(_on_currency_changed)


func _setup_drop_bars() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var currency_type: Enums.CurrencyType = TierRegistry.primary_currency(board_type)
	var coin_color: Color = t.get_coin_color(currency_type)
	var coin_color_dark: Color = t.get_coin_color_faded(currency_type)

	# Main drop bar
	_drop_main.setup(coin_color, coin_color_dark)
	_drop_main.update_text("Drop %s" % FormatUtils.currency_name(currency_type))
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
	_drop_advanced.visible = false


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
	if is_waiting:
		_drop_timer_remaining = maxf(0.0, _drop_timer_remaining - delta)
		_update_drop_fill()
		if _drop_timer_remaining == 0.0:
			_on_drop_timer_done()
	elif _is_hold_to_drop_advanced_active():
		request_drop(_get_advanced_drop_costs(), advanced_bucket_type)
	elif _is_hold_to_drop_active():
		request_drop()

	if not _active_flashes.is_empty():
		_update_peg_flashes(delta)
	if not _active_peg_pulses.is_empty():
		_update_peg_pulses(delta)

	if not _active_coin_indices.is_empty():
		_sync_coin_multimesh(delta)

	if not _active_drop_bursts.is_empty():
		_sync_drop_burst(delta)


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


func _is_hold_to_drop_active() -> bool:
	return Input.is_action_pressed("drop_coin") \
		and ChallengeProgressManager.is_unlocked(ChallengeRewardData.UnlockType.HOLD_TO_DROP) \
		and drop_section.visible


func _is_hold_to_drop_advanced_active() -> bool:
	return Input.is_action_pressed("drop_unrefined") \
		and ChallengeProgressManager.is_unlocked(ChallengeRewardData.UnlockType.HOLD_TO_DROP) \
		and drop_section.visible \
		and _drop_advanced.visible


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


func request_drop(costs: Array = [], coin_type: int = -1) -> void:
	if ChallengeManager.is_active_challenge and ChallengeManager.has_failed():
		return

	if costs.is_empty():
		costs = _get_drop_costs()
	var drop_coin_type: Enums.CurrencyType = (coin_type as Enums.CurrencyType) if coin_type != -1 else TierRegistry.primary_currency(board_type)

	if not _can_afford(costs):
		return

	# Multi-drop count is per-color (the coin's native board), not per the board it's
	# being dropped on. Raw orange dropped on gold uses orange's multi-drop level, etc.
	var coin_multi_drop: int = _get_multi_drop_for_coin_type(drop_coin_type)

	# First coin — normal queue/immediate path (pays cost once)
	var coin: Coin = CoinScene.instantiate()
	coin.coin_type = drop_coin_type
	if drop_coin_type == advanced_bucket_type:
		coin.multiplier = advanced_coin_multiplier

	if coin_queue.has_queue() and not coin_queue.is_full():
		_spend(costs)
		coin_queue.enqueue(coin)
		if not is_waiting:
			_drop_from_queue()
	elif not is_waiting:
		_spend(costs)
		_drop_immediate_coin(coin)
	else:
		return  # Can't drop right now

	# Spawn burst VFX for the first coin. Bonus coins from the multi-drop loop
	# below fire their own bursts via force_drop_coin. The per-board rate limit
	# (drop_burst_max_per_second) naturally caps this during heavy drop storms.
	_try_emit_drop_burst(drop_coin_type)

	# Multi-drop: first coin pays the cost (above). Bonus coins from prestige/challenges
	# are free and staggered so they don't all land in the same bucket simultaneously.
	var mult: float = advanced_coin_multiplier if drop_coin_type == advanced_bucket_type else 1.0
	for i in range(1, coin_multi_drop):
		var tween := create_tween()
		tween.tween_interval(i * MULTI_DROP_STAGGER)
		tween.tween_callback(force_drop_coin.bind(drop_coin_type, mult, true))

	if coin_multi_drop > 1:
		_show_multi_drop_label(coin_multi_drop)


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


func _drop_immediate_coin(coin: Coin) -> void:
	_launch_coin(coin)
	_start_drop_timer()


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


func _drop_from_queue() -> void:
	if coin_queue.is_empty():
		return

	var coin: Coin = coin_queue.dequeue()
	_launch_coin(coin)
	_start_drop_timer()


func _start_drop_timer() -> void:
	is_waiting = true
	_drop_timer_remaining = drop_delay


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
	if _drop_advanced.visible:
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
	var t: VisualTheme = ThemeProvider.theme
	var bucket_idx := _get_bucket_index(bucket)
	var amount: int = roundi(bucket.value * coin.multiplier)
	if not coin.is_prestige_coin:
		CurrencyManager.add(bucket.currency_type, amount)
		coin_landed.emit(board_type, bucket_idx, bucket.currency_type, amount, coin.multiplier)
	bucket.pulse()
	var num_buckets: int = buckets_container.get_child_count()
	var bucket_distance: int = absi(bucket_idx - num_buckets / 2)
	var is_advanced: bool = coin.coin_type == advanced_bucket_type
	AudioManager.play_bucket(board_type, bucket_distance, is_advanced)
	if coin.multiplier > 1 and not coin.is_prestige_coin:
		_show_floating_text(coin.global_position, coin.multiplier, amount)
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
			if ChallengeManager.is_active_challenge and not ChallengeManager.is_upgrade_allowed(reward.upgrade_type):
				# Drop an advanced coin instead of unlocking a blocked upgrade
				if advanced_bucket_type >= 0:
					force_drop_coin(advanced_bucket_type, advanced_coin_multiplier)
				else:
					force_drop_coin(TierRegistry.primary_currency(board_type), advanced_coin_multiplier)
		elif reward.type == RewardData.RewardType.UNLOCK_ADVANCED_BUCKET and reward.target_board == board_type:
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

	_drop_advanced.visible = true
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

		var value = 1
		var bucket_currency: Enums.CurrencyType = TierRegistry.primary_currency(board_type)
		if distance_from_center >= distance_for_advanced_buckets and should_show_advanced_buckets:
			bucket_currency = advanced_bucket_type
			distance_from_center -= distance_for_advanced_buckets

		value += distance_from_center * bucket_value_multiplier
		var pct_bonus := ChallengeProgressManager.get_bucket_value_percent_bonus(board_type)
		if pct_bonus > 0.0:
			value = roundi(value * (1.0 + pct_bonus))
		bucket.is_prestige_bucket = _will_trigger_prestige(bucket_currency)
		buckets_container.add_child(bucket)
		bucket.setup(bucket_currency, Vector3(i * space_between_pegs, 0, 0), value)

	# Re-apply stored markings after rebuild
	for index in _bucket_markings:
		var bucket := get_bucket(index)
		if bucket:
			match _bucket_markings[index]:
				&"hit": bucket.mark_hit()
				&"target": bucket.mark_target()
				&"forbidden": bucket.mark_forbidden()

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

func increase_bucket_values() -> void:
	bucket_value_multiplier += 1
	build_board()

func decrease_drop_delay() -> void:
	var old_delay := drop_delay
	drop_delay *= drop_delay_reduction_factor
	# If currently waiting, scale remaining time proportionally so the player
	# doesn't have to wait the full old duration
	if is_waiting and old_delay > 0.0:
		_drop_timer_remaining *= drop_delay / old_delay

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
	var is_sparkle: bool = randf() < AudioManager.PEG_SPARKLE_CHANCE

	if is_sparkle:
		AudioManager.play_peg_sparkle(board_type)

	# Set instance color to flash color and register for animated fade-back.
	# Always flash on sparkle so the peg visually signals the chime.
	if t.peg_flash_enabled or is_sparkle:
		_peg_multimesh_instance.multimesh.set_instance_color(closest_idx, glow_color)
		_active_flashes[closest_idx] = {
			"start_color": glow_color,
			"elapsed": 0.0,
			"duration": t.peg_glow_duration,
		}

	if t.peg_pulse_enabled:
		_active_peg_pulses[closest_idx] = {
			"elapsed": 0.0,
			"duration": t.bucket_pulse_duration,
		}

	if t.peg_glow_halo_enabled:
		_spawn_peg_halo(_peg_positions[closest_idx], glow_color, t)
	if t.peg_ring_enabled:
		var ring_color: Color = glow_color if is_sparkle else _peg_base_color
		_spawn_peg_ring(_peg_positions[closest_idx], ring_color, t)


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
	coin_queue.set_capacity(coin_queue._capacity + 1)


func try_autodrop(is_advanced: bool) -> void:
	var costs: Array = _get_advanced_drop_costs() if is_advanced else _get_drop_costs()
	var coin_type: int = advanced_bucket_type if is_advanced else -1
	if _can_afford(costs):
		request_drop(costs, coin_type)
	else:
		autodrop_failed.emit(board_type)


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
		_show_advanced_drop_bar()

	build_board()
