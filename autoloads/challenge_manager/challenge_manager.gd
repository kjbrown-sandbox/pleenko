extends Node
## Manages the challenge lifecycle: setting up conditions, providing text for
## the HUD, and gating upgrades/boards. Delegates active challenge tracking
## to a ChallengeTracker child node.

signal challenge_completed
signal challenge_failed(reason: String)

var is_active_challenge: bool = false
var _challenge: ChallengeData
var _board_manager: BoardManager
var _tracker: ChallengeTracker


func set_challenge(challenge: ChallengeData) -> void:
	_challenge = challenge
	is_active_challenge = true


func get_challenge() -> ChallengeData:
	return _challenge


func get_time_remaining() -> float:
	return _tracker.time_remaining if _tracker else 0.0


func get_total_drops() -> int:
	return _tracker.get_total_drops() if _tracker else 0


func get_time_taken() -> float:
	return _tracker.get_time_taken() if _tracker else 0.0


func has_failed() -> bool:
	return _tracker._has_failed if _tracker else false


# ── Setup ─────────────────────────────────────────────────────────

func setup(board_manager: BoardManager) -> void:
	_board_manager = board_manager

	# Reset currency to starting state
	CurrencyManager.reset()

	# Set gates on other managers
	UpgradeManager.upgrade_gate = is_upgrade_allowed
	_board_manager.board_gate = is_board_allowed

	# Apply starting conditions before tracker connects
	_apply_starting_conditions()

	# Create and start the tracker
	_tracker = ChallengeTracker.new()
	_tracker.setup(_challenge, _board_manager)
	_tracker.completed.connect(func(): challenge_completed.emit())
	_tracker.failed.connect(func(reason: String): challenge_failed.emit(reason))
	add_child(_tracker)

	# Connect tracker to all boards (including any created by starting conditions)
	_tracker.connect_to_boards()
	_tracker.mark_initial_visuals()

	# Survive objectives now drive their own timing inside the tracker. The
	# tracker calls activate_survive_autodroppers() when phase 1 begins, so
	# nothing needs to happen here at challenge start.


# ── Starting conditions ──────────────────────────────────────────

func _apply_starting_conditions() -> void:
	# Apply caps first so coins aren't truncated
	for condition in _challenge.starting_conditions:
		if condition is StartingCap:
			CurrencyManager.caps[condition.currency_type] = condition.cap

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
		elif condition is StartingDropDelay:
			var board := _get_board(condition.board_type)
			if board:
				board.drop_delay = condition.drop_delay

	# Apply STARTING_MODIFIER rewards earned from previously-completed challenges.
	# Other modifier types (MULTI_DROP, ADVANCED_COIN_MULTIPLIER, BUCKET_VALUE_PERCENT)
	# are consumed directly by the board on setup via the ChallengeProgressManager getters.
	for mod in ChallengeProgressManager.get_starting_modifiers():
		if mod.modifier_type == ChallengeRewardData.ModifierType.STARTING_COINS:
			CurrencyManager.add(mod.currency_type, int(mod.modifier_amount))


## Called by ChallengeTracker when the survive challenge transitions from the
## WAITING phase to the SURVIVING phase. This is the moment the orange board's
## autodroppers should appear and start dropping.
func activate_survive_autodroppers(objective: Survive) -> void:
	if not is_active_challenge:
		return
	var board := _get_board(objective.board_type)
	if not board:
		return

	# Create the autodropper pool if needed and reveal the UI on every board.
	var needed: int = objective.autodropper_count - _board_manager.get_free_autodroppers()
	for i in needed:
		UpgradeManager.force_apply(Enums.BoardType.GOLD, Enums.UpgradeType.AUTODROPPER)
	_board_manager._on_autodropper_unlocked()

	# Assign the autodroppers to this board, bypassing the player gate.
	var normal_id := StringName("%s_NORMAL" % Enums.BoardType.keys()[objective.board_type])
	for i in objective.autodropper_count:
		_board_manager._on_autodropper_adjust(normal_id, 1, false)


# ── Gates ─────────────────────────────────────────────────────────

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


# ── Text for HUD ──────────────────────────────────────────────────

func get_objective_text() -> String:
	return get_objective_text_for(_challenge)


func get_objective_progress() -> String:
	if not is_active_challenge or not _tracker:
		return ""
	return _tracker.get_progress_text()


static func get_constraint_text(challenge: ChallengeData) -> String:
	var parts: PackedStringArray = []
	for constraint in challenge.constraints:
		parts.append(constraint.get_text())
	if parts.is_empty():
		return "None"
	return "\n".join(parts)


static func get_objective_text_for(challenge: ChallengeData) -> String:
	var parts: PackedStringArray = []
	for objective in challenge.objectives:
		parts.append(objective.get_text())
	return "\n".join(parts)


# ── Teardown ──────────────────────────────────────────────────────

func clear_challenge() -> void:
	is_active_challenge = false
	_challenge = null

	# Clear gates
	UpgradeManager.upgrade_gate = Callable()
	if _board_manager:
		_board_manager.board_gate = Callable()

	# Clean up tracker
	if _tracker:
		_tracker.disconnect_all()
		_tracker.queue_free()
		_tracker = null

	_board_manager = null


# ── Utilities ─────────────────────────────────────────────────────

func _get_board(board_type: Enums.BoardType) -> PlinkoBoard:
	if not _board_manager:
		return null
	for board in _board_manager.get_boards():
		if board.board_type == board_type:
			return board
	return null
