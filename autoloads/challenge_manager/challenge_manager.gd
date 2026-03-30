extends Node

signal challenge_completed
signal challenge_failed(reason: String)

var is_active_challenge: bool = false
var _challenge: ChallengeData
var _board_manager: BoardManager
var _time_remaining: float = 0.0
var _total_drops: int = 0

# Tracking state for objectives
var _bucket_hits: Dictionary = {}  # "BoardType_BucketIndex" -> int
var _last_bucket: Dictionary = {}  # BoardType -> int (last bucket index hit)
var _same_bucket_streak: Dictionary = {}  # BoardType -> int
var _survive_passed: bool = false


func set_challenge(challenge: ChallengeData) -> void:
	_challenge = challenge
	is_active_challenge = true


func get_challenge() -> ChallengeData:
	return _challenge


func get_time_remaining() -> float:
	return _time_remaining


func setup(board_manager: BoardManager) -> void:
	_board_manager = board_manager
	_time_remaining = _challenge.time_limit_seconds
	_total_drops = 0
	_bucket_hits.clear()
	_last_bucket.clear()
	_same_bucket_streak.clear()

	# Set gates on other managers
	UpgradeManager.upgrade_gate = is_upgrade_allowed
	_board_manager.board_gate = is_board_allowed

	# Connect to board signals
	for board in _board_manager.get_boards():
		_connect_board(board)

	# Connect to currency changes for constraint checking
	CurrencyManager.currency_changed.connect(_on_currency_changed)

	# Listen for new boards being unlocked
	_board_manager.board_switched.connect(_on_board_switched)

	# Apply starting conditions
	_apply_starting_conditions()

	# Mark target buckets for HitXBucketYTimes objectives
	for objective in _challenge.objectives:
		if objective is HitXBucketYTimes:
			_mark_target_bucket(objective)

	# Force-start autodroppers for Survive objectives
	for objective in _challenge.objectives:
		if objective is Survive:
			_setup_survive(objective)


func _connect_board(board: PlinkoBoard) -> void:
	board.coin_landed.connect(_on_coin_landed)
	board.autodrop_failed.connect(_on_autodrop_failed)
	board.board_rebuilt.connect(_on_board_rebuilt.bind(board))


func _on_board_switched(_board: PlinkoBoard) -> void:
	# Connect new boards that may not have been connected yet
	for board in _board_manager.get_boards():
		if not board.coin_landed.is_connected(_on_coin_landed):
			_connect_board(board)


func _process(delta: float) -> void:
	if not is_active_challenge:
		return

	_time_remaining -= delta
	if _time_remaining <= 0.0:
		_time_remaining = 0.0
		_on_time_up()


func _on_time_up() -> void:
	_survive_passed = true
	if _check_all_objectives_met():
		challenge_completed.emit()
	else:
		challenge_failed.emit("Time's up!")


func _on_coin_landed(board_type: Enums.BoardType, bucket_index: int, _currency_type: Enums.CurrencyType, _amount: int) -> void:
	_total_drops += 1

	# Track bucket hits
	var key := "%d_%d" % [board_type, bucket_index]
	var first_hit := not _bucket_hits.has(key)
	_bucket_hits[key] = _bucket_hits.get(key, 0) + 1

	# Mark bucket visually for LandInEveryBucket objectives
	if first_hit:
		for objective in _challenge.objectives:
			if objective is LandInEveryBucket and objective.board_type == board_type:
				var board := _get_board(board_type)
				if board:
					var bucket := board.get_bucket(bucket_index)
					if bucket:
						bucket.mark_hit()

	# Track streaks
	var last: int = _last_bucket.get(board_type, -1)
	if bucket_index == last:
		_same_bucket_streak[board_type] = _same_bucket_streak.get(board_type, 0) + 1
	else:
		_same_bucket_streak[board_type] = 1
	_last_bucket[board_type] = bucket_index

	# Check constraints
	_check_bucket_constraints(board_type, bucket_index)

	# Check drop-limit failures
	for objective in _challenge.objectives:
		if objective is EarnWithinXDrops and _total_drops > objective.max_drops:
			var balance := CurrencyManager.get_balance(objective.currency_type)
			if balance < objective.amount:
				challenge_failed.emit("Ran out of drops!")
				return

	# Check objectives
	_check_objectives()


