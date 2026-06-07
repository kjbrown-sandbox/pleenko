class_name PlinkoBoard
extends Node3D

@export var num_rows: int = 2
var space_between_pegs: float
var vertical_spacing: float
@export var drop_delay: float = 2.0
@export var drop_delay_reduction_factor: float = 0.82
@export var distance_for_advanced_buckets: int = 3 # Before you modify this, know I've tested it and 4 feel awful

## Each coin in the queue (FULL or FILLING) boosts drop rate by this multiplier
## of the base rate. effective_delay = drop_delay / (1 + bonus * queue.count).
## Additive in rate (not delay) keeps the curve self-bounded — delay shrinks
## but never reaches zero. With 1.0, one queued coin doubles the rate, two
## triples it, ten gives 11x the base rate.
const QUEUE_RATE_BONUS_PER_COIN := 0.15

## Each granted QUEUE_RATE_BONUS challenge reward adds this much to the
## per-queued-coin bonus above. Stackable; gold board only (counted globally,
## applied to gold — mirrors GOLD_COIN_SPEED_BOOST).
## The reward's displayed text is derived live from this constant by
## ChallengeRewardData.display_text() (QUEUE_RATE_BONUS case), so changing the
## value updates every reward display automatically — no .tres edits needed.
const QUEUE_RATE_BONUS_PER_UNLOCK := 0.10

## Effective per-queued-coin bonus after folding in earned QUEUE_RATE_BONUS
## rewards. Cached in setup() (challenge progress only changes on a scene
## reload, like Coin's _fall_speed_multiplier) so the autoload isn't queried
## every drop cycle. Defaults to the base so a bare PlinkoBoard.new() (tests,
## null-queue path) works without setup().
var _queue_rate_bonus_per_coin: float = QUEUE_RATE_BONUS_PER_COIN

## Pixel offset from the projected spawn point to the top-left of the bonus
## label box. +X pushes the label right of the queue (clear of the drop
## column); -Y centers a single line vertically against the spawn dot.
const QUEUE_BONUS_LABEL_OFFSET := Vector2(40.0, -16.0)

## Delay between each bonus coin in a multi-drop, so they don't all land simultaneously.
const MULTI_DROP_STAGGER := 0.05

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
@onready var _drop_main_tooltip: Tooltip = $DropSection/DropMainTooltip
@onready var _drop_advanced_tooltip: Tooltip = $DropSection/DropAdvancedTooltip

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
@export var hack_burst: int = 10 
var _coin_z_counter: int = 0  # Increments per coin so later coins render in front
# True while the mouse is hovering the respective drop button — used by the
# tooltip refresh logic so that button's persistent "Needs X" message is
# suppressed in favor of the regular cost tooltip during hover. Tracked per
# button so hovering one never suppresses the other's "Needs X" message.
var _drop_main_hovered: bool = false
var _drop_advanced_hovered: bool = false
# Set while the autodropper +/- cap of a drop button is hovered, so the per-frame
# "Needs X" refresh doesn't clobber the "Add/Remove autodropper" hover tooltip
# (those caps aren't the main button, so _drop_*_hovered stays false on them).
var _drop_main_side_hovered: bool = false
var _drop_advanced_side_hovered: bool = false

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

# Player-placed deflectors. Key is peg_index(row, col); value is an
# Enums.Direction (+1 right / -1 left) the coin is forced toward at that peg.
# Owned here (the model); the DeflectorEditor child is a pure view+input node.
# Lives only in the BoardManager save blob — cleared on prestige reset.
var _deflectors: Dictionary = {}  # peg_index: int -> dir: int (Enums.Direction)
var _deflector_editor: DeflectorEditor

## Bucket indices whose vertical column has been destroyed by a bomb detonation.
## Cleared on build_board (matches the deflectors-survive-prestige-only pattern
## but for a per-challenge runtime concept). Read by Coin via
## is_lattice_cell_voided to drive fall-through; never persisted. PEGS REMAIN
## "purely visual" — coin behavior couples to *columns*, not to peg instances.
var _voided_columns: PackedInt32Array = PackedInt32Array()
## Radial voids carved by ForbiddenBucketHazard detonations. Each entry is
## `{cx, cy, radius}` in PlinkoBoard-local space. Independent of `_voided_columns`
## (different geometry — circle vs strict-vertical-strip); `is_lattice_cell_voided`
## unions both. Cleared in `clear_all_markings` and re-applied across rebuilds
## by `_reapply_voided_radii`, same lifecycle as `_voided_columns`.
var _voided_radii: Array[Dictionary] = []
## Bucket indices destroyed by ANY radial detonation. Populated synchronously
## in `detonate_radius` BEFORE the fall animation starts, so any coin still in
## flight during the (multi-second) fall sees the cell as voided and refuses
## to land. Survives rebuilds; cleared with `_voided_radii` in
## `clear_all_markings`. (Bomb-cut buckets are tracked separately via
## `_voided_columns` — their column-cut semantics already handle this.)
var _destroyed_bucket_indices: Dictionary = {}  # bucket_index: int -> true
## Set by BoardManager — returns total deflectors placed across ALL boards
## (the universal cap is global). Falls back to this board's own count when
## unset (bare unit tests).
var deflector_total_query: Callable

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
## Fires when a coin begins the final bounce that will FIRST earn a raw currency
## after a prestige — the moment the max-cap "+" buttons would silently appear.
## Like prestige_coin_landed this fires at final-bounce *start* (not landing),
## so CapRaiseRevealAnimator can borrow the camera before the coin touches down.
signal cap_raise_coin_landed(coin: Coin, predicted_bucket: Bucket)
## Final-bounce signal mirroring cap_raise_coin_landed, fired when the predicted
## bucket is marked forbidden. ForbiddenBucketRevealAnimator listens and softly
## zooms + slow-mos the camera before the doomed coin touches down.
signal forbidden_bucket_coin_landed(coin: Coin, predicted_bucket: Bucket)
## Requests that the next tier's board be unlocked. Fired on the SECOND board
## completion (the cap-raise reveal beat), replacing the old raw-currency-earned
## unlock path. BoardManager connects this to unlock_board.
signal next_board_unlock_requested(board_type: Enums.BoardType)

## Add-rows juice. `row_upgrade_starting` fires at the top of add_two_rows
## (before build_board) so BoardManager can suppress the default fit-tween
## that board_rebuilt would otherwise trigger; `row_upgrade_sweep_started`
## carries the sweep geometry so BoardManager can drive the zoom-in/track/
## settle camera. Signals up, calls down — PlinkoBoard never touches the
## camera. Naming pair matches the lifecycle: `_starting` (prepare,
## suppression flag) → `_sweep_started` (commit, with payload).
signal row_upgrade_starting
signal row_upgrade_sweep_started(start_local_x: float, end_local_x: float, focus_local_y: float, sweep_duration: float)

## Hazard signals. Signals up — listeners (AudioManager, ChallengeHUD, VFX
## layers) react without PlinkoBoard knowing about them. column_voided is the
## state transition (bucket becomes unreachable, pegs along the strict vertical
## are destroyed); bomb_* signals carry the bomb hazard lifecycle.
signal bomb_spawned(board_type: Enums.BoardType, bucket_index: int, seconds: float)
signal bomb_defused(board_type: Enums.BoardType, bucket_index: int, multiplier: float)
signal bomb_detonated(board_type: Enums.BoardType, bucket_index: int)
signal column_voided(board_type: Enums.BoardType, bucket_index: int)
signal forbidden_bucket_detonated(board_type: Enums.BoardType, bucket_index: int)

# Timestamps of recent drop bursts, used to rate-limit emissions to
# drop_burst_max_per_second. Only the last ~1 second of entries are kept.
var _drop_burst_times: Array[float] = []

# MultiMesh drop burst state
var _drop_burst_mm_instance: MultiMeshInstance3D
var _drop_burst_free_indices: Array[int] = []
var _active_drop_bursts: Array[Dictionary] = []

# Downward particle spray played when a coin lands in a bucket. Self-contained
# pooled node — created once, persists across rebuilds (like the MultiMeshes).
const _COIN_BURST_FIELD_SCENE := preload("res://entities/coin_burst_field/coin_burst_field.tscn")
var _coin_burst_field: CoinBurstField

## The coin armed for the cap-raise reveal — set when cap_raise_coin_landed is
## emitted, consumed once by finalize_coin_landing to swap the normal downward
## landing spray for the doubled 360° radial burst.
var _cap_raise_intro_coin: Coin = null

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
	vertical_spacing = Lattice.vertical_spacing(space_between_pegs)
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
	if UpgradeManager.upgrade_purchased.is_connected(_on_upgrade_purchased):
		UpgradeManager.upgrade_purchased.disconnect(_on_upgrade_purchased)


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
	# advanced_coin_multiplier is legacy (raw/advanced coins removed). Kept as a
	# plain base for force-dropped bonus coins; no longer boosted by challenges.
	advanced_coin_multiplier = 2.0
	multi_drop_count = PrestigeManager.get_multi_drop(board_type) + ChallengeProgressManager.get_bonus_multi_drop(board_type)
	_queue_rate_bonus_per_coin = _queue_rate_bonus_for_board(board_type)

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
	coin_queue.set_capacity(_queue_capacity_for_level(perm_queue))
	coin_queue.count_changed.connect(_on_queue_count_changed)
	drop_section.set_queue_bonus(coin_queue.count, _queue_rate_bonus_per_coin)
	LevelManager.rewards_claimed.connect(_on_rewards_claimed)
	LevelManager.reconcile_reward.connect(_on_reconcile_reward)
	CurrencyManager.currency_changed.connect(_on_currency_changed)

	# Deflector editor (pure view+input child; this board owns the model).
	_deflector_editor = preload("res://entities/deflector_editor/deflector_editor.tscn").instantiate()
	add_child(_deflector_editor)
	_deflector_editor.setup(self)
	_deflector_editor.deflector_change_requested.connect(_on_deflector_change_requested)
	_deflector_editor.set_capacity(get_deflector_cap())
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)


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
	_drop_main.update_text("Drop %s" % FormatUtils.currency_name(label_currency, false))
	_drop_main.main_pressed.connect(func(): request_drop())
	_drop_main.main_mouse_entered.connect(_on_drop_main_hover)
	_drop_main.main_mouse_exited.connect(_on_drop_main_hover_exit)
	_drop_main.side_button_hover.connect(_on_drop_side_hover.bind(_drop_main_tooltip))

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
	_no_room_label.text = "no\nauto\nroom"
	_no_room_label.font_size = 32
	if t.label_font:
		_no_room_label.font = t.label_font
	_no_room_label.modulate = t.normal_text_color
	_no_room_label.outline_size = 0
	_no_room_label.no_depth_test = true
	_no_room_label.line_spacing = -16
	_no_room_label.position = coin_queue.get_overflow_position() + Vector3(-0.2, 0, 0)
	add_child(_no_room_label)


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
	_drop_main_hovered = true
	# Hover always shows the regular cost tooltip, overriding any persistent
	# "Needs X" message until the mouse exits.
	_drop_main_tooltip.update_and_show("Cost: %s\nHotkey: SPACE" % _format_cost_text(_get_drop_costs()))


