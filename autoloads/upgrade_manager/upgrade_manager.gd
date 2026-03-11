extends Node

class UpgradeState:
	var level: int = 0
	var cost: int = 0
	var delta: int = 0

signal upgrade_purchased(upgrade_id, board_type, new_level)

## Populate this array in the Inspector with .tres UpgradeData resources.
@export var upgrades: Array[UpgradeData] = []

## Per-board, per-upgrade runtime state.
var _state: Dictionary = {}  # BoardType -> upgrade_id -> UpgradeState

## Quick lookup: upgrade_id -> UpgradeData
var _upgrade_map: Dictionary = {}


func _ready() -> void:
	# Build lookup map
	for data in upgrades:
		_upgrade_map[data.id] = data

	# Initialize state for every board + upgrade combination
	for board_type in Enums.BoardType.values():
		_state[board_type] = {}
		for data in upgrades:
			var s := UpgradeState.new()
			s.cost = data.base_cost
			s.delta = data.cost_delta
			_state[board_type][data.id] = s

	# Debug: print initial state
	for board_type in _state:
		var board_name: String = Enums.BoardType.keys()[board_type]
		for upgrade_id in _state[board_type]:
			var s: UpgradeState = _state[board_type][upgrade_id]
			print("[UpgradeManager] %s/%s — level=%d cost=%d" % [
				board_name, upgrade_id, s.level, s.cost
			])


func get_upgrade(id: String) -> UpgradeData:
	return _upgrade_map.get(id)


func get_level(board_type: Enums.BoardType, upgrade_id: String) -> int:
	return _state[board_type][upgrade_id].level


func get_cost(board_type: Enums.BoardType, upgrade_id: String) -> int:
	return _state[board_type][upgrade_id].cost


func get_max_level(upgrade_id: String) -> int:
	return _upgrade_map[upgrade_id].max_level


func can_buy(board_type: Enums.BoardType, upgrade_id: String) -> bool:
	var data: UpgradeData = _upgrade_map[upgrade_id]
	var level: int = _state[board_type][upgrade_id].level

	# max_level of 0 means uncapped
	if data.max_level > 0 and level >= data.max_level:
		return false

	# TODO: check CurrencyManager.can_afford() once it exists
	return true


func buy(board_type: Enums.BoardType, upgrade_id: String) -> bool:
	if not can_buy(board_type, upgrade_id):
		return false

	var state: UpgradeState = _state[board_type][upgrade_id]
	var data: UpgradeData = _upgrade_map[upgrade_id]

	# TODO: CurrencyManager.spend(currency, state.cost)

	state.level += 1
	_advance_cost(board_type, upgrade_id)

	# TODO: apply effect based on upgrade_id

	upgrade_purchased.emit(upgrade_id, board_type, state.level)
	return true


func _advance_cost(board_type: Enums.BoardType, upgrade_id: String) -> void:
	var upgrade_state: UpgradeState = _state[board_type][upgrade_id]
	var data: UpgradeData = _upgrade_map[upgrade_id]

	match data.cost_type:
		UpgradeData.CostType.ADDITIVE:
			upgrade_state.cost += upgrade_state.delta
		UpgradeData.CostType.ADDITIVE_ESCALATING:
			upgrade_state.cost += upgrade_state.delta
			upgrade_state.delta += data.delta_escalation
		UpgradeData.CostType.MULTIPLICATIVE:
			upgrade_state.cost = int(upgrade_state.cost * data.cost_multiplier)