func _on_board_rebuilt(board: PlinkoBoard) -> void:
	if not is_active_challenge:
		return
	for objective in _challenge.objectives:
		# Re-mark hit buckets after board rebuild (e.g. buying bucket value)
		if objective is LandInEveryBucket and objective.board_type == board.board_type:
			var bucket_count: int = board.num_rows + 1
			for i in bucket_count:
				var key := "%d_%d" % [board.board_type, i]
				if _bucket_hits.has(key):
					var bucket := board.get_bucket(i)
					if bucket:
						bucket.mark_hit()
		# Re-mark target bucket for HitXBucketYTimes
		elif objective is HitXBucketYTimes and objective.board_type == board.board_type:
			_mark_target_bucket(objective)


func _mark_target_bucket(objective: HitXBucketYTimes) -> void:
	var board := _get_board(objective.board_type)
	if board:
		var bucket := board.get_bucket(objective.bucket_index)
		if bucket:
			bucket.mark_hit()


func _on_currency_changed(type: Enums.CurrencyType, new_balance: int, _new_cap: int) -> void:
	for constraint in _challenge.constraints:
		if constraint is NeverMoreThanXCoins:
			if type == constraint.currency_type and new_balance > constraint.amount:
				challenge_failed.emit("Exceeded %d %s!" % [constraint.amount, Enums.CurrencyType.keys()[type]])
				return
		elif constraint is NeverLessThanXCoins:
			if type == constraint.currency_type and new_balance < constraint.amount:
				challenge_failed.emit("Dropped below %d %s!" % [constraint.amount, Enums.CurrencyType.keys()[type]])
				return


func _check_bucket_constraints(board_type: Enums.BoardType, bucket_index: int) -> void:
	for constraint in _challenge.constraints:
		if constraint is NeverTouchBucket:
			if board_type == constraint.board_type and bucket_index == constraint.bucket_index:
				challenge_failed.emit("Landed in forbidden bucket!")
				return


func _check_objectives() -> void:
	if _check_all_objectives_met():
		challenge_completed.emit()


func _check_all_objectives_met() -> bool:
	for objective in _challenge.objectives:
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
		if not _board_manager:
			return false
		return _board_manager.is_board_unlocked(objective.board_type)

	elif objective is Survive:
		return _survive_passed

	elif objective is GetSameBucketXTimes:
		if objective.in_a_row:
			return _same_bucket_streak.get(objective.board_type, 0) >= objective.times
		else:
			# Check if any bucket on this board has been hit enough times
			for key in _bucket_hits:
				if key.begins_with("%d_" % objective.board_type):
					if _bucket_hits[key] >= objective.times:
						return true
			return false

	elif objective is HitXBucketYTimes:
		var key := "%d_%d" % [objective.board_type, objective.bucket_index]
		return _bucket_hits.get(key, 0) >= objective.times

	elif objective is LandInEveryBucket:
		var board := _get_board(objective.board_type)
		if not board:
			return false
		var bucket_count: int = board.num_rows + 1
		for i in bucket_count:
			var key := "%d_%d" % [objective.board_type, i]
			if not _bucket_hits.has(key):
				return false
		return true

	elif objective is EarnWithinXDrops:
		if _total_drops > objective.max_drops:
			# This is handled as a failure, not just "not met"
			return false
		var balance := CurrencyManager.get_balance(objective.currency_type)
		return balance >= objective.amount

	return false


func _on_autodrop_failed(board_type: Enums.BoardType) -> void:
	for objective in _challenge.objectives:
		if objective is Survive and objective.board_type == board_type:
			challenge_failed.emit("Autodropper can't afford to drop!")
			return