func _on_drop_advanced_hover() -> void:
	_drop_advanced.pulse_main(1.005)
	_drop_advanced_hovered = true
	_drop_advanced_tooltip.update_and_show("Cost: %s\nHotkey: B" % _format_cost_text(_get_advanced_drop_costs()))


func _on_drop_main_hover_exit() -> void:
	_drop_main_hovered = false
	_drop_main_tooltip.hide_tooltip()
	# Re-evaluate the persistent needs message after the hover ends.
	_refresh_needs_tooltips()


func _on_drop_advanced_hover_exit() -> void:
	_drop_advanced_hovered = false
	_drop_advanced_tooltip.hide_tooltip()
	_refresh_needs_tooltips()


## Side-button (autodropper +/-) hover. The tooltip is bound per drop column at
## connection time. Empty text means the hover ended — restore the "Needs X"
## messages instead of leaving the tooltip blank.
func _on_drop_side_hover(text: String, tooltip: Tooltip) -> void:
	var is_advanced := tooltip == _drop_advanced_tooltip
	if text.is_empty():
		if is_advanced:
			_drop_advanced_side_hovered = false
		else:
			_drop_main_side_hovered = false
		_refresh_needs_tooltips()
	else:
		if is_advanced:
			_drop_advanced_side_hovered = true
		else:
			_drop_main_side_hovered = true
		tooltip.update_and_show(text)


func _format_missing_cost_text(costs: Array) -> String:
	var parts: PackedStringArray = []
	for cost in costs:
		var balance: int = CurrencyManager.get_balance(cost[0])
		var missing: int = cost[1] - balance
		if missing > 0:
			parts.append("%s %s" % [FormatUtils.format_number(missing), FormatUtils.currency_name(cost[0], false)])
	return ", ".join(parts)


## Outcome of `_needs_tooltip_action` for one drop button's "Needs X" tooltip.
enum NeedsTooltipAction { SHOW, HIDE, KEEP }


## Decides what to do with a drop button's persistent "Needs X" tooltip.
## Cooldown is deliberately NOT a factor — if the player can't afford a drop the
## warning stays put steadily while the drop timer cycles (otherwise it flickers
## once per drop). KEEP means the button is hovered, so its hover handler owns
## the tooltip (showing cost) and the refresh must not clobber it.
func _needs_tooltip_action(affordable: bool, hovered: bool) -> NeedsTooltipAction:
	if hovered:
		return NeedsTooltipAction.KEEP
	return NeedsTooltipAction.HIDE if affordable else NeedsTooltipAction.SHOW


## Refreshes the persistent "Needs X" tooltip for both drop buttons. Each message
## is anchored above its own button; the advanced button is skipped until its
## column is visible.
func _refresh_needs_tooltips() -> void:
	_apply_needs_tooltip(_drop_main_tooltip, _get_drop_costs(), _drop_main_hovered or _drop_main_side_hovered)
	if _drop_advanced_column.visible:
		_apply_needs_tooltip(_drop_advanced_tooltip, _get_advanced_drop_costs(), _drop_advanced_hovered or _drop_advanced_side_hovered)


## Applies the computed action to a single drop button's "Needs X" tooltip.
func _apply_needs_tooltip(tooltip: Tooltip, costs: Array, hovered: bool) -> void:
	match _needs_tooltip_action(_can_afford(costs), hovered):
		NeedsTooltipAction.SHOW:
			tooltip.update_and_show_colored("Needs %s" % _format_missing_cost_text(costs), ThemeProvider.theme.red_main)
		NeedsTooltipAction.HIDE:
			tooltip.hide_tooltip()
		NeedsTooltipAction.KEEP:
			pass


func _process(delta: float) -> void:
	# TEMP: performance test — spam coins while holding spacebar
	if hack_space and Input.is_action_pressed("drop_coin") and drop_section.visible:
		for i in hack_burst:
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
		# Snap to peak, then elastic-out settle back to 1.0 — same jello feel
		# as MenuBoard's _wobble_peg, but driven by a manual delta loop instead
		# of a per-peg Tween (cheaper at scale; gameplay can have many pegs
		# pulsing simultaneously).
		var scale: float = lerpf(pulse_scale, 1.0, _elastic_out(t_ratio))
		var scaled_basis: Basis = _peg_basis.scaled(Vector3.ONE * scale)
		mm.set_instance_transform(idx, Transform3D(scaled_basis, _peg_positions[idx]))

		if t_ratio >= 1.0:
			finished.append(idx)

	for idx in finished:
		mm.set_instance_transform(idx, Transform3D(_peg_basis, _peg_positions[idx]))
		_active_peg_pulses.erase(idx)


## Elastic-out easing — equivalent to `Tween.TRANS_ELASTIC + EASE_OUT`. Pure
## static so the peg-pulse curve can be unit-tested without a scene tree.
static func _elastic_out(x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	return pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * (TAU / 3.0)) + 1.0


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
	return (Input.is_action_pressed("drop_coin") or _drop_main.is_held()) \
		and drop_section.visible


func _is_hold_to_drop_advanced_active() -> bool:
	return (Input.is_action_pressed("drop_unrefined") or _drop_advanced.is_held()) \
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
	var costs: Array = TierRegistry.get_drop_costs(board_type)
	# Apply any DROP_COST_REDUCTION challenge reward (flat per-drop discount on
	# this board's fuel cost). Floored at 1 so gold (already 1) is unaffected and
	# no drop is ever free. TierRegistry returns a fresh array, safe to mutate.
	var reduction: int = ChallengeProgressManager.get_drop_cost_reduction(board_type)
	if reduction > 0:
		for cost in costs:
			cost[1] = maxi(1, cost[1] - reduction)
	return costs


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


## "Coin frenzy" milestone reward: drops `count` coins one at a time (NOT all at
## once) at twice the multi-drop stagger, each with a guaranteed particle burst
## and a bell "pop" so the burst really lands. Used by DROP_COINS rewards.
const FRENZY_STAGGER := 0.25
## Frenzy never drops more than this many coins, even at high levels — keeps
## challenge frenzies (which scale with the level reached) from overpowering.
const FRENZY_MAX_COINS := 6

func _coin_frenzy_drop(coin_type: Enums.CurrencyType, count: int) -> void:
	for i in count:
		var tween := create_tween()
		tween.tween_interval(i * FRENZY_STAGGER)
		tween.tween_callback(_frenzy_drop_one.bind(coin_type, i))


func _frenzy_drop_one(coin_type: Enums.CurrencyType, step: int) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var frenzy_color: Color = t.frenzy_coin_color
	# Frenzy coins are tinted (upgrade-button color by default) so they read as
	# "from the milestone" — purely visual, no gameplay change.
	var coin: Coin = CoinScene.instantiate()
	coin.coin_type = coin_type
	coin.color_override = frenzy_color
	_launch_coin(coin)
	# Guaranteed per-coin burst in the frenzy color — bypasses _try_emit_drop_burst's
	# per-second rate limit so EVERY frenzy coin pops — plus a bell pop two octaves
	# up at 2/3 the volume of a bucket hit (amplitude, ≈ -3.5 dB below it).
	if t.drop_burst_enabled:
		_spawn_drop_burst_3d(Vector3(0, vertical_spacing + 0.2, 0), frenzy_color)
	# Theme-driven pop — `step` walks the chord progression so the frenzy
	# arpeggiates through all the chord roots (bell themes ignore it).
	AudioManager.play_frenzy_pop(step)


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


## Per-queued-coin drop-rate bonus for a board. The QUEUE_RATE_BONUS challenge
## reward is counted globally but applied to the gold board only (mirrors
## GOLD_COIN_SPEED_BOOST → Coin); other boards stay at the base bonus. Pure
## given ChallengeProgressManager state — tested via a bare board.
func _queue_rate_bonus_for_board(type: Enums.BoardType) -> float:
	if type != Enums.BoardType.GOLD:
		return QUEUE_RATE_BONUS_PER_COIN
	return QUEUE_RATE_BONUS_PER_COIN \
		+ ChallengeProgressManager.get_queue_rate_bonus_count() * QUEUE_RATE_BONUS_PER_UNLOCK


## Drop delay after applying the queue's rate bonus. Each queued coin (FULL or
## FILLING) adds _queue_rate_bonus_per_coin (base + earned QUEUE_RATE_BONUS
## challenge rewards, gold only) to the effective rate (rate = 1/delay), which
## is equivalent to dividing the delay by (1 + bonus * queue.count).
## Naturally bounded — delay shrinks but never reaches zero.
func get_effective_drop_delay() -> float:
	if coin_queue == null:
		return drop_delay
	var bonus_mult: float = 1.0 + _queue_rate_bonus_per_coin * float(coin_queue.count)
	return drop_delay / bonus_mult


func _on_queue_count_changed(_new_count: int) -> void:
	# Rescale the active drop timer proportionally so the player sees an
	# immediate speed-up/slow-down when the queue fills or drains, matching
	# the precedent in decrease_drop_delay().
	if is_waiting and _drop_timer_remaining > 0.0 and _last_effective_delay > 0.0:
		var new_effective: float = get_effective_drop_delay()
		_drop_timer_remaining *= new_effective / _last_effective_delay
		_last_effective_delay = new_effective
	drop_section.set_queue_bonus(coin_queue.count, _queue_rate_bonus_per_coin)


## Cached so we don't re-walk the viewport every frame. Refreshed on demand
## if it's freed (theme swap / scene reload).
var _cached_camera: Camera3D


## Lazily-refreshed active camera (shared with the queue-label projection so we
## don't re-walk the viewport). Used by the DeflectorEditor's hover raycast.
func get_active_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d()
	return _cached_camera


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
	# Advanced drop bar removed (single-currency model); the column stays hidden.
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

	_refresh_needs_tooltips()


func on_coin_landed(coin: Coin) -> void:
	var bucket = get_nearest_bucket(coin.global_position.x)
	finalize_coin_landing(coin, bucket)


