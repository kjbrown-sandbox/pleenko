class_name ChallengeTracker
extends Node
## Runs a single active challenge: tracks coin landings, checks constraints
## and objectives, and manages the timer. Uses the board's marking API for
## bucket visuals rather than reaching into bucket nodes directly.

signal completed
signal failed(reason: String)

var challenge: ChallengeData
var board_manager: BoardManager
var time_remaining: float = 0.0

# Tracking state
var _bucket_hits: Dictionary = {}  # _bucket_key() -> int (lifetime hits, for LandInEveryBucket etc.)
var _group_hits: Dictionary = {}   # _bucket_key() -> bool (hits within current bucket group only)
var _last_bucket: Dictionary = {}  # BoardType -> int
var _same_bucket_streak: Dictionary = {}  # BoardType -> int
var _survive_passed: bool = false
var _current_bucket_group: int = 0
var _total_drops: int = 0
var _has_failed: bool = false
var _timer_started: bool = false
# Last integer second-value emitted via ChallengeManager.tick. Tracks both the
# regular and survive timers; -1 = nothing emitted yet.
var _last_tick_seconds: int = -1

# Survive-specific state. Survive challenges drive their own two-phase timing
# and ignore challenge.time_limit_seconds entirely.
enum SurvivePhase { WAITING, SURVIVING, DONE }
var _survive_objective: Survive = null
var _survive_phase: int = SurvivePhase.WAITING
var _survive_phase_remaining: float = 0.0
## Total real-time elapsed since survive challenge started (for stats).
var _survive_elapsed: float = 0.0


func get_total_drops() -> int:
	return _total_drops


func get_time_taken() -> float:
	if _survive_objective:
		return _survive_elapsed
	return challenge.time_limit_seconds - time_remaining if challenge else 0.0


func setup(_challenge: ChallengeData, _board_manager: BoardManager) -> void:
	challenge = _challenge
	board_manager = _board_manager
	time_remaining = challenge.time_limit_seconds
	_bucket_hits.clear()
	_group_hits.clear()
	_last_bucket.clear()
	_same_bucket_streak.clear()
	_survive_passed = false
	_current_bucket_group = 0
	_total_drops = 0
	_timer_started = false
	_last_tick_seconds = -1

	# Detect a Survive objective and initialize the two-phase countdown.
	_survive_objective = null
	_survive_phase = SurvivePhase.WAITING
	_survive_elapsed = 0.0
	for objective in challenge.objectives:
		if objective is Survive:
			_survive_objective = objective
			_survive_phase_remaining = objective.start_delay
			break


func start_timer() -> void:
	_timer_started = true


func connect_to_boards() -> void:
	for board in board_manager.get_boards():
		_connect_board(board)
	board_manager.board_switched.connect(_on_board_switched)
	CurrencyManager.currency_changed.connect(_on_currency_changed)


func _connect_board(board: PlinkoBoard) -> void:
	if board.coin_landed.is_connected(_on_coin_landed):
		return
	board.coin_landed.connect(_on_coin_landed)
	board.coin_dropped.connect(_on_coin_dropped)
	board.autodrop_failed.connect(_on_autodrop_failed)


func _on_coin_dropped() -> void:
	if not _timer_started:
		_timer_started = true


func _on_board_switched(_board: PlinkoBoard) -> void:
	for board in board_manager.get_boards():
		_connect_board(board)


# ── Timer ─────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _survive_objective:
		_process_survive(delta)
		return
	if not _timer_started:
		return
	time_remaining -= delta
	if time_remaining <= 0.0:
		time_remaining = 0.0
		_on_time_up()
		set_process(false)
	_maybe_emit_tick(time_remaining)


## Emits ChallengeManager.tick(seconds_remaining) when the integer second
## boundary crosses downward. Use for both the regular timer and the SURVIVING
## phase so every challenge has a consistent per-second pulse for audio + UI.
func _maybe_emit_tick(remaining: float) -> void:
	var new_sec: int = int(ceil(remaining))
	if new_sec < 0:
		return
	if new_sec != _last_tick_seconds:
		_last_tick_seconds = new_sec
		ChallengeManager.tick.emit(new_sec)


