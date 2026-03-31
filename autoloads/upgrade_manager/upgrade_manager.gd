extends Node

class UpgradeState:
	var level: int = 0
	var cost: int = 0
	var delta: int = 0
	var base_cap: int = 0     ## from BaseUpgradeData.max_level; 0 = uncapped
	var current_cap: int = 0  ## starts at base_cap; raised by cap upgrades
	var cap_level: int = 0    ## number of cap raises purchased

signal upgrade_purchased(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType, new_level: int)
signal upgrade_unlocked(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType)
signal cap_raise_unlocked(board_type: Enums.BoardType)
signal autodropper_unlocked

## Populate this array in the Inspector with .tres BaseUpgradeData resources.
@export var upgrades: Array[BaseUpgradeData] = []

## Optional gate callable: Callable(upgrade_type: Enums.UpgradeType) -> bool
## Set by ChallengeManager to block upgrades during challenges.
var upgrade_gate: Callable

## Per-board, per-upgrade runtime state.
var _state: Dictionary = {}  # BoardType -> UpgradeType -> UpgradeState

## Quick lookup: UpgradeType -> BaseUpgradeData
var _upgrade_map: Dictionary = {}

## Tracks which upgrades are unlocked per board.
var _unlocked: Dictionary = {}  # BoardType -> UpgradeType -> bool

## Tracks whether cap raising is available per board (next board must be unlocked).
var _cap_raise_available: Dictionary = {}  # BoardType -> bool


func _ready() -> void:
	# Build lookup map
	for data in upgrades:
		_upgrade_map[data.type] = data

	_init_state()

	# Listen for level rewards to unlock upgrades
	LevelManager.rewards_claimed.connect(_on_rewards_claimed)
	CurrencyManager.currency_changed.connect(_on_currency_changed)


func _init_state() -> void:
	for board_type in Enums.BoardType.values():
		_state[board_type] = {}
		_unlocked[board_type] = {}
		_cap_raise_available[board_type] = false
		for data in upgrades:
			var s := UpgradeState.new()
			s.cost = data.base_cost
			s.delta = data.cost_delta
			s.base_cap = data.max_level
			s.current_cap = data.max_level
			_state[board_type][data.type] = s
			_unlocked[board_type][data.type] = false


func reset() -> void:
	_init_state()

	# Debug: print initial state
	for board_type in _state:
		var board_name: String = Enums.BoardType.keys()[board_type]
		for upgrade_type in _state[board_type]:
			var s: UpgradeState = _state[board_type][upgrade_type]
			var upgrade_name: String = Enums.UpgradeType.keys()[upgrade_type]
			print("[UpgradeManager] %s/%s — level=%d cost=%d" % [
				board_name, upgrade_name, s.level, s.cost
			])


func get_upgrade(upgrade_type: Enums.UpgradeType) -> BaseUpgradeData:
	return _upgrade_map.get(upgrade_type)