## Completes the normal landing flow: adds currency, emits signal, cleans up coin.
## Prestige coins skip currency add and queue_free — the PrestigeAnimator handles them.
func finalize_coin_landing(coin: Coin, bucket: Bucket) -> void:
	# Safety net: if the board rebuilt between final_bounce_started and landing,
	# the predicted bucket may have been normal but the actual bucket is advanced.
	# Catch this and route through the prestige path (skips slow-mo, starts at freeze).
	if not coin.is_prestige_coin and _will_trigger_prestige_completion(coin, bucket):
		prestige_coin_landed.emit(coin, bucket)
		if coin.is_prestige_coin:
			return

	var t: VisualTheme = ThemeProvider.theme
	var bucket_idx := _get_bucket_index(bucket)
	var target_multiplier: float = 1.0
	if _gameplay_target_enabled and bucket_idx == _gameplay_target_index:
		target_multiplier = _golden_bucket_multiplier()
		_pick_new_gameplay_target()
	# Bomb defuse: mirrors the gameplay-target multiplier path. Runtime listens
	# for the subsequent coin_landed signal and clears the bomb visual.
	target_multiplier *= get_active_bomb_multiplier(bucket_idx)
	var amount: int = roundi(bucket.value * coin.multiplier * target_multiplier)
	var was_already_singing := bucket.is_singing()
	if not coin.is_prestige_coin:
		CurrencyManager.add(bucket.currency_type, amount)
		coin_landed.emit(board_type, bucket_idx, bucket.currency_type, amount, coin.multiplier)
	bucket.pulse()
	var num_buckets: int = buckets_container.get_child_count()
	var bucket_distance: int = absi(bucket_idx - num_buckets / 2)
	var is_advanced: bool = coin.coin_type == advanced_bucket_type
	# Suppress all bucket audio during the upgrade ripple — the ripple owns the arpeggio.
	# Repeat hits route to the lower-priority queue and play softer per concurrent
	# active drone for the bucket (see AudioManager.REPEAT_ATTENUATION_DB / CAP).
	# Visual singing is gated on the audio request being accepted so an inactive or
	# silenced board doesn't visually mark its buckets (would resurface via
	# _singing_positions on board switch-back).
	if not _upgrade_animating:
		var accepted: bool = AudioManager.request_bucket_play(board_type, bucket_idx, bucket_distance, is_advanced, was_already_singing)
		if accepted and not was_already_singing:
			bucket.mark_singing()
			_singing_positions[_bucket_position_key(bucket.position.x + buckets_container.position.x)] = true
	AudioManager.on_coin_landed()
	var effective_multiplier := coin.multiplier * target_multiplier
	var has_multiplier_text := effective_multiplier > 1.0 and not coin.is_prestige_coin
	if has_multiplier_text:
		_show_floating_text(coin.global_position, effective_multiplier, amount)
	if not coin.is_prestige_coin:
		# Downward burst in the coin's own color, then despawn. Prestige coins
		# skip both (PrestigeAnimator owns their lifecycle). The field gates
		# itself on theme.coin_burst_enabled + its own rate limit.
		if _coin_burst_field:
			if coin == _cap_raise_intro_coin:
				# Cap-raise reveal coin: no in-world spray at all. CapRaiseRevealAnimator
				# plays its own orange particle burst on the HUD overlay, which then
				# swoops up to the new cap buttons.
				_cap_raise_intro_coin = null
			else:
				_coin_burst_field.spawn(coin.global_position, t.get_coin_color(coin.coin_type))
		coin.queue_free()


## Called when a coin starts its final bounce and we can predict which bucket it will land in.
## If this landing would trigger a prestige, emit prestige_coin_landed so the animator can take over.
func _on_final_bounce_started(coin: Coin, predicted_bucket: Bucket) -> void:
	# Mutually exclusive beats, all keyed off "this coin completes the board"
	# (reaches 500 of the board's primary currency):
	#  - 1st completion (next board can still prestige) -> PRESTIGE.
	#  - 2nd completion (already prestiged, caps not yet revealed) -> unlock the
	#    next board + reveal cap "+" buttons.
	#  - forbidden landing is orthogonal (challenge bucket marking).
	if _will_trigger_prestige_completion(coin, predicted_bucket):
		prestige_coin_landed.emit(coin, predicted_bucket)
	elif _will_reveal_cap_raise_completion(coin, predicted_bucket):
		_cap_raise_intro_coin = coin
		# Enable caps BEFORE the animator queries pending targets (it reads
		# UpgradeManager.is_cap_raise_available). Then emit the reveal so the
		# animator can defer the new-board peek, THEN request the unlock.
		UpgradeManager.enable_cap_raise(board_type)
		cap_raise_coin_landed.emit(coin, predicted_bucket)
		var next := TierRegistry.get_next_tier(board_type)
		if next != null:
			next_board_unlock_requested.emit(next.board_type)
	elif _will_reveal_forbidden_landing(predicted_bucket):
		forbidden_bucket_coin_landed.emit(coin, predicted_bucket)


## Predicted currency gain for this coin landing in this bucket, mirroring the
## multiplier math in finalize_coin_landing but WITHOUT mutating state (no
## _pick_new_gameplay_target). Used to decide, at final-bounce start, whether the
## landing will cross the board-completion threshold.
func _predicted_bucket_gain(coin: Coin, bucket: Bucket) -> int:
	var bucket_idx := _get_bucket_index(bucket)
	var target_multiplier: float = 1.0
	if _gameplay_target_enabled and bucket_idx == _gameplay_target_index:
		target_multiplier = _golden_bucket_multiplier()
	target_multiplier *= get_active_bomb_multiplier(bucket_idx)
	return roundi(bucket.value * coin.multiplier * target_multiplier)


## The wandering golden-bucket payout multiplier: base 2.0 plus any
## GOLDEN_BUCKET_MULTIPLIER challenge rewards for this board.
func _golden_bucket_multiplier() -> float:
	return 2.0 + ChallengeProgressManager.get_golden_bucket_multiplier_bonus(board_type)


## True when THIS coin's landing will bring the board's primary currency from
## below 500 to >= 500 — i.e. the coin that "completes" the board. The 500 is the
## final level-bar threshold (LevelManager.TIER_THRESHOLDS[-1]). Balance is read
## pre-add (currency is credited later in finalize_coin_landing).
func _coin_completes_board(coin: Coin, predicted_bucket: Bucket) -> bool:
	if not is_instance_valid(predicted_bucket):
		return false
	var primary: Enums.CurrencyType = TierRegistry.primary_currency(board_type)
	if predicted_bucket.currency_type != primary:
		return false
	var threshold: int = LevelManager.TIER_THRESHOLDS[-1]
	var balance: int = CurrencyManager.get_balance(primary)
	if balance >= threshold:
		return false
	return balance + _predicted_bucket_gain(coin, predicted_bucket) >= threshold


## 1st board completion: fires the prestige sequence. Gated on the NEXT board
## still being prestige-able (can_prestige true => never prestiged). After the
## prestige claim this flips false, so the 2nd completion routes to the cap beat.
func _will_trigger_prestige_completion(coin: Coin, predicted_bucket: Bucket) -> bool:
	var next := TierRegistry.get_next_tier(board_type)
	if next == null:
		return false
	if not _coin_completes_board(coin, predicted_bucket):
		return false
	return PrestigeManager.can_prestige(next.board_type)


## 2nd board completion: unlocks the next board + reveals the cap "+" buttons.
## Gated on the next board already being prestiged (can_prestige false) AND this
## board's cap raises not yet available — making it one-shot per tier with no new
## persistent flag (UpgradeManager._cap_raise_available is already serialized).
func _will_reveal_cap_raise_completion(coin: Coin, predicted_bucket: Bucket) -> bool:
	if not ThemeProvider.theme.cap_raise_reveal_enabled:
		return false
	var next := TierRegistry.get_next_tier(board_type)
	if next == null:
		return false
	if not _coin_completes_board(coin, predicted_bucket):
		return false
	if PrestigeManager.can_prestige(next.board_type):
		return false
	return not UpgradeManager.is_cap_raise_available(board_type)


## True when this final bounce will land in a still-living forbidden bucket —
## the trigger for the ForbiddenBucketRevealAnimator zoom. The visible check
## makes the zoom one-shot per bucket-instance for free: once a forbidden bucket
## is detonated, the bucket is invisible (fell off), so a later coin routed
## toward its now-voided column won't re-trigger the zoom.
func _will_reveal_forbidden_landing(predicted_bucket: Bucket) -> bool:
	if not is_instance_valid(predicted_bucket) or not predicted_bucket.visible:
		return false
	var idx: int = _get_bucket_index(predicted_bucket)
	return _bucket_markings.get(idx, &"") == &"forbidden"


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


## Multiplier applied to coin_landed.amount when a coin lands in an active bomb
## bucket (defuse). Set by BombHazardRuntime via mark_bucket_bomb; cleared on
## unmark. Mirrors the gameplay-target multiplier path in finalize_coin_landing.
var _active_bomb_multipliers: Dictionary = {}  # bucket_index: int -> multiplier: float


func mark_bucket_bomb(index: int, defuse_multiplier: float = 1.0) -> void:
	_bucket_markings[index] = &"bomb"
	_active_bomb_multipliers[index] = defuse_multiplier
	var bucket := get_bucket(index)
	if bucket:
		bucket.mark_bomb()


func set_bomb_countdown(index: int, seconds_remaining: int) -> void:
	var bucket := get_bucket(index)
	if bucket:
		bucket.set_bomb_countdown(seconds_remaining)


func unmark_bucket_bomb(index: int) -> void:
	_bucket_markings.erase(index)
	_active_bomb_multipliers.erase(index)
	var bucket := get_bucket(index)
	if bucket:
		bucket.unmark_bomb()


func get_active_bomb_multiplier(bucket_index: int) -> float:
	return _active_bomb_multipliers.get(bucket_index, 1.0)


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
	# Bomb-hazard runtime state — wipe on challenge end so the next challenge
	# starts on a fresh, undamaged board.
	_voided_columns.clear()
	_voided_radii.clear()
	_destroyed_bucket_indices.clear()
	_active_bomb_multipliers.clear()


## Gameplay target: picks a new random bucket, avoiding the current one.
## Picker delegates to WanderingBucketSelector — shared with BombHazardRuntime
## so the "pick a wandering target, never the current one" rule has one home.
func _pick_new_gameplay_target() -> void:
	var num_buckets := buckets_container.get_child_count()
	if num_buckets <= 0:
		return
	# Clear old target
	if _gameplay_target_index >= 0 and _gameplay_target_index < num_buckets:
		var old_bucket := get_bucket(_gameplay_target_index)
		if old_bucket:
			old_bucket.stop_gameplay_target()
	var allowed: PackedInt32Array = PackedInt32Array()
	for i in num_buckets:
		allowed.append(i)
	var rng_fn: Callable = func(n: int) -> int: return randi() % maxi(1, n)
	_gameplay_target_index = WanderingBucketSelector.pick(allowed, _gameplay_target_index, rng_fn)
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