func _process_survive(delta: float) -> void:
	if _has_failed or _survive_phase == SurvivePhase.DONE:
		return
	_survive_elapsed += delta
	_survive_phase_remaining -= delta
	if _survive_phase == SurvivePhase.SURVIVING:
		_maybe_emit_tick(_survive_phase_remaining)
	if _survive_phase_remaining > 0.0:
		return

	if _survive_phase == SurvivePhase.WAITING:
		# Transition: autodroppers appear and the survive countdown starts.
		_survive_phase = SurvivePhase.SURVIVING
		_survive_phase_remaining += _survive_objective.survive_duration
		ChallengeManager.activate_survive_autodroppers(_survive_objective)
	elif _survive_phase == SurvivePhase.SURVIVING:
		# Survived the full duration — challenge complete.
		_survive_phase_remaining = 0.0
		_survive_phase = SurvivePhase.DONE
		_survive_passed = true
		set_process(false)
		if _are_all_objectives_met():
			completed.emit()


func _on_time_up() -> void:
	if _has_failed:
		return
	_survive_passed = true
	if _are_all_objectives_met():
		completed.emit()
	else:
		_has_failed = true
		failed.emit("Time's up!")


# ── Coin landing ─────────────────────────────────────────────────

func _on_coin_landed(board_type: Enums.BoardType, bucket_index: int, _currency_type: Enums.CurrencyType, _amount: int, multiplier: float) -> void:
	if _has_failed:
		return
	_total_drops += 1

	# Track bucket hits — multiplier coins count as round(multiplier) hits (min 1)
	var hit_count: int = maxi(1, roundi(multiplier))
	var key := _bucket_key(board_type, bucket_index)
	var first_hit := not _bucket_hits.has(key)
	_bucket_hits[key] = _bucket_hits.get(key, 0) + hit_count
	_group_hits[key] = true

	# Mark bucket visually for LandInEveryBucket objectives
	if first_hit:
		for objective in challenge.objectives:
			if objective is LandInEveryBucket and objective.board_type == board_type:
				var board := _get_board(board_type)
				if board:
					board.mark_bucket_hit(bucket_index)

	# Check HitBucketsInOrder progress
	for objective in challenge.objectives:
		if objective is HitBucketsInOrder and objective.board_type == board_type:
			var board := _get_board(board_type)
			if not board:
				continue

			# Unmark this individual target if it's in the current group
			if _current_bucket_group < objective.bucket_groups.size():
				var current_group: PackedInt32Array = objective.bucket_groups[_current_bucket_group]
				if bucket_index in current_group:
					board.unmark_bucket(bucket_index)

			# Try to advance to next group (uses _group_hits, not lifetime _bucket_hits)
			if _try_advance_bucket_group(objective):
				# Unmark any remaining buckets from completed group
				var completed_group: PackedInt32Array = objective.bucket_groups[_current_bucket_group - 1]
				for bi in completed_group:
					board.unmark_bucket(bi)
				# Reset group hits for the new group
				_group_hits.clear()
				# Mark next group as targets
				if _current_bucket_group < objective.bucket_groups.size():
					for bi in objective.bucket_groups[_current_bucket_group]:
						board.mark_bucket_target(bi)

	# Track streaks
	var prev: int = _last_bucket.get(board_type, -1)
	if bucket_index == prev:
		_same_bucket_streak[board_type] = _same_bucket_streak.get(board_type, 0) + 1
	else:
		_same_bucket_streak[board_type] = 1
	_last_bucket[board_type] = bucket_index

	# Check bucket constraints
	for constraint in challenge.constraints:
		if constraint is NeverTouchBucket:
			if board_type == constraint.board_type and bucket_index == constraint.bucket_index:
				_has_failed = true
				failed.emit("Landed in forbidden bucket!")
				return

	# Check drop-limit failures
	for objective in challenge.objectives:
		if objective is EarnWithinXDrops and _total_drops > objective.max_drops:
			var balance := CurrencyManager.get_balance(objective.currency_type)
			if balance < objective.amount:
				_has_failed = true
				failed.emit("Ran out of drops!")
				return

	# Check if all objectives are now met
	if _are_all_objectives_met():
		completed.emit()


