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
	LevelManager.reconcile_reward.connect(_on_reconcile_reward)
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


## Effective ceiling on an upgrade's level. 0 means uncapped.
##
## This is `current_cap` folded together with any HARD cap. current_cap can be
## RAISED by the cap-raise system, so a hard ceiling expressed only as
## BaseUpgradeData.max_level would evaporate after enough cap raises. Every
## purchasability gate (can_buy, can_buy_cap_raise, force_apply, UpgradeRow)
## reads this one function so they cannot disagree.
func get_max_level(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> int:
	var cap: int = _state[board_type][upgrade_type].current_cap
	var hard: int = _hard_cap(upgrade_type)
	if hard < 0:
		return cap
	if cap <= 0:
		return hard
	return mini(cap, hard)


## Hard ceiling for an upgrade type, or -1 when it has none.
##
## ADD_ROW is the only one: once a board's earrings meet at the centre there is
## nothing left for the upgrade to grow. Only applies when earrings are enabled
## — an uncapped challenge board keeps today's unbounded cap-raise behaviour.
func _hard_cap(upgrade_type: Enums.UpgradeType) -> int:
	if upgrade_type != Enums.UpgradeType.ADD_ROW:
		return -1
	if not ChallengeManager.boards_grow_earrings():
		return -1
	return EarringGeometry.max_add_row_level()


## True when this upgrade's current cap has already reached its hard ceiling, so
## buying a cap raise would raise a cap that can never be spent — a wasted-spend
## soft-lock if left enabled.
func is_at_hard_cap(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	var hard: int = _hard_cap(upgrade_type)
	return hard >= 0 and _state[board_type][upgrade_type].current_cap >= hard


func get_state(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> UpgradeState:
	return _state[board_type][upgrade_type]


func is_unlocked(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	return _unlocked[board_type][upgrade_type]


## RETIRED upgrades can never be unlocked, by save restore or by reward.
##
## NEITHER half of a retired upgrade may be deleted, for two DIFFERENT reasons:
##   - Its .tres registration (data/advanced_autodropper.tres) stays because
##     deserialize() indexes _state[board][type] for every Enums.UpgradeType.
##     Unregistering it would CRASH any save that recorded the key.
##   - Its enum VALUE stays because UpgradeType ordinals are persisted as ints —
##     by .tres files (peg_deflector.tres hardcodes `type = 6`) and by
##     ChallengeProgressManager's permanent_upgrades blob. Deleting ordinal 5
##     would silently renumber PEG_DEFLECTOR 6 -> 5 and repoint both at the wrong
##     upgrade. That one corrupts data instead of crashing, so it is the more
##     dangerous of the two.
##
## Refusing the unlock is what actually makes a retired upgrade unreachable.
## _clear_retired_state() then drops any level/cost an old save carried, so
## nothing can recompute a pool from it later.
const RETIRED_UPGRADES: Array[Enums.UpgradeType] = [
	Enums.UpgradeType.ADVANCED_AUTODROPPER,
]


func is_retired(upgrade_type: Enums.UpgradeType) -> bool:
	return upgrade_type in RETIRED_UPGRADES


## Zeroes every board's stored state for retired upgrades. Called at the end of
## deserialize so an old save's purchased levels can't be read back by anything
## that derives a value from upgrade level (e.g. BoardManager's legacy
## normal_pool fallback), and so they stop being re-serialized.
func _clear_retired_state() -> void:
	for upgrade_type in RETIRED_UPGRADES:
		for board_type in Enums.BoardType.values():
			var s: UpgradeState = _state[board_type][upgrade_type]
			s.level = 0
			s.cap_level = 0
			s.current_cap = s.base_cap
			_unlocked[board_type][upgrade_type] = false


func unlock(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> void:
	if is_retired(upgrade_type):
		_unlocked[board_type][upgrade_type] = false
		return
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

	# get_max_level of 0 means uncapped
	var max_level: int = get_max_level(board_type, upgrade_type)
	if max_level > 0 and state.level >= max_level:
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


## Grants a level with no cost and no unlock check (StartingUpgrades, prestige
## rewards). Still honours the hard cap — past it the level would be unbuildable
## geometry, not just an unaffordable purchase.
func force_apply(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> void:
	var state: UpgradeState = _state[board_type][upgrade_type]
	var hard: int = _hard_cap(upgrade_type)
	if hard >= 0 and state.level >= hard:
		return
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


func _on_reconcile_reward(reward: RewardData) -> void:
	if reward.type == RewardData.RewardType.UNLOCK_UPGRADE:
		unlock(reward.board_type, reward.upgrade_type)


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
	# Nor past a hard ceiling — the raise would buy a level that can never be
	# purchased, spending higher-tier currency for nothing.
	if is_at_hard_cap(board_type, upgrade_type):
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


func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
	# Cap raises are no longer unlocked by earning a raw currency. They are now
	# enabled explicitly via enable_cap_raise() on the 2nd board-completion beat
	# (see PlinkoBoard._on_final_bounce_started).
	pass


## Enables cap raises for a board (its caps can now be raised with the next tier's
## currency). Called on the 2nd board completion, BEFORE cap_raise_coin_landed is
## emitted so the reveal animator sees is_cap_raise_available() == true.
func enable_cap_raise(board_type: Enums.BoardType) -> void:
	if _cap_raise_available[board_type]:
		return
	_cap_raise_available[board_type] = true
	cap_raise_unlocked.emit(board_type)


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

	# Last: an old save may carry levels for an upgrade that has since been
	# retired. unlock() already refused the flag; this drops the rest.
	_clear_retired_state()


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