func _on_rewards_claimed(level: int, rewards: Array[RewardData]) -> void:
	for reward in rewards:
		if reward.type == RewardData.RewardType.DROP_COINS and reward.target_board == board_type:
			# Frenzy count scales with the level reached, capped so challenges
			# (which reach this reward at low levels) can't be overpowered.
			_coin_frenzy_drop(reward.coin_type, mini(level, FRENZY_MAX_COINS))
		elif reward.type == RewardData.RewardType.UNLOCK_UPGRADE and reward.board_type == board_type:
			if upgrade_allowed.is_valid() and not upgrade_allowed.call(reward.upgrade_type):
				# Upgrade is gated (challenges) — give a coin frenzy instead, so the
				# milestone still feels rewarding (scaling count + frenzy tint), the
				# same as a DROP_COINS milestone.
				_coin_frenzy_drop(TierRegistry.primary_currency(board_type), mini(level, FRENZY_MAX_COINS))
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
	# Single-currency model: advanced drops are removed. No-op so the column never
	# appears (including for old saves that recorded has_advanced_drop = true).
	return
	@warning_ignore("unreachable_code")
	if _has_advanced_drop:
		return
	_has_advanced_drop = true
	var t: VisualTheme = ThemeProvider.theme
	var adv_color: Color = t.get_coin_color(advanced_bucket_type)
	var adv_color_dark: Color = t.get_coin_color_faded(advanced_bucket_type)
	_drop_advanced.setup(adv_color, adv_color_dark)
	_drop_advanced.update_text("Drop %s" % FormatUtils.currency_name(advanced_bucket_type, false))
	_drop_advanced.main_pressed.connect(func(): request_drop(_get_advanced_drop_costs(), advanced_bucket_type))
	_drop_advanced.main_mouse_entered.connect(_on_drop_advanced_hover)
	_drop_advanced.main_mouse_exited.connect(_on_drop_advanced_hover_exit)
	_drop_advanced.side_button_hover.connect(_on_drop_side_hover.bind(_drop_advanced_tooltip))

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


# ---------------------------------------------------------------------------
# Lattice model + deflectors
#
# The board is a triangular Galton lattice. A coin's position is the integer
# cell (row, col): row 0 has one peg (col 0); row r has r+1 pegs (col 0..r).
# Moving RIGHT off (row, col) lands on (row+1, col+1); LEFT lands on (row+1,
# col). The geometry lives in the shared Lattice module; these methods are thin
# forwarders so build_board(), the Coin, and the decorative MenuBoard all go
# through the ONE mapping and can't drift against each other. (flash_nearest_peg
# is intentionally separate: it answers "nearest rendered peg to a mid-bounce
# position", a different question.)
# ---------------------------------------------------------------------------

## Y of a coin resting on a peg row, slightly above the peg centres. Matches the
## historical bounce arithmetic (coin spawns at vertical_spacing + 0.2, start()
## drops it to y = 0.2 = row 0, each bounce subtracts one vertical_spacing).
const COIN_ROW_Y_OFFSET := 0.2

enum ClickAction { IGNORE, PLACE, REMOVE }

## Outcome of a coin bouncing off a peg, w.r.t. any deflector placed there.
## NONE = no deflector at that peg; FOLLOWED = coin went the deflector's set
## way; MISSED = coin escaped against it. Drives the deflector reaction VFX.
## Named (not a ±1/0 int) so it never reads as an Enums.Direction.
enum DeflectorOutcome { NONE, FOLLOWED, MISSED }

## Deflector is a UNIVERSAL upgrade: its level (the global slot pool) is stored
## under one canonical board, and deflectors may be placed on ANY board's pegs.
const DEFLECTOR_BOARD := Enums.BoardType.ORANGE

## Local x of peg/coin lattice cell (row, col). Forwards to the shared Lattice
## module — build_board() uses this for every peg.
func position_x_for(row: int, col: int) -> float:
	return Lattice.x_for(row, col, space_between_pegs)


## Flat peg index for (row, col), matching build_board()'s row-major fill order
## (sum of pegs in the rows above, plus col). Used as the _deflectors key.
func peg_index(row: int, col: int) -> int:
	@warning_ignore("integer_division")
	return row * (row + 1) / 2 + col


## Local-space target a coin tweens to when it reaches lattice cell (row, col).
## Z is left at 0 — the coin keeps its own render-order z (only x/y are tweened).
## vertical_spacing/COIN_ROW_Y_OFFSET are passed in (not recomputed) so a manual
## vertical_spacing override stays exact.
func cell_to_world(row: int, col: int) -> Vector3:
	return Lattice.cell_to_world(row, col, space_between_pegs, vertical_spacing, COIN_ROW_Y_OFFSET)


## Pure integer lattice transition. direction is an Enums.Direction (+1 right).
func next_lattice_cell(row: int, col: int, direction: int) -> Vector2i:
	return Lattice.next_cell(row, col, direction)


# ── Voided columns (bomb-hazard "saw-off-the-limb" fallout) ───────
# Vocabulary used throughout this section:
#   • detonate — the event (BombHazardRuntime calls void_column)
#   • void     — the state (`_voided_columns`, `is_column_voided`, `column_voided`)
#   • cut      — the geometry (`cell_in_cut`, `peg_indices_on_cut`, `bomb_cut_side`)
#
# When a bomb detonates at bucket B, the cut runs from the bomb through the
# nearer board edge: every bucket and peg with world-x on that side of B
# (including B's own column) falls away. CENTER bombs (only on odd-bucket-
# count boards) take the whole board down. The surviving buckets are always
# a contiguous range bounded by the cuts from previous detonations.
#
# State lives in `_voided_columns` (PackedInt32Array of voided bucket indices).
# Voids persist across build_board() rebuilds (e.g. add_two_rows mid-challenge)
# — only `clear_all_markings` resets them, which the tracker calls on challenge
# end.

## Return values of `bomb_cut_side` — named so callers branching on the
## result aren't reading raw -1 / 0 / +1 ints.
const CUT_LEFT := -1
const CUT_CENTER := 0
const CUT_RIGHT := 1

## Pure: which side of the board bucket B sits on. Returns CUT_LEFT (-1),
## CUT_RIGHT (+1), or CUT_CENTER (0) — see the named constants above. A
## CUT_CENTER detonation (only possible on odd-bucket-count boards) takes
## down the entire board rather than cleaving one side.
static func bomb_cut_side(bucket_index: int, num_buckets: int) -> int:
	@warning_ignore("integer_division")
	if num_buckets % 2 == 1 and bucket_index == (num_buckets - 1) / 2:
		return CUT_CENTER
	return CUT_LEFT if bucket_index * 2 < num_buckets - 1 else CUT_RIGHT


## Pure: bucket-index normalised position (x in `space` units) — independent of
## space_between_pegs so the saw-side math stays integer-exact.
static func _bucket_x_norm(bucket_index: int, num_rows_param: int) -> float:
	return float(bucket_index) - num_rows_param * 0.5


## Pure: cell-index normalised position. Cells share the same normalisation as
## buckets so cell-vs-cut comparisons are exact integer/half-integer math.
static func _cell_x_norm(row: int, col: int) -> float:
	return float(col) - row * 0.5


## Pure: is cell (row, col) inside the cut from a bomb at `bucket_index` on
## `side` (CUT_LEFT/CUT_RIGHT/CUT_CENTER)? "Inside" is inclusive of the
## strict column for the off-centre sides; CUT_CENTER engulfs the whole
## board.
static func cell_in_cut(row: int, col: int, bucket_index: int, num_rows_param: int, side: int) -> bool:
	if side == CUT_CENTER:
		return true
	var cell_x: float = _cell_x_norm(row, col)
	var bucket_x: float = _bucket_x_norm(bucket_index, num_rows_param)
	if side == CUT_LEFT:
		return cell_x <= bucket_x
	return cell_x >= bucket_x


## Pure: is cell (row, col) destroyed by ANY of `voided_columns`? Each voided
## bucket implies a cut to its nearer edge — the cell is destroyed if it lies
## inside any of those cuts.
static func should_fall_through(row: int, col: int, voided_columns: PackedInt32Array, num_rows_param: int) -> bool:
	var num_buckets: int = num_rows_param + 1
	for B in voided_columns:
		var side: int = bomb_cut_side(B, num_buckets)
		if cell_in_cut(row, col, B, num_rows_param, side):
			return true
	return false


## Pure: flat peg indices in row-major order that get destroyed when bucket
## `bucket_index` is detonated. With saw-off semantics, that's every peg whose
## world-x is on the cut side of (or equal to) bucket_index's x.
static func peg_indices_on_cut(bucket_index: int, num_rows_param: int) -> PackedInt32Array:
	var num_buckets: int = num_rows_param + 1
	var side: int = bomb_cut_side(bucket_index, num_buckets)
	var out: PackedInt32Array = PackedInt32Array()
	for row in num_rows_param:
		for col in row + 1:
			if cell_in_cut(row, col, bucket_index, num_rows_param, side):
				@warning_ignore("integer_division")
				out.append(row * (row + 1) / 2 + col)
	return out


## Pure: bucket indices voided by detonating `bucket_index`. With saw-off
## semantics: B itself plus every bucket on the cut side (out to the edge).
## Centre detonations take down every bucket on the board.
static func buckets_on_cut(bucket_index: int, num_rows_param: int) -> PackedInt32Array:
	var num_buckets: int = num_rows_param + 1
	var side: int = bomb_cut_side(bucket_index, num_buckets)
	var out: PackedInt32Array = PackedInt32Array()
	if side == CUT_CENTER:
		for B in num_buckets:
			out.append(B)
	elif side == CUT_LEFT:
		for B in bucket_index + 1:
			out.append(B)
	else:
		for B in range(bucket_index, num_buckets):
			out.append(B)
	return out


func is_column_voided(bucket_index: int) -> bool:
	return _voided_columns.has(bucket_index)


## True at any lattice cell destroyed by a bomb cut OR a forbidden-bucket radial
## detonation. Called by Coin at every bounce step — coins in voided cells
## switch to the straight-fall + despawn path (see `_begin_void_fall`).
func is_lattice_cell_voided(row: int, col: int) -> bool:
	if should_fall_through(row, col, _voided_columns, num_rows):
		return true
	# Bucket row: an explicit "this bucket was destroyed" set is the
	# authoritative answer. Synchronously populated by `detonate_radius`
	# BEFORE the fall animation starts, so coins in flight during the
	# multi-second fall see the cell as voided immediately rather than landing
	# in a falling-but-still-scoring bucket. Avoids both the y-offset
	# boundary case AND the mid-fall position confusion.
	if row >= num_rows:
		if _destroyed_bucket_indices.has(col):
			return true
	if _voided_radii.is_empty():
		return false
	# Peg rows: use the lattice cell position — pegs are lattice-aligned, so
	# the radius check is exact.
	var cell_pos: Vector3 = cell_to_world(row, col)
	for entry: Dictionary in _voided_radii:
		var dx: float = cell_pos.x - entry["cx"]
		var dy: float = cell_pos.y - entry["cy"]
		var r: float = entry["radius"]
		if dx * dx + dy * dy <= r * r:
			return true
	return false


