class_name ChallengeTracker
extends Node
## Runs a single active challenge: tracks coin landings, checks constraints
## and objectives, manages the timer, and marks buckets visually.

signal completed
signal failed(reason: String)

var challenge: ChallengeData
var board_manager: BoardManager
var time_remaining: float = 0.0

# Tracking state
var _bucket_hits: Dictionary = {}  # _bucket_key() -> int
var _last_bucket: Dictionary = {}  # BoardType -> int
var _same_bucket_streak: Dictionary = {}  # BoardType -> int
var _survive_passed: bool = false
var _current_bucket_group: int = 0
var _total_drops: int = 0


func setup(_challenge: ChallengeData, _board_manager: BoardManager) -> void:
	challenge = _challenge
	board_manager = _board_manager
	time_remaining = challenge.time_limit_seconds
	_bucket_hits.clear()
	_last_bucket.clear()
	_same_bucket_streak.clear()
	_survive_passed = false
	_current_bucket_group = 0
	_total_drops = 0


func connect_to_boards() -> void:
	for board in board_manager.get_boards():
		_connect_board(board)
	board_manager.board_switched.connect(_on_board_switched)
	CurrencyManager.currency_changed.connect(_on_currency_changed)


func _connect_board(board: PlinkoBoard) -> void:
	if board.coin_landed.is_connected(_on_coin_landed):
		return
	board.coin_landed.connect(_on_coin_landed)
	board.autodrop_failed.connect(_on_autodrop_failed)
	board.board_rebuilt.connect(_on_board_rebuilt.bind(board))


func _on_board_switched(_board: PlinkoBoard) -> void:
	for board in board_manager.get_boards():
		_connect_board(board)


# ── Timer ─────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	time_remaining -= delta
	if time_remaining <= 0.0:
		time_remaining = 0.0
		_on_time_up()
		set_process(false)


func _on_time_up() -> void:
	_survive_passed = true
	if _are_all_objectives_met():
		completed.emit()
	else:
		failed.emit("Time's up!")


# ── Coin landing ─────────────────────────────────────────────────

func _on_coin_landed(board_type: Enums.BoardType, bucket_index: int, _currency_type: Enums.CurrencyType, _amount: int) -> void:
	_total_drops += 1

	# Track bucket hits
	var key := _bucket_key(board_type, bucket_index)
	var first_hit := not _bucket_hits.has(key)
	_bucket_hits[key] = _bucket_hits.get(key, 0) + 1

	# Mark bucket visually for LandInEveryBucket objectives
	if first_hit:
		for objective in challenge.objectives:
			if objective is LandInEveryBucket and objective.board_type == board_type:
				var board := _get_board(board_type)
				if board:
					var bucket := board.get_bucket(bucket_index)
					if bucket:
						bucket.mark_hit()

	# Check HitBucketsInOrder progress
	for objective in challenge.objectives:
		if objective is HitBucketsInOrder and objective.board_type == board_type:
			if _try_advance_bucket_group(objective):
				if _current_bucket_group < objective.bucket_groups.size():
					_mark_bucket_group(objective, _current_bucket_group)

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
				failed.emit("Landed in forbidden bucket!")
				return

	# Check drop-limit failures
	for objective in challenge.objectives:
		if objective is EarnWithinXDrops and _total_drops > objective.max_drops:
			var balance := CurrencyManager.get_balance(objective.currency_type)
			if balance < objective.amount:
				failed.emit("Ran out of drops!")
				return

	# Check if all objectives are now met
	if _are_all_objectives_met():
		completed.emit()


# ── Currency constraints ──────────────────────────────────────────