# ── Currency constraints ──────────────────────────────────────────

func _on_currency_changed(type: Enums.CurrencyType, new_balance: int, _new_cap: int) -> void:
	if _has_failed:
		return
	for constraint in challenge.constraints:
		if constraint is NeverMoreThanXCoins:
			if type == constraint.currency_type and new_balance > constraint.amount:
				_has_failed = true
				failed.emit("Exceeded %d %s!" % [constraint.amount, Enums.CurrencyType.keys()[type]])
				return
		elif constraint is NeverLessThanXCoins:
			if type == constraint.currency_type and new_balance < constraint.amount:
				_has_failed = true
				failed.emit("Dropped below %d %s!" % [constraint.amount, Enums.CurrencyType.keys()[type]])
				return


# ── Autodrop failure ──────────────────────────────────────────────

func _on_autodrop_failed(board_type: Enums.BoardType) -> void:
	if _has_failed:
		return
	for objective in challenge.objectives:
		if objective is Survive and objective.board_type == board_type:
			_has_failed = true
			failed.emit("Autodropper can't afford to drop!")
			return


# ── Visual marking (via board API) ────────────────────────────────

func mark_initial_visuals() -> void:
	for objective in challenge.objectives:
		if objective is HitXBucketYTimes:
			var board := _get_board(objective.board_type)
			if board:
				board.mark_bucket_target(objective.bucket_index)
		elif objective is HitBucketsInOrder:
			var board := _get_board(objective.board_type)
			if board and not objective.bucket_groups.is_empty():
				for bi in objective.bucket_groups[0]:
					board.mark_bucket_target(bi)

	for constraint in challenge.constraints:
		if constraint is NeverTouchBucket:
			var board := _get_board(constraint.board_type)
			if board:
				board.mark_bucket_forbidden(constraint.bucket_index)


# ── Objective validation ──────────────────────────────────────────

func _are_all_objectives_met() -> bool:
	for objective in challenge.objectives:
		if not _is_objective_met(objective):
			return false
	return true


func _is_objective_met(objective: ChallengeObjective) -> bool:
	if objective is CoinGoal:
		var balance := CurrencyManager.get_balance(objective.currency_type)
		if objective.exact:
			return balance == objective.amount
		return balance >= objective.amount

	elif objective is BoardGoal:
		return board_manager and board_manager.is_board_unlocked(objective.board_type)

	elif objective is Survive:
		return _survive_passed

	elif objective is GetSameBucketXTimes:
		if objective.in_a_row:
			return _same_bucket_streak.get(objective.board_type, 0) >= objective.times
		for key in _bucket_hits:
			if key.begins_with(_bucket_key_prefix(objective.board_type)):
				if _bucket_hits[key] >= objective.times:
					return true
		return false

	elif objective is HitXBucketYTimes:
		return _bucket_hits.get(_bucket_key(objective.board_type, objective.bucket_index), 0) >= objective.times

	elif objective is HitBucketsInOrder:
		return _current_bucket_group >= objective.bucket_groups.size()

	elif objective is LandInEveryBucket:
		var board := _get_board(objective.board_type)
		if not board:
			return false
		for i in board.num_rows + 1:
			if not _bucket_hits.has(_bucket_key(objective.board_type, i)):
				return false
		return true

	elif objective is EarnWithinXDrops:
		if _total_drops > objective.max_drops:
			return false
		return CurrencyManager.get_balance(objective.currency_type) >= objective.amount

	return false


