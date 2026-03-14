extends Node

class UpgradeState:
	var level: int = 0
	var cost: int = 0
	var delta: int = 0
	var max_level: int = 0  ## 0 = uncapped; mutable for cap raises

signal upgrade_purchased(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType, new_level: int)
signal upgrade_unlocked(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType)

## Populate this array in the Inspector with .tres BaseUpgradeData resources.
@export var upgrades: Array[BaseUpgradeData] = []

## Per-board, per-upgrade runtime state.
var _state: Dictionary = {}  # BoardType -> UpgradeType -> UpgradeState

## Quick lookup: UpgradeType -> BaseUpgradeData
var _upgrade_map: Dictionary = {}

## Tracks which upgrades are unlocked per board.
var _unlocked: Dictionary = {}  # BoardType -> UpgradeType -> bool


func _ready() -> void:
	# Build lookup map
	for data in upgrades:
		_upgrade_map[data.type] = data

	# Initialize state and unlock tracking for every board + upgrade combination
	for board_type in Enums.BoardType.values():
		_state[board_type] = {}
		_unlocked[board_type] = {}
		for data in upgrades:
			var s := UpgradeState.new()
			s.cost = data.base_cost
			s.delta = data.cost_delta
			s.max_level = data.max_level
			_state[board_type][data.type] = s
			_unlocked[board_type][data.type] = false

	# Listen for level rewards to unlock upgrades
	LevelManager.rewards_claimed.connect(_on_rewards_claimed)

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
	return _state[board_type][upgrade_type].max_level


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
	if not is_unlocked(board_type, upgrade_type):
		return false

	var state: UpgradeState = _state[board_type][upgrade_type]

	# max_level of 0 means uncapped
	if state.max_level > 0 and state.level >= state.max_level:
		return false

	var currency := Enums.currency_for_board(board_type)
	return CurrencyManager.can_afford(currency, state.cost)


func buy(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	if not can_buy(board_type, upgrade_type):
		return false

	var state: UpgradeState = _state[board_type][upgrade_type]

	var currency := Enums.currency_for_board(board_type)
	CurrencyManager.spend(currency, state.cost)

	state.level += 1
	_advance_cost(board_type, upgrade_type)

	upgrade_purchased.emit(upgrade_type, board_type, state.level)
	return true


func _on_rewards_claimed(_level: int, rewards: Array[RewardData]) -> void:
	for reward in rewards:
		if reward.type == RewardData.RewardType.UNLOCK_UPGRADE:
			unlock(reward.board_type, reward.upgrade_type)


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