func _on_currency_changed(type: Enums.CurrencyType, new_balance: int, _new_cap: int) -> void:
	for constraint in challenge.constraints:
		if constraint is NeverMoreThanXCoins:
			if type == constraint.currency_type and new_balance > constraint.amount:
				failed.emit("Exceeded %d %s!" % [constraint.amount, Enums.CurrencyType.keys()[type]])
				return
		elif constraint is NeverLessThanXCoins:
			if type == constraint.currency_type and new_balance < constraint.amount:
				failed.emit("Dropped below %d %s!" % [constraint.amount, Enums.CurrencyType.keys()[type]])
				return


# ── Autodrop failure ──────────────────────────────────────────────

func _on_autodrop_failed(board_type: Enums.BoardType) -> void:
	for objective in challenge.objectives:
		if objective is Survive and objective.board_type == board_type:
			failed.emit("Autodropper can't afford to drop!")
			return


# ── Board rebuilt — re-mark visuals ───────────────────────────────

func _on_board_rebuilt(board: PlinkoBoard) -> void:
	for objective in challenge.objectives:
		if objective is LandInEveryBucket and objective.board_type == board.board_type:
			var bucket_count: int = board.num_rows + 1
			for i in bucket_count:
				if _bucket_hits.has(_bucket_key(board.board_type, i)):
					var bucket := board.get_bucket(i)
					if bucket:
						bucket.mark_hit()
		elif objective is HitXBucketYTimes and objective.board_type == board.board_type:
			_mark_target_bucket(objective)
		elif objective is HitBucketsInOrder and objective.board_type == board.board_type:
			for gi in range(_current_bucket_group + 1):
				_mark_bucket_group(objective, gi)

	for constraint in challenge.constraints:
		if constraint is NeverTouchBucket and constraint.board_type == board.board_type:
			_mark_forbidden_bucket(constraint)


# ── Visual marking ────────────────────────────────────────────────

func mark_initial_visuals() -> void:
	for objective in challenge.objectives:
		if objective is HitXBucketYTimes:
			_mark_target_bucket(objective)
		elif objective is HitBucketsInOrder:
			_mark_bucket_group(objective, 0)

	for constraint in challenge.constraints:
		if constraint is NeverTouchBucket:
			_mark_forbidden_bucket(constraint)


func _mark_bucket_group(objective: HitBucketsInOrder, group_index: int) -> void:
	if group_index >= objective.bucket_groups.size():
		return
	var board := _get_board(objective.board_type)
	if not board:
		return
	for bi in objective.bucket_groups[group_index]:
		var bucket := board.get_bucket(bi)
		if bucket:
			bucket.mark_hit()


func _mark_target_bucket(objective: HitXBucketYTimes) -> void:
	var board := _get_board(objective.board_type)
	if board:
		var bucket := board.get_bucket(objective.bucket_index)
		if bucket:
			bucket.mark_hit()


func _mark_forbidden_bucket(constraint: NeverTouchBucket) -> void:
	var board := _get_board(constraint.board_type)
	if board:
		var bucket := board.get_bucket(constraint.bucket_index)
		if bucket:
			bucket.mark_forbidden()


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
	var group: PackedInt32Array = objective.bucket_groups[_current_bucket_group]
	for bi in group:
		if not _bucket_hits.has(_bucket_key(objective.board_type, bi)):
			return false
	_current_bucket_group += 1
	return true


# ── Progress text ─────────────────────────────────────────────────

func get_progress_text() -> String:
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
			parts.append("%d / %d" % [_current_bucket_group, objective.bucket_groups.size()])
	return "\n".join(parts)


# ── Utilities ─────────────────────────────────────────────────────

func _get_board(board_type: Enums.BoardType) -> PlinkoBoard:
	if not board_manager:
		return null
	for board in board_manager.get_boards():
		if board.board_type == board_type:
			return board
	return null

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
			if board.autodrop_failed.is_connected(_on_autodrop_failed):
				board.autodrop_failed.disconnect(_on_autodrop_failed)
			for conn in board.board_rebuilt.get_connections():
				if conn["callable"].get_method() == "_on_board_rebuilt":
					board.board_rebuilt.disconnect(conn["callable"])