func _apply_starting_conditions() -> void:
	for condition in _challenge.starting_conditions:
		if condition is StartingCoins:
			CurrencyManager.add(condition.currency_type, condition.amount)
		elif condition is StartingUpgrades:
			for i in condition.level:
				UpgradeManager.force_apply(condition.board_type, condition.upgrade_type)
		elif condition is StartingBoards:
			_board_manager.unlock_board(condition.board_type)
			var board := _get_board(condition.board_type)
			if board:
				var rows_to_add: int = (condition.rows - 2) / 2
				for i in rows_to_add:
					board.add_two_rows()


func _setup_survive(objective: Survive) -> void:
	# Force-assign autodroppers to the specified board
	var board := _get_board(objective.board_type)
	if not board:
		return
	var normal_id := StringName("%s_NORMAL" % Enums.BoardType.keys()[objective.board_type])
	for i in objective.autodropper_count:
		_board_manager._on_autodropper_adjust(normal_id, 1)


func _get_board(board_type: Enums.BoardType) -> PlinkoBoard:
	if not _board_manager:
		return null
	for board in _board_manager.get_boards():
		if board.board_type == board_type:
			return board
	return null


func is_upgrade_allowed(upgrade_type: Enums.UpgradeType) -> bool:
	if not is_active_challenge:
		return true
	for constraint in _challenge.constraints:
		if constraint is UpgradesLimited:
			if constraint.all_upgrades:
				return false
			if upgrade_type in constraint.blocked_upgrades:
				return false
	return true


func is_board_allowed(board_type: Enums.BoardType) -> bool:
	if not is_active_challenge:
		return true
	for constraint in _challenge.constraints:
		if constraint is OnlyOneBoard:
			return board_type == constraint.board_type
	return true


func get_objective_text() -> String:
	var parts: PackedStringArray = []
	for objective in _challenge.objectives:
		if objective is CoinGoal:
			var currency_name: String = Enums.CurrencyType.keys()[objective.currency_type].to_lower().replace("_", " ")
			if objective.exact:
				parts.append("Get exactly %d %ss" % [objective.amount, currency_name])
			else:
				parts.append("Earn %d %ss" % [objective.amount, currency_name])
		elif objective is BoardGoal:
			var board_name: String = Enums.BoardType.keys()[objective.board_type].to_lower()
			parts.append("Unlock the %s board" % board_name)
		elif objective is Survive:
			parts.append("Survive with %d autodropper(s)" % objective.autodropper_count)
		elif objective is GetSameBucketXTimes:
			if objective.in_a_row:
				parts.append("Hit the same bucket %d times in a row" % objective.times)
			else:
				parts.append("Hit the same bucket %d times" % objective.times)
		elif objective is HitXBucketYTimes:
			parts.append("Land a coin in the target bucket %d times" % objective.times)
		elif objective is LandInEveryBucket:
			parts.append("Land in every bucket")
		elif objective is EarnWithinXDrops:
			var currency_name: String = Enums.CurrencyType.keys()[objective.currency_type].to_lower().replace("_", " ")
			parts.append("Earn %d %s in %d drops" % [objective.amount, currency_name, objective.max_drops])
	return "\n".join(parts)


func get_objective_progress() -> String:
	if not is_active_challenge:
		return ""
	var parts: PackedStringArray = []
	for objective in _challenge.objectives:
		if objective is GetSameBucketXTimes:
			var best: int = 0
			for key in _bucket_hits:
				if key.begins_with("%d_" % objective.board_type):
					best = maxi(best, _bucket_hits[key])
			parts.append("%d / %d" % [best, objective.times])
		elif objective is HitXBucketYTimes:
			var key := "%d_%d" % [objective.board_type, objective.bucket_index]
			var hits: int = _bucket_hits.get(key, 0)
			parts.append("%d / %d" % [hits, objective.times])
	return "\n".join(parts)