func get_level(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> int:
	return _state[board_type][upgrade_type].level


func get_cost(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> int:
	return _state[board_type][upgrade_type].cost


func get_max_level(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> int:
	return _state[board_type][upgrade_type].current_cap


func get_state(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> UpgradeState:
	return _state[board_type][upgrade_type]


func is_unlocked(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	return _unlocked[board_type][upgrade_type]


func unlock(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> void:
	if _unlocked[board_type][upgrade_type]:
		return
	_unlocked[board_type][upgrade_type] = true
	upgrade_unlocked.emit(upgrade_type, board_type)
	print("[UpgradeManager] Unlocked %s on %s" % [
		Enums.UpgradeType.keys()[upgrade_type],
		Enums.BoardType.keys()[board_type]
	])


func can_buy(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	if upgrade_gate.is_valid() and not upgrade_gate.call(upgrade_type):
		return false
	if not is_unlocked(board_type, upgrade_type):
		return false

	var state: UpgradeState = _state[board_type][upgrade_type]

	# current_cap of 0 means uncapped
	if state.current_cap > 0 and state.level >= state.current_cap:
		return false

	var currency := TierRegistry.primary_currency(board_type)
	return CurrencyManager.can_afford(currency, state.cost)


func buy(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	if not can_buy(board_type, upgrade_type):
		return false

	var state: UpgradeState = _state[board_type][upgrade_type]

	var currency := TierRegistry.primary_currency(board_type)
	CurrencyManager.spend(currency, state.cost)

	state.level += 1
	_advance_cost(board_type, upgrade_type)

	upgrade_purchased.emit(upgrade_type, board_type, state.level)
	return true


func force_apply(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> void:
	var state: UpgradeState = _state[board_type][upgrade_type]
	state.level += 1
	_advance_cost(board_type, upgrade_type)
	upgrade_purchased.emit(upgrade_type, board_type, state.level)


func _on_rewards_claimed(_level: int, rewards: Array[RewardData]) -> void:
	for reward in rewards:
		if reward.type == RewardData.RewardType.UNLOCK_UPGRADE:
			if ChallengeManager.is_active_challenge and not ChallengeManager.is_upgrade_allowed(reward.upgrade_type):
				continue
			unlock(reward.board_type, reward.upgrade_type)
		elif reward.type == RewardData.RewardType.UNLOCK_AUTODROPPER:
			autodropper_unlocked.emit()


func is_cap_raise_available(board_type: Enums.BoardType) -> bool:
	return _cap_raise_available[board_type]


func get_cap_raise_cost(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> int:
	var state: UpgradeState = _state[board_type][upgrade_type]
	return 1 + 2 * state.cap_level


func can_buy_cap_raise(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	if not _cap_raise_available[board_type]:
		return false
	var state: UpgradeState = _state[board_type][upgrade_type]
	# Can't raise cap on uncapped upgrades
	if state.base_cap == 0:
		return false
	var currency: int = TierRegistry.cap_raise_currency(board_type)
	if currency == -1:
		return false
	return CurrencyManager.can_afford(currency, get_cap_raise_cost(board_type, upgrade_type))


func buy_cap_raise(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	if not can_buy_cap_raise(board_type, upgrade_type):
		return false
	var state: UpgradeState = _state[board_type][upgrade_type]
	var currency: int = TierRegistry.cap_raise_currency(board_type)
	CurrencyManager.spend(currency, get_cap_raise_cost(board_type, upgrade_type))
	state.current_cap += 1
	state.cap_level += 1
	upgrade_purchased.emit(upgrade_type, board_type, state.level)
	return true


func _on_currency_changed(type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
	if _new_balance <= 0:
		return
	# When a raw currency is earned, enable cap raises for the previous tier's board.
	# e.g. earning RAW_ORANGE enables cap raises on GOLD board.
	for i in range(1, TierRegistry.get_tier_count()):
		var tier := TierRegistry.get_tier_by_index(i)
		if tier.raw_currency == type:
			var prev := TierRegistry.get_tier_by_index(i - 1)
			if prev and not _cap_raise_available[prev.board_type]:
				_cap_raise_available[prev.board_type] = true
				cap_raise_unlocked.emit(prev.board_type)


func serialize() -> Dictionary:
	var data := {}

	# Serialize per-board, per-upgrade state
	var state_data := {}
	for board_type in _state:
		var board_key: String = Enums.BoardType.keys()[board_type]
		state_data[board_key] = {}
		for upgrade_type in _state[board_type]:
			var upgrade_key: String = Enums.UpgradeType.keys()[upgrade_type]
			var s: UpgradeState = _state[board_type][upgrade_type]
			state_data[board_key][upgrade_key] = {
				"level": s.level,
				"cost": s.cost,
				"delta": s.delta,
				"current_cap": s.current_cap,
				"cap_level": s.cap_level,
			}
	data["state"] = state_data

	# Serialize unlocks
	var unlocked_data := {}
	for board_type in _unlocked:
		var board_key: String = Enums.BoardType.keys()[board_type]
		unlocked_data[board_key] = {}
		for upgrade_type in _unlocked[board_type]:
			var upgrade_key: String = Enums.UpgradeType.keys()[upgrade_type]
			unlocked_data[board_key][upgrade_key] = _unlocked[board_type][upgrade_type]
	data["unlocked"] = unlocked_data

	# Serialize cap raise availability
	var cap_raise_data := {}
	for board_type in _cap_raise_available:
		var board_key: String = Enums.BoardType.keys()[board_type]
		cap_raise_data[board_key] = _cap_raise_available[board_type]
	data["cap_raise_available"] = cap_raise_data

	return data


func deserialize(data: Dictionary) -> void:
	# Restore per-board, per-upgrade state
	var state_data: Dictionary = data.get("state", {})
	for board_type in Enums.BoardType.values():
		var board_key: String = Enums.BoardType.keys()[board_type]
		if board_key not in state_data:
			continue
		for upgrade_type in Enums.UpgradeType.values():
			var upgrade_key: String = Enums.UpgradeType.keys()[upgrade_type]
			if upgrade_key not in state_data[board_key]:
				continue
			var entry: Dictionary = state_data[board_key][upgrade_key]
			var s: UpgradeState = _state[board_type][upgrade_type]
			s.level = entry.get("level", 0)
			s.cost = entry.get("cost", 0)
			s.delta = entry.get("delta", 0)
			s.current_cap = entry.get("current_cap", s.base_cap)
			s.cap_level = entry.get("cap_level", 0)

	# Restore unlocks
	var unlocked_data: Dictionary = data.get("unlocked", {})
	for board_type in Enums.BoardType.values():
		var board_key: String = Enums.BoardType.keys()[board_type]
		if board_key not in unlocked_data:
			continue
		for upgrade_type in Enums.UpgradeType.values():
			var upgrade_key: String = Enums.UpgradeType.keys()[upgrade_type]
			if upgrade_key not in unlocked_data[board_key]:
				continue
			if unlocked_data[board_key][upgrade_key]:
				unlock(board_type, upgrade_type)

	# Restore cap raise availability
	var cap_raise_data: Dictionary = data.get("cap_raise_available", {})
	for board_type in Enums.BoardType.values():
		var board_key: String = Enums.BoardType.keys()[board_type]
		if board_key in cap_raise_data and cap_raise_data[board_key]:
			_cap_raise_available[board_type] = true
			cap_raise_unlocked.emit(board_type)


func _advance_cost(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> void:
	var upgrade_state: UpgradeState = _state[board_type][upgrade_type]
	var data: BaseUpgradeData = _upgrade_map[upgrade_type]

	match data.cost_type:
		BaseUpgradeData.CostType.ADDITIVE:
			upgrade_state.cost += upgrade_state.delta
		BaseUpgradeData.CostType.ADDITIVE_ESCALATING:
			upgrade_state.cost += upgrade_state.delta
			upgrade_state.delta += data.delta_escalation
		BaseUpgradeData.CostType.MULTIPLICATIVE:
			upgrade_state.cost = int(upgrade_state.cost * data.cost_multiplier)