## All bucket indices not voided. Survives geometric ordering — for a saw-off
## board this is the contiguous unsawn middle. Bomb hazards target a tighter
## subset (see get_targetable_bucket_indices).
func get_reachable_bucket_indices() -> PackedInt32Array:
	var num_buckets: int = num_rows + 1
	var out: PackedInt32Array = PackedInt32Array()
	for i in num_buckets:
		if not is_column_voided(i):
			out.append(i)
	return out


## Buckets that are valid bomb targets: in the surviving range AND interior
## (skip the leftmost + rightmost — they're board edges with no pegs above,
## detonating them would do nothing). Mirrors the "never spawn a bomb where it
## can't do damage" rule.
func get_targetable_bucket_indices() -> PackedInt32Array:
	var reachable: PackedInt32Array = get_reachable_bucket_indices()
	if reachable.size() <= 2:
		# Only edges (or fewer) survive — nothing for a bomb to chew on.
		return PackedInt32Array()
	var out: PackedInt32Array = PackedInt32Array()
	for i in range(1, reachable.size() - 1):
		out.append(reachable[i])
	return out


## Detonate bucket `bucket_index`: saw off everything on the cut side. Voids
## buckets, destroys pegs, animates the falling limb, vaporises in-flight coins
## inside the blast, plays the dragon explosion sound. Idempotent — if the
## bucket was already voided we no-op (avoids double-cuts if multiple bombs
## end up resolving at the same target across one frame).
func void_column(bucket_index: int) -> void:
	if is_column_voided(bucket_index):
		return
	var num_buckets: int = num_rows + 1
	var side: int = bomb_cut_side(bucket_index, num_buckets)
	var newly_voided_buckets: PackedInt32Array = buckets_on_cut(bucket_index, num_rows)
	# Filter out any that were already voided (re-detonating into a more-inside
	# bucket re-cuts a wider area but doesn't re-process the already-fallen
	# half).
	var truly_new: PackedInt32Array = PackedInt32Array()
	for B in newly_voided_buckets:
		if not is_column_voided(B):
			_voided_columns.append(B)
			truly_new.append(B)
	if truly_new.is_empty():
		return

	# Visuals + audio + coin clearing happen on the saw-line geometry, not just
	# on the bomb bucket — the limb falls as a single piece.
	var peg_indices: PackedInt32Array = peg_indices_on_cut(bucket_index, num_rows)
	_animate_falling_pegs(peg_indices)
	_hide_pegs(peg_indices)
	_animate_falling_buckets(truly_new)
	_vaporise_coins_in_cut(bucket_index, side)
	_play_column_detonation_vfx(bucket_index)
	AudioManager.play_bomb_detonation(board_type)

	column_voided.emit(board_type, bucket_index)