static func get_constraint_text(challenge: ChallengeData) -> String:
	var parts: PackedStringArray = []
	for constraint in challenge.constraints:
		if constraint is NeverMoreThanXCoins:
			var currency_name: String = Enums.CurrencyType.keys()[constraint.currency_type].to_lower().replace("_", " ")
			parts.append("Never have more than %d %s" % [constraint.amount, currency_name])
		elif constraint is NeverLessThanXCoins:
			var currency_name: String = Enums.CurrencyType.keys()[constraint.currency_type].to_lower().replace("_", " ")
			parts.append("Never have less than %d %s" % [constraint.amount, currency_name])
		elif constraint is NeverTouchBucket:
			parts.append("Never land in bucket %d" % constraint.bucket_index)
		elif constraint is UpgradesLimited:
			if constraint.all_upgrades:
				parts.append("No upgrades")
			else:
				var names: PackedStringArray = []
				for ut in constraint.blocked_upgrades:
					names.append(Enums.UpgradeType.keys()[ut].to_lower().replace("_", " "))
				parts.append("No %s upgrades" % ", ".join(names))
		elif constraint is OnlyOneBoard:
			var board_name: String = Enums.BoardType.keys()[constraint.board_type].to_lower()
			parts.append("Only %s board" % board_name)
	if parts.is_empty():
		return "None"
	return "\n".join(parts)


static func get_objective_text_for(challenge: ChallengeData) -> String:
	var parts: PackedStringArray = []
	for objective in challenge.objectives:
		if objective is CoinGoal:
			var currency_name: String = Enums.CurrencyType.keys()[objective.currency_type].to_lower().replace("_", " ")
			if objective.exact:
				parts.append("Get exactly %d %s" % [objective.amount, currency_name])
			else:
				parts.append("Earn %d %s" % [objective.amount, currency_name])
		elif objective is BoardGoal:
			var board_name: String = Enums.BoardType.keys()[objective.board_type].to_lower()
			parts.append("Unlock the %s board" % board_name)
		elif objective is Survive:
			parts.append("Survive with %d autodropper(s)" % objective.autodropper_count)
		elif objective is GetSameBucketXTimes:
			if objective.in_a_row:
				parts.append("Hit the same bucket %d times in a row" % objective.times)
			else:
				parts.append("Hit the same bucket %d times" % objective.times)
		elif objective is HitXBucketYTimes:
			parts.append("Land a coin in the target bucket %d times" % objective.times)
		elif objective is LandInEveryBucket:
			parts.append("Land in every bucket")
		elif objective is EarnWithinXDrops:
			var currency_name: String = Enums.CurrencyType.keys()[objective.currency_type].to_lower().replace("_", " ")
			parts.append("Earn %d %s in %d drops" % [objective.amount, currency_name, objective.max_drops])
	return "\n".join(parts)


func clear_challenge() -> void:
	is_active_challenge = false
	_challenge = null
	_time_remaining = 0.0
	_total_drops = 0
	_bucket_hits.clear()
	_last_bucket.clear()
	_same_bucket_streak.clear()
	_survive_passed = false

	# Clear gates
	UpgradeManager.upgrade_gate = Callable()
	if _board_manager:
		_board_manager.board_gate = Callable()

	# Disconnect signals
	if CurrencyManager.currency_changed.is_connected(_on_currency_changed):
		CurrencyManager.currency_changed.disconnect(_on_currency_changed)
	if _board_manager:
		if _board_manager.board_switched.is_connected(_on_board_switched):
			_board_manager.board_switched.disconnect(_on_board_switched)
		for board in _board_manager.get_boards():
			if board.coin_landed.is_connected(_on_coin_landed):
				board.coin_landed.disconnect(_on_coin_landed)
			if board.autodrop_failed.is_connected(_on_autodrop_failed):
				board.autodrop_failed.disconnect(_on_autodrop_failed)
			for conn in board.board_rebuilt.get_connections():
				if conn["callable"].get_method() == "_on_board_rebuilt":
					board.board_rebuilt.disconnect(conn["callable"])
	_board_manager = null