func _try_advance_bucket_group(objective: HitBucketsInOrder) -> bool:
	if _current_bucket_group >= objective.bucket_groups.size():
		return false
	# Only count hits that occurred AFTER this group became active
	var group: PackedInt32Array = objective.bucket_groups[_current_bucket_group]
	for bi in group:
		if not _group_hits.has(_bucket_key(objective.board_type, bi)):
			return false
	_current_bucket_group += 1
	return true


# ── Progress text ─────────────────────────────────────────────────

func get_progress_text() -> String:
	# Survive challenges replace the entire progress text with a phase-aware
	# countdown line.
	if _survive_objective:
		return _get_survive_progress_text()

	var parts: PackedStringArray = []
	for objective in challenge.objectives:
		if objective is GetSameBucketXTimes:
			var best: int = 0
			for key in _bucket_hits:
				if key.begins_with(_bucket_key_prefix(objective.board_type)):
					best = maxi(best, _bucket_hits[key])
			parts.append("%d / %d" % [best, objective.times])
		elif objective is HitXBucketYTimes:
			var hits: int = _bucket_hits.get(_bucket_key(objective.board_type, objective.bucket_index), 0)
			parts.append("%d / %d" % [hits, objective.times])
		elif objective is HitBucketsInOrder:
			# Count total buckets across all groups, and how many have been completed
			var total_buckets: int = 0
			var completed_buckets: int = 0
			for gi in objective.bucket_groups.size():
				var group: PackedInt32Array = objective.bucket_groups[gi]
				total_buckets += group.size()
				if gi < _current_bucket_group:
					completed_buckets += group.size()
			# Add any hits in the current active group
			if _current_bucket_group < objective.bucket_groups.size():
				var active_group: PackedInt32Array = objective.bucket_groups[_current_bucket_group]
				for bi in active_group:
					if _group_hits.has(_bucket_key(objective.board_type, bi)):
						completed_buckets += 1
			parts.append("%d / %d" % [completed_buckets, total_buckets])
	return "\n".join(parts)


# ── Utilities ─────────────────────────────────────────────────────

func _get_board(board_type: Enums.BoardType) -> PlinkoBoard:
	if not board_manager:
		return null
	for board in board_manager.get_boards():
		if board.board_type == board_type:
			return board
	return null

func _get_survive_progress_text() -> String:
	var seconds: int = int(ceil(_survive_phase_remaining))
	var mins: int = seconds / 60
	var secs: int = seconds % 60
	var time_str: String = "%d:%02d" % [mins, secs]
	match _survive_phase:
		SurvivePhase.WAITING:
			var board_name: String = Enums.BoardType.keys()[_survive_objective.board_type].to_lower()
			return "Time until %s autodropper starts: %s" % [board_name, time_str]
		SurvivePhase.SURVIVING:
			return "Survive for: %s" % time_str
	return ""


static func _bucket_key(board_type: Enums.BoardType, bucket_index: int) -> String:
	return "%d_%d" % [board_type, bucket_index]

static func _bucket_key_prefix(board_type: Enums.BoardType) -> String:
	return "%d_" % board_type


# ── Teardown ──────────────────────────────────────────────────────

func disconnect_all() -> void:
	if CurrencyManager.currency_changed.is_connected(_on_currency_changed):
		CurrencyManager.currency_changed.disconnect(_on_currency_changed)
	if board_manager:
		if board_manager.board_switched.is_connected(_on_board_switched):
			board_manager.board_switched.disconnect(_on_board_switched)
		for board in board_manager.get_boards():
			if board.coin_landed.is_connected(_on_coin_landed):
				board.coin_landed.disconnect(_on_coin_landed)
			if board.coin_dropped.is_connected(_on_coin_dropped):
				board.coin_dropped.disconnect(_on_coin_dropped)
			if board.autodrop_failed.is_connected(_on_autodrop_failed):
				board.autodrop_failed.disconnect(_on_autodrop_failed)
			board.clear_all_markings()