func _animate_falling_pegs(indices: PackedInt32Array) -> void:
	if not _peg_multimesh_instance or indices.is_empty():
		return
	var t: VisualTheme = ThemeProvider.theme
	# Spawn one MeshInstance3D per peg as a falling debris copy. The originals
	# are scale-zeroed in the MM (next call) so we don't double-render. The
	# shader material is shared across all debris this detonation — peg colour
	# is uniform, no per-instance tinting needed; freed via RefCounted when
	# the last MeshInstance3D drops it.
	var peg_mesh: Mesh = t.make_peg_mesh()
	var peg_mat: ShaderMaterial = t.make_peg_shader_material()
	var fall_distance: float = vertical_spacing * (num_rows + 3) + space_between_pegs * 2.0
	var fall_duration: float = t.bomb_debris_fall_duration
	for flat_idx in indices:
		if flat_idx < 0 or flat_idx >= _peg_positions.size():
			continue
		var debris := MeshInstance3D.new()
		debris.mesh = peg_mesh
		debris.material_override = peg_mat
		debris.transform = Transform3D(_peg_basis, _peg_positions[flat_idx])
		add_child(debris)
		var spin: float = randf_range(-PI * 1.5, PI * 1.5)
		var drift_x: float = randf_range(-0.35, 0.35)
		var target_pos: Vector3 = debris.position + Vector3(drift_x, -fall_distance, 0)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.bind_node(debris)
		tween.tween_property(debris, "position", target_pos, fall_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(debris, "rotation:z", debris.rotation.z + spin, fall_duration)
		tween.chain().tween_callback(debris.queue_free)
	_spawn_destruction_particles(indices)


func _animate_falling_buckets(bucket_indices: PackedInt32Array) -> void:
	# Bare-instance safety: tests instantiate PlinkoBoard.new() without the
	# scene tree, so buckets_container is null and get_bucket would crash.
	if not buckets_container:
		return
	var t: VisualTheme = ThemeProvider.theme
	var fall_distance: float = vertical_spacing * (num_rows + 3) + space_between_pegs * 2.0
	var fall_duration: float = t.bomb_debris_fall_duration
	for B in bucket_indices:
		var bucket := get_bucket(B)
		if not bucket:
			continue
		var start_pos: Vector3 = bucket.position
		var spin: float = randf_range(-PI * 1.0, PI * 1.0)
		var drift_x: float = randf_range(-0.25, 0.25)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.bind_node(bucket)
		tween.tween_property(bucket, "position",
			start_pos + Vector3(drift_x, -fall_distance, 0), fall_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(bucket, "rotation:z",
			bucket.rotation.z + spin, fall_duration)
		# After the fall, set invisible — bucket stays in the tree so
		# get_bucket(idx) keeps its index valid; child count doesn't shift.
		tween.chain().tween_callback(func() -> void:
			if is_instance_valid(bucket):
				bucket.visible = false
		)


## Spawn a radial particle burst at each destroyed peg. Reuses CoinBurstField's
## spawn API — fire-and-forget pooled particles already battle-tested for the
## landing burst.
func _spawn_destruction_particles(indices: PackedInt32Array) -> void:
	if not _coin_burst_field:
		return
	var t: VisualTheme = ThemeProvider.theme
	for flat_idx in indices:
		if flat_idx < 0 or flat_idx >= _peg_positions.size():
			continue
		# Several bursts per peg so the explosion reads as big.
		var world_pos: Vector3 = to_global(_peg_positions[flat_idx])
		for _i in 3:
			_coin_burst_field.spawn(world_pos, t.bomb_detonation_color)


## Bright column-of-light flash at the bomb's strict column (centred on the
## bomb bucket's x). Cheap, expressive, fades over `bomb_detonation_pulse_duration`.
func _play_column_detonation_vfx(bucket_index: int) -> void:
	if not is_node_ready():
		return
	var t: VisualTheme = ThemeProvider.theme
	var bucket_x: float = position_x_for(num_rows, bucket_index)
	var column_height: float = vertical_spacing * num_rows + COIN_ROW_Y_OFFSET + space_between_pegs
	var box := BoxMesh.new()
	box.size = Vector3(t.void_column_light_width, column_height, 0.05)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = t.bomb_detonation_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	mi.position = Vector3(bucket_x, -vertical_spacing * num_rows * 0.5, -0.1)
	add_child(mi)
	var tween := create_tween()
	tween.bind_node(mi)
	tween.tween_property(mat, "albedo_color:a", 0.0, t.bomb_detonation_pulse_duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(mi.queue_free)


## Any in-flight coin whose current lattice cell sits inside the cut from a
## detonation at `bomb_index` (cut side `side`) gets queue_freed. Fires a small
## particle puff at the coin's position so the vaporisation reads visually.
func _vaporise_coins_in_cut(bomb_index: int, side: int) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var to_free: Array[Coin] = []
	for coin: Coin in _active_coin_indices.keys():
		if not is_instance_valid(coin):
			continue
		if cell_in_cut(coin._row, coin._col, bomb_index, num_rows, side):
			to_free.append(coin)
	for coin in to_free:
		if _coin_burst_field:
			_coin_burst_field.spawn(coin.global_position, t.bomb_detonation_color)
		coin.kill_tweens()
		coin.queue_free()


func _hide_pegs(indices: PackedInt32Array) -> void:
	if not _peg_multimesh_instance:
		return
	var mm: MultiMesh = _peg_multimesh_instance.multimesh
	var hidden_basis: Basis = _peg_basis.scaled(Vector3.ZERO)
	for flat_idx in indices:
		if flat_idx < 0 or flat_idx >= _peg_positions.size():
			continue
		# Clear any flash / pulse claims on this index so per-frame loops don't
		# write the transform back to a non-zero scale. Without this, a peg
		# being detonated mid-bounce-flash visually stays around for the pulse
		# duration.
		_active_flashes.erase(flat_idx)
		_active_peg_pulses.erase(flat_idx)
		mm.set_instance_transform(flat_idx,
			Transform3D(hidden_basis, _peg_positions[flat_idx]))


## Re-applies peg hiding for every voided column after a board rebuild. Called
## from build_board at the end so voids persist across add_two_rows (and any
## other mid-challenge rebuild like the advanced-bucket reward).
##
## Uses the same `should_fall_through` predicate that Coin queries at bounce
## time, so the visual hide-set is guaranteed to match the gameplay cut-set —
## no chance of pegs visible in cells that would fall a coin through, or vice
## versa. Handles LEFT / RIGHT / CENTER cuts uniformly.
func _reapply_voided_pegs() -> void:
	if _voided_columns.is_empty():
		return
	if not buckets_container:
		return  # bare-instance test path: no buckets to hide, no MM to update
	var hide: PackedInt32Array = PackedInt32Array()
	for row in num_rows:
		for col in row + 1:
			if should_fall_through(row, col, _voided_columns, num_rows):
				@warning_ignore("integer_division")
				hide.append(row * (row + 1) / 2 + col)
	_hide_pegs(hide)
	# Hide any buckets that should be voided — for the post-rebuild state, just
	# set visible=false. (Animation only fires on the live detonation path.)
	for B in _voided_columns:
		var bucket := get_bucket(B)
		if bucket:
			bucket.visible = false


## Detonate a circular blast centered on bucket `bucket_index`. Destroys every
## peg + bucket inside `radius`, vaporises in-flight coins inside the blast,
## adds the circle to `_voided_radii` so future coin paths fall through it, and
## plays the bomb detonation SFX. Idempotent on the bucket: if the bucket is
## already gone (re-call), no new peg/bucket animations fire because the
## already-hidden filter rejects them, and the new radius entry is harmless.
##
## Pure VFX + voided-cell carve-out — does NOT end the challenge (that's the
## hazard runtime's old behavior; we deliberately keep playing).
func detonate_radius(bucket_index: int, radius: float) -> void:
	if radius <= 0.0 or not buckets_container:
		return
	var center_bucket := get_bucket(bucket_index)
	if not center_bucket:
		return
	var b_offset: Vector3 = buckets_container.position
	var center: Vector2 = Vector2(
		b_offset.x + center_bucket.position.x,
		b_offset.y + center_bucket.position.y)
	var r2: float = radius * radius
	var peg_indices: PackedInt32Array = PackedInt32Array()
	for i in _peg_positions.size():
		var p: Vector3 = _peg_positions[i]
		var dx: float = p.x - center.x
		var dy: float = p.y - center.y
		if dx * dx + dy * dy <= r2:
			peg_indices.append(i)
	var bucket_indices: PackedInt32Array = PackedInt32Array()
	var num_buckets: int = buckets_container.get_child_count()
	for i in num_buckets:
		var b := get_bucket(i)
		if not b or not b.visible:
			continue
		var bx: float = b_offset.x + b.position.x - center.x
		var by: float = b_offset.y + b.position.y - center.y
		if bx * bx + by * by <= r2:
			bucket_indices.append(i)
	# Register voids BEFORE animating so any same-frame coin step sees them.
	# _destroyed_bucket_indices is the authoritative "this bucket no longer
	# scores" set — synchronously true the instant the fall starts, even though
	# the bucket's `visible` flag doesn't flip until ~1.5s later when the fall
	# tween completes. `is_lattice_cell_voided` checks this for the bucket row
	# so in-flight coins targeting a falling bucket switch to void_fall.
	_voided_radii.append({"cx": center.x, "cy": center.y, "radius": radius})
	for i in bucket_indices:
		_destroyed_bucket_indices[i] = true
	if not peg_indices.is_empty():
		_animate_falling_pegs(peg_indices)
		_hide_pegs(peg_indices)
	if not bucket_indices.is_empty():
		_animate_falling_buckets(bucket_indices)
	_vaporise_coins_in_radius(center, radius)
	AudioManager.play_bomb_detonation(board_type)
	forbidden_bucket_detonated.emit(board_type, bucket_index)


## Any in-flight coin whose lattice cell sits inside the radial blast is
## queue_freed. Mirrors `_vaporise_coins_in_cut` but uses Euclidean distance
## from `center` against the coin's lattice cell position.
func _vaporise_coins_in_radius(center: Vector2, radius: float) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var r2: float = radius * radius
	var to_free: Array[Coin] = []
	for coin: Coin in _active_coin_indices.keys():
		if not is_instance_valid(coin):
			continue
		var cp: Vector3 = cell_to_world(coin._row, coin._col)
		var dx: float = cp.x - center.x
		var dy: float = cp.y - center.y
		if dx * dx + dy * dy <= r2:
			to_free.append(coin)
	for coin in to_free:
		if _coin_burst_field:
			_coin_burst_field.spawn(coin.global_position, t.bomb_detonation_color)
		coin.kill_tweens()
		coin.queue_free()


## Re-apply radial voids after a board rebuild. Mirrors `_reapply_voided_pegs`
## but unions against the same lattice predicate `is_lattice_cell_voided`
## already does — so the visible peg set matches what Coin sees at runtime.
func _reapply_voided_radii() -> void:
	if _voided_radii.is_empty():
		return
	if not buckets_container:
		return
	var hide: PackedInt32Array = PackedInt32Array()
	var r2_list: Array[float] = []
	for entry: Dictionary in _voided_radii:
		var r: float = entry["radius"]
		r2_list.append(r * r)
	for i in _peg_positions.size():
		var p: Vector3 = _peg_positions[i]
		for j in _voided_radii.size():
			var entry: Dictionary = _voided_radii[j]
			var dx: float = p.x - entry["cx"]
			var dy: float = p.y - entry["cy"]
			if dx * dx + dy * dy <= r2_list[j]:
				hide.append(i)
				break
	_hide_pegs(hide)
	# Hide buckets whose centres fall in any radius — post-rebuild snap, no fall.
	var b_offset: Vector3 = buckets_container.position
	var num_buckets: int = buckets_container.get_child_count()
	for i in num_buckets:
		var b := get_bucket(i)
		if not b:
			continue
		var bx: float = b_offset.x + b.position.x
		var by: float = b_offset.y + b.position.y
		for j in _voided_radii.size():
			var entry: Dictionary = _voided_radii[j]
			var dx2: float = bx - entry["cx"]
			var dy2: float = by - entry["cy"]
			if dx2 * dx2 + dy2 * dy2 <= r2_list[j]:
				b.visible = false
				break


## True once the coin has fallen past the last peg row into the bucket row.
## There are `num_rows` peg rows (0 .. num_rows - 1).
func is_terminal_cell(row: int, _col: int) -> bool:
	return row >= num_rows


## At the terminal row the column maps 1:1 onto the bucket child index
## (num_buckets == num_rows + 1, col in 0 .. num_rows).
func predicted_bucket_index(_row: int, col: int) -> int:
	return col


## Base deflector strength. Strength s biases a deflected peg toward its
## chosen direction with probability (s+1)/(s+2): s=5 → 6/7 (1 in 7 still go
## the other way — a 1:6 split), s=6 → 7/8, … asymptotic to but never 100%
## (deflectors *encourage*, they don't *force*). Higher strength is intended
## to come from challenge rewards later (board-agnostic, like the slot pool).
const DEFLECTOR_BASE_STRENGTH := 5


## Single source of truth for strength → bias. Static so UI (the upgrade row's
## "current odds") can read it without a board instance.
static func deflector_bias_for_strength(s: int) -> float:
	return float(s + 1) / float(s + 2)


func get_deflector_strength() -> int:
	return DEFLECTOR_BASE_STRENGTH


## Probability a deflected coin actually follows its deflector's direction.
func _deflector_bias() -> float:
	return deflector_bias_for_strength(get_deflector_strength())


## Legacy 50/50 pick — bit-identical to the old `1 if randf() < 0.5 else -1`.
func _random_dir(roll: float) -> int:
	return Enums.Direction.RIGHT if roll < 0.5 else Enums.Direction.LEFT


## The direction a coin leaves peg (row, col): a deflector *encourages* its
## direction (followed with probability _deflector_bias(), else the opposite);
## otherwise `roll` gives the legacy 50/50 pick. Bit-identical to the old
## `1 if randf() < 0.5 else -1` when no deflector is present.
func resolve_bounce_direction(row: int, col: int, roll: float) -> int:
	if _deflectors.is_empty():
		return _random_dir(roll)
	var idx := peg_index(row, col)
	if _deflectors.has(idx):
		var d: int = _deflectors[idx]
		return d if roll < _deflector_bias() else -d
	return _random_dir(roll)


## Did the coin follow or fight the deflector at cell (row, col)? Pure query —
## reads _deflectors only, no RNG, no side effects. `direction` is the already
## resolved bounce direction (an Enums.Direction); this just compares it to the
## stored deflector dir, so resolve_bounce_direction stays bit-identical and the
## trajectory tests are unaffected. NONE when this peg has no deflector.
func deflector_outcome(row: int, col: int, direction: int) -> DeflectorOutcome:
	if _deflectors.is_empty():
		return DeflectorOutcome.NONE
	var idx := peg_index(row, col)
	if not _deflectors.has(idx):
		return DeflectorOutcome.NONE
	return DeflectorOutcome.FOLLOWED if _deflectors[idx] == direction \
		else DeflectorOutcome.MISSED


## Event hook (called DOWN by Coin alongside flash_nearest_peg, before its cell
## reassignment): the coin's deflector interaction at (row, col) is decided —
## drive the reaction VFX. Fire-and-forget and a safe no-op when no deflector
## editor exists (bare test boards) or this peg has no deflector. Pure view:
## never mutates _deflectors and never saves.
func notify_deflector_resolved(row: int, col: int, direction: int) -> void:
	if not _deflector_editor:
		return
	var idx := peg_index(row, col)
	match deflector_outcome(row, col, direction):
		DeflectorOutcome.FOLLOWED:
			_deflector_editor.play_deflector_hit(idx)
		DeflectorOutcome.MISSED:
			_deflector_editor.play_deflector_miss(idx)


## Global slot count = the player's Deflector upgrade level (stored under the
## canonical board; the upgrade is universal so this is board-agnostic).
func get_deflector_cap() -> int:
	return UpgradeManager.get_level(DEFLECTOR_BOARD, Enums.UpgradeType.PEG_DEFLECTOR) \
		+ PrestigeManager.get_permanent_deflector_count()


func deflector_count() -> int:
	return _deflectors.size()


## Total deflectors placed across every board (BoardManager-provided), or this
## board's own count when the query is unset (bare tests / single board).
func _global_deflectors_placed() -> int:
	if deflector_total_query.is_valid():
		return deflector_total_query.call()
	return _deflectors.size()


func has_deflector(peg_idx: int) -> bool:
	return _deflectors.has(peg_idx)


func get_deflector_keys() -> Array:
	return _deflectors.keys()


func get_deflector_dir(peg_idx: int) -> int:
	return _deflectors.get(peg_idx, 0)


## Place (or re-aim) a deflector. Rejected only when it would exceed the slot
## cap (re-aiming an existing peg never consumes a new slot).
func place_deflector(peg_idx: int, dir: int) -> bool:
	if not _deflectors.has(peg_idx) and _global_deflectors_placed() >= get_deflector_cap():
		return false
	_deflectors[peg_idx] = dir
	return true


func remove_deflector(peg_idx: int) -> void:
	_deflectors.erase(peg_idx)


## Pure click→intent decision (testable without the editor/raycast).
func resolve_click_action(peg_idx: int) -> int:
	if _deflectors.has(peg_idx):
		return ClickAction.REMOVE
	if _global_deflectors_placed() < get_deflector_cap():
		return ClickAction.PLACE
	return ClickAction.IGNORE


func serialize_deflectors() -> Array:
	var out: Array = []
	for idx in _deflectors:
		out.append({"peg": idx, "dir": _deflectors[idx]})
	return out


## Pure restore — drops entries off the current grid or beyond the slot cap.
## Safe to call on a bare board (does NOT touch build_board / scene nodes).
func restore_deflectors(raw: Array) -> void:
	_deflectors.clear()
	@warning_ignore("integer_division")
	var total_pegs: int = num_rows * (num_rows + 1) / 2
	var cap: int = get_deflector_cap()
	for entry in raw:
		if not (entry is Dictionary):
			continue
		var idx: int = int(entry.get("peg", -1))
		var dir: int = int(entry.get("dir", 0))
		if idx < 0 or idx >= total_pegs:
			continue
		if dir != Enums.Direction.LEFT and dir != Enums.Direction.RIGHT:
			continue
		# Global cap (boards restore sequentially; deflector_total_query already
		# wired) — same invariant place_deflector/resolve_click_action enforce.
		if _global_deflectors_placed() >= cap:
			break
		_deflectors[idx] = dir


## Editor → board intent (signals up, calls down). dir 0 removes; ±1 places.
func _on_deflector_change_requested(peg_index: int, dir: int) -> void:
	if dir == 0:
		remove_deflector(peg_index)
	else:
		if place_deflector(peg_index, dir) and not OnboardingProgress.has_placed_deflector():
			# First-ever placement — stops the discoverability pulse everywhere.
			OnboardingProgress.mark_deflector_placed()
	if _deflector_editor:
		_deflector_editor.refresh()
	SaveManager.save_game()


## Auto-place a deflector on this board's first peg (the apex, row 0 col 0).
## Used once by the orange-prestige reward seeding; no-op if one is already
## there. The player can then move or remove it like any other.
func seed_first_peg_deflector(dir: int = Enums.Direction.RIGHT) -> void:
	var idx := peg_index(0, 0)
	if has_deflector(idx):
		return
	place_deflector(idx, dir)
	if _deflector_editor:
		_deflector_editor.refresh()


## Editor enable forwarding (BoardManager / Main call these — they don't poke
## the private editor directly).
func set_deflector_input_active(active: bool) -> void:
	if _deflector_editor:
		_deflector_editor.set_active(active)


func set_deflector_input_allowed(allowed: bool) -> void:
	if _deflector_editor:
		_deflector_editor.set_input_allowed(allowed)


func _on_upgrade_purchased(upgrade_type: Enums.UpgradeType, _p_board_type: Enums.BoardType, _new_level: int) -> void:
	# Universal upgrade — every board's editor reflects the global cap,
	# regardless of which board the purchase was booked under.
	if upgrade_type == Enums.UpgradeType.PEG_DEFLECTOR:
		if _deflector_editor:
			_deflector_editor.set_capacity(get_deflector_cap())


## Palette source the pegs use — so the deflector remove-X (a TintedIcon)
## resolves to the same neutral peg color and survives theme swaps.
func get_peg_palette_source() -> VisualTheme.Palette:
	return ThemeProvider.theme.peg_color_source


func get_peg_local_position(idx: int) -> Vector3:
	if idx < 0 or idx >= _peg_positions.size():
		return Vector3.ZERO
	return _peg_positions[idx]


## A roughly-central peg (mid row, mid column) — the sparkle/pulse target.
func get_center_peg_index() -> int:
	@warning_ignore("integer_division")
	var row: int = num_rows / 2
	@warning_ignore("integer_division")
	var col: int = clampi(row / 2, 0, row)
	return peg_index(row, col)


func get_center_peg_screen_position() -> Vector2:
	var cam := get_active_camera()
	if cam == null or _peg_positions.is_empty():
		return Vector2.ZERO
	return cam.unproject_position(
		to_global(get_peg_local_position(get_center_peg_index())))


## Called by the intro animator (via the orange board) once the sparkles land:
## start the pulsing center-peg hint until the player places their first one.
func start_deflector_center_hint() -> void:
	if _deflector_editor:
		_deflector_editor.start_center_peg_hint(get_center_peg_index())


## Flat index of the peg nearest a board-local point, or -1 if none within
## max_dist. Scans the authoritative _peg_positions array (same kind of lookup
## as flash_nearest_peg) — used by the DeflectorEditor for hover/click, never
## on the coin hot path.
func nearest_peg_index_to_local(local_pos: Vector3, max_dist: float) -> int:
	var best := -1
	var best_dist := max_dist
	for i in _peg_positions.size():
		var d := local_pos.distance_to(_peg_positions[i])
		if d < best_dist:
			best_dist = d
			best = i
	return best


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
	# Voided columns are per-challenge runtime state and PERSIST across rebuilds
	# (add_two_rows mid-challenge would otherwise resurrect destroyed pegs).
	# `clear_all_markings` (called by the tracker on challenge end) wipes them.
	# Re-applying the cuts happens at the bottom of this function, after the new
	# peg MultiMesh is populated.
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
		var y := -vertical_spacing * i
		for j in range(i + 1):
			# position_x_for is the single canonical lattice->x formula (also
			# used by cell_to_world / the Coin), so build and gameplay can't drift.
			_peg_positions[idx] = Vector3(position_x_for(i, j), y, 0)
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

	# --- Coin landing burst (only created once, persists across rebuilds) ---
	if not _coin_burst_field:
		_coin_burst_field = _COIN_BURST_FIELD_SCENE.instantiate()
		add_child(_coin_burst_field)

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

		# Single-currency model: every bucket earns the board's primary currency.
		# Advanced buckets (raw-currency edge buckets) are gone.
		var bucket_currency: Enums.CurrencyType = TierRegistry.primary_currency(board_type)

		var value: int = _bucket_value_for_distance(distance_from_center)
		# No single "prestige bucket" anymore — prestige is triggered by reaching
		# 500 of the currency, which any bucket can do (see _coin_completes_board).
		bucket.is_prestige_bucket = false
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

	# Peg positions changed (row add / rebuild) — re-derive paddle positions.
	if _deflector_editor:
		_deflector_editor.refresh()

	# Voids survive rebuilds — re-paint the destroyed pegs + hide the voided
	# buckets in the freshly-built MultiMesh / bucket nodes. Both column-based
	# (bomb hazard) and radial (forbidden bucket) voids share the same
	# survives-rebuild lifecycle.
	_reapply_voided_pegs()
	_reapply_voided_radii()

	board_rebuilt.emit()


## Returns the bounding rect of this board in local space.
## Used by BoardManager to frame the camera.
func get_bounds() -> Rect2:
	var top := vertical_spacing + 0.5
	var bottom := -vertical_spacing * num_rows + (vertical_spacing / 3) - 0.5
	var half_width := (num_rows / 2.0) * space_between_pegs + 0.5
	return Rect2(-half_width, bottom, half_width * 2.0, top - bottom)


## `animated` defaults to true (the player-purchase path runs the full juice).
## ChallengeManager._apply_starting_conditions sets it false so challenge setup
## doesn't fire the glissando + camera sweep before the player has even seen
## the board — the prior bug was that every `StartingBoards` row count fired
## row_upgrade_starting/sweep, suppressing BoardManager's normal fit-tween and
## playing audio cues during scene init.
func add_two_rows(animated: bool = true) -> void:
	# Voided columns are bucket-indexed; adding two rows adds one bucket on
	# each side, shifting every existing bucket's index by +1. Shift before
	# build_board so _reapply_voided_pegs sees the new numbering.
	_shift_voided_columns(1)
	if not animated:
		num_rows += 2
		build_board()
		return
	# Snapshot the OLD row count + container Y first — the scheduler needs the
	# row count to identify the two new peg rows (those with row >= old_num_rows)
	# that get hidden until the wavefront passes them, and the assert in
	# _play_row_upgrade_glissando uses the container delta to verify the lift
	# math against any future change to build_board's offset formula.
	# Emit `row_upgrade_starting` BEFORE build_board so BoardManager suppresses
	# the default fit-tween that board_rebuilt will fire mid-call; otherwise it
	# would race the sweep camera.
	var old_num_rows := num_rows
	var old_container_y := buckets_container.position.y
	row_upgrade_starting.emit()
	num_rows += 2
	build_board()                       # rebuilds geometry at NEW positions; emits board_rebuilt
	_play_row_upgrade_glissando(old_num_rows, old_container_y)


## Shifts every voided bucket index by `delta`. Called from add_two_rows so
## the existing voids stay anchored to the same geometric positions when the
## bucket-numbering shifts (new edge buckets added on each side).
func _shift_voided_columns(delta: int) -> void:
	if _voided_columns.is_empty() or delta == 0:
		return
	var shifted: PackedInt32Array = PackedInt32Array()
	for B in _voided_columns:
		shifted.append(B + delta)
	_voided_columns = shifted

## Whether a bucket at this distance-from-center is an "advanced" bucket
## (alternate currency). Single predicate so build_board, _bucket_value_for_distance,
## the bucket-value ripple, and the add-rows glissando can't drift on the
## condition.
func _is_advanced_at_distance(_distance: int) -> bool:
	# Single-currency model: advanced (raw-currency edge) buckets are removed.
	# Kept as a stub so existing callers (bucket value, multimesh build) stay valid.
	return false


## Computes the value for a bucket at a given distance from center.
## Used by both build_board() and the upgrade ripple to keep the formula in one place.
func _bucket_value_for_distance(distance: int) -> int:
	var val: int = 1 + distance * bucket_value_multiplier
	# Middle bucket (distance 0) is always value 1 and never scales via the
	# bucket-value upgrade, so a CENTER_BUCKET_VALUE challenge reward is the only
	# way to raise it.
	if distance == 0:
		val += ChallengeProgressManager.get_center_bucket_value_bonus(board_type)
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

		var is_adv: bool = _is_advanced_at_distance(distance)
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


## Pure scheduler for the add-rows glissando + new-peg reveal. No scene tree,
## no autoloads — primitives in, dictionary out (testable like get_bounds).
##
## A left→right wavefront drops bucket column i at step i. Each newly-added peg
## (row in [num_rows_before, num_rows_after - 1]) is revealed on the step of the
## bucket immediately to its left, so a peg never appears before the bucket left
## of it starts dropping.
##
## start_offset = 2 * vertical_spacing: after add_two_rows the buckets_container
## drops by 2 * vertical_spacing, so lifting each bucket's local y by that much
## puts the new row visually at the OLD row height; the fall tween brings it
## back to rest.
func _compute_row_upgrade_schedule(num_rows_before: int, num_rows_after: int,
		num_buckets: int, space: float, vert_spacing: float,
		glissando_interval: float) -> Dictionary:
	var start_offset: float = 2.0 * vert_spacing
	var sweep_duration: float = maxf(0.0, (num_buckets - 1) * glissando_interval)
	var bucket_x_offset: float = -space * (num_buckets - 1) / 2.0

	# One reveal list per column, indexed by bucket column 0..num_buckets-1.
	var reveal_by_col: Array = []
	for i in num_buckets:
		reveal_by_col.append(PackedInt32Array())

	for row in range(num_rows_before, num_rows_after):
		for col in range(row + 1):
			var peg_x: float = Lattice.x_for(row, col, space)
			# Largest bucket column i with (bucket_x_offset + i*space) <= peg_x,
			# clamped to [0, num_buckets-1]. If a peg sits to the left of every
			# bucket (rare; buckets span wider than pegs by design) we clamp to
			# 0 so it reveals on the very first step.
			var raw_col: int = floori((peg_x - bucket_x_offset) / space)
			var trigger_col: int = clampi(raw_col, 0, num_buckets - 1)
			# Triangular index — sum of pegs in all rows above (= row*(row+1)/2)
			# plus the column. Matches build_board's row-major fill order at
			# :1591-1594 and `peg_index()` at :1273; must stay in sync.
			@warning_ignore("integer_division")
			var flat_idx: int = row * (row + 1) / 2 + col
			reveal_by_col[trigger_col].append(flat_idx)

	var columns: Array = []
	for i in num_buckets:
		columns.append({
			"index": i,
			"glissando_degree": i,
			"reveal_peg_indices": reveal_by_col[i],
		})

	return {
		"start_offset": start_offset,
		"sweep_duration": sweep_duration,
		"start_local_x": bucket_x_offset,
		"end_local_x": bucket_x_offset + (num_buckets - 1) * space,
		"columns": columns,
	}


## Animates Add Rows as a left→right "piano glissando": the just-rebuilt bucket
## row is pre-lifted to the OLD row height, then each column falls + bounces +
## sings one at a time, with ascending pitch. Newly-added peg rows stay hidden
## until the bucket to their left begins dropping. Mirrors
## _play_bucket_value_upgrade_ripple's tween cadence and reuses
## _upgrade_animating + _upgrade_ripple_tween (so build_board()'s kill-on-rebuild
## handles re-trigger mid-animation for free).
func _play_row_upgrade_glissando(old_num_rows: int, old_container_y: float) -> void:
	_upgrade_animating = true
	if _upgrade_ripple_tween and _upgrade_ripple_tween.is_valid():
		_upgrade_ripple_tween.kill()

	var num_buckets: int = buckets_container.get_child_count()
	if num_buckets == 0:
		_upgrade_animating = false
		return

	# ThemeProvider is an autoload, always present in the live path — same
	# assumption as `_play_bucket_value_upgrade_ripple` above. No fallback
	# ladder; defaults live exactly once, in `VisualTheme`.
	var t: VisualTheme = ThemeProvider.theme
	var fall_duration: float = t.row_upgrade_fall_duration
	var overshoot: float = t.row_upgrade_bounce_overshoot
	var pre_drop_delay: float = t.row_upgrade_pre_drop_delay
	# Stagger is its own dial, deliberately NOT derived from fall_duration —
	# the density of the cascade (how many buckets are co-animating) is a
	# separate feel decision from how long each bucket takes. With the default
	# 0.125s stagger and 1.0s fall, eight buckets are concurrently in motion.
	var glissando_interval: float = t.row_upgrade_glissando_interval

	var schedule: Dictionary = _compute_row_upgrade_schedule(
		old_num_rows, num_rows, num_buckets,
		space_between_pegs, vertical_spacing, glissando_interval)
	var start_offset: float = schedule["start_offset"]
	var columns: Array = schedule["columns"]

	# Guard the load-bearing claim that lifting buckets by `start_offset` puts
	# them at the OLD bucket-row height. The scheduler computes `start_offset`
	# from `vertical_spacing` alone; this assert verifies it matches the actual
	# container Y delta produced by build_board. If build_board's offset
	# formula ever drifts, this trips before the glissando looks wrong.
	assert(is_equal_approx(start_offset, old_container_y - buckets_container.position.y))

	# Pre-stage in one frame, before the tween starts: every bucket up to the
	# old height, every new-row peg hidden. New EDGE buckets (positions that
	# didn't exist on the previous bucket row — always indices 0 and
	# num_buckets-1, since each add-rows widens by exactly 2) also start
	# invisible; they fade in during their fall.
	var last_idx: int = num_buckets - 1
	for i in num_buckets:
		var b: Bucket = get_bucket(i)
		if b:
			b.lift_for_fall(start_offset)
			if i == 0 or i == last_idx:
				b.snap_invisible()
	_set_new_pegs_hidden(columns)

	# Hand the sweep geometry to BoardManager (signals up, calls down — the
	# camera lives there). focus_local_y is in board-local space; BoardManager
	# adds board.position.y to get world.
	var sweep_duration: float = schedule["sweep_duration"]
	row_upgrade_sweep_started.emit(schedule["start_local_x"], schedule["end_local_x"],
		buckets_container.position.y, sweep_duration)

	# Same V-shape center used by build_board and _bucket_value_for_distance:
	# distance-from-center indexes into the chord array for normal landings.
	# For the glissando we pass the column index as `degree` instead (ascending
	# diatonic run); `center` is only used here for the is_adv classification.
	@warning_ignore("integer_division")
	var center: int = num_buckets / 2

	_upgrade_ripple_tween = create_tween()
	_upgrade_ripple_tween.bind_node(self)

	# Pause before the first bucket drops so the camera has time to pan over.
	# The audio cascade also waits — silence then the run, instead of starting
	# notes while the camera is mid-pan.
	if pre_drop_delay > 0.0:
		_upgrade_ripple_tween.tween_interval(pre_drop_delay)

	# Per-column step: fall, sing, glissando note (pitch = column index so it
	# ascends left→right), reveal that column's new pegs. Captures `entry` per
	# iteration the same way the ripple captures `group` (each iteration's
	# local var is its own binding in the closure).
	for col_data in columns:
		var entry: Dictionary = col_data
		_upgrade_ripple_tween.tween_callback(func() -> void:
			var i: int = entry["index"]
			var bucket: Bucket = get_bucket(i)
			if not bucket:
				return
			var distance: int = absi(i - center)
			var is_adv: bool = _is_advanced_at_distance(distance)
			bucket.fall_to_rest(start_offset, overshoot, fall_duration)
			if i == 0 or i == last_idx:
				bucket.fade_in(fall_duration)
			bucket.mark_singing()
			AudioManager.force_play_bucket(board_type, i, entry["glissando_degree"], is_adv)
			_reveal_new_pegs(entry["reveal_peg_indices"])
		)
		_upgrade_ripple_tween.tween_interval(glissando_interval)

	# Clean up after the full glissando.
	_upgrade_ripple_tween.tween_callback(func() -> void:
		_upgrade_animating = false
	)


## Zero-scales every new-row peg in the MultiMesh so it's invisible until its
## column's step reveals it. No-op without the multimesh (e.g. bare-instance
## tests, which never reach this code path).
func _set_new_pegs_hidden(columns: Array) -> void:
	if not _peg_multimesh_instance:
		return
	var mm: MultiMesh = _peg_multimesh_instance.multimesh
	var hidden_basis: Basis = _peg_basis.scaled(Vector3.ZERO)
	for col_data in columns:
		for flat_idx in col_data["reveal_peg_indices"]:
			mm.set_instance_transform(flat_idx,
				Transform3D(hidden_basis, _peg_positions[flat_idx]))


## Restores the given peg MultiMesh instances to their full transform —
## triggered per-column by the glissando wavefront.
func _reveal_new_pegs(indices: PackedInt32Array) -> void:
	if not _peg_multimesh_instance:
		return
	var mm: MultiMesh = _peg_multimesh_instance.multimesh
	for flat_idx in indices:
		mm.set_instance_transform(flat_idx,
			Transform3D(_peg_basis, _peg_positions[flat_idx]))


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


# Intentionally a thresholded nearest-search over rendered positions, NOT the
# lattice math (position_x_for / peg_index): it runs mid-bounce when the coin is
# not snapped to a peg, so it must tolerate the bounce arc. Kept separate from
# the deflector lookup on purpose — they answer different questions.
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

	# Sparkle is the rare, rewarding event (gated by should_sparkle's proximity
	# window). When it doesn't fire, fall through to the throttled chime.
	var is_sparkle: bool = AudioManager.should_sparkle(board_type)
	if is_sparkle:
		AudioManager.play_peg_sparkle(board_type)
	else:
		AudioManager.play_peg_chime()

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
	# accent rather than a generic ripple. Chimes never get the ring; they're
	# the high-frequency throttled layer and would look too busy.
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


## Effective queue slots for a raw queue level (purchased + permanent challenge
## grants). Empty until the first level; the first level grants 2 slots, each
## level after adds 1 (capacity = level + 1 once any level is owned).
static func _queue_capacity_for_level(level: int) -> int:
	return level + 1 if level > 0 else 0


func increase_queue_capacity() -> void:
	# upgrade_section._buy_upgrade() commits the QUEUE level via UpgradeManager.buy()
	# before calling this, so the level read here is already the new value.
	var level: int = UpgradeManager.get_level(board_type, Enums.UpgradeType.QUEUE) \
		+ ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.QUEUE)
	coin_queue.set_capacity(_queue_capacity_for_level(level))


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
	var captured_bid: StringName = bid
	var is_adv: bool = (bid as String).ends_with("_ADVANCED")
	var label: String = "advanced autodropper" if is_adv else "autodropper"

	bar.setup_minus(
		func(): autodropper_adjust_requested.emit(captured_bid, -1),
		func() -> String: return "Remove %s" % label,
	)

	bar.setup_plus(
		func(): autodropper_adjust_requested.emit(captured_bid, 1),
		func() -> String: return "Add %s" % label,
	)


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


func get_drop_button_screen_center(btn_id: StringName) -> Vector2:
	var bar: HBoxContainer = _drop_buttons.get(btn_id)
	if not is_instance_valid(bar):
		return Vector2.ZERO
	return bar.get_global_rect().get_center()


func get_drop_button_ids() -> Array:
	return _drop_buttons.keys()


func set_drop_subtext(button_id: StringName, text: String) -> void:
	var bar: HBoxContainer = _drop_buttons.get(button_id)
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

	advanced_coin_multiplier = upgrade_state.get("advanced_coin_multiplier", 2.0)

	var drop_rate_level: int = upgrade_state.get("DROP_RATE", 0)
	var perm_dr: int = ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.DROP_RATE)
	for i in drop_rate_level + perm_dr:
		drop_delay *= drop_delay_reduction_factor

	var queue_level: int = upgrade_state.get("QUEUE", 0)
	var perm_q: int = ChallengeProgressManager.get_permanent_upgrade_level(board_type, Enums.UpgradeType.QUEUE)
	coin_queue.set_capacity(_queue_capacity_for_level(queue_level + perm_q))

	if upgrade_state.get("show_advanced_buckets", false):
		should_show_advanced_buckets = true
	if upgrade_state.get("has_advanced_drop", false):
		_show_advanced_drop_bar()

	build_board()

	# Restore deflectors LAST: build_board() rebuilt the peg grid, and
	# UpgradeManager (slot cap source) was deserialized before BoardManager.
	# restore_deflectors drops entries off-grid or beyond the cap.
	restore_deflectors(upgrade_state.get("deflectors", []))
	if _deflector_editor:
		_deflector_editor.set_capacity(get_deflector_cap())
		_deflector_editor.refresh()
