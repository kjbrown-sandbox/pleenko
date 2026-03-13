extends Node

enum UpgradeType {
	ADD_ROW,
	BUCKET_VALUE,
	DROP_RATE,
	QUEUE,
}

## Maps UpgradeType enum values to the string IDs used in .tres data files.
const UPGRADE_IDS: Dictionary = {
	UpgradeType.ADD_ROW: "add_row",
	UpgradeType.BUCKET_VALUE: "bucket_value",
	UpgradeType.DROP_RATE: "drop_rate",
	UpgradeType.QUEUE: "queue",
}

class UpgradeState:
	var level: int = 0
	var cost: int = 0
	var delta: int = 0
	var max_level: int = 0  ## 0 = uncapped; mutable for cap raises

signal upgrade_purchased(upgrade_id, board_type, new_level)

## Populate this array in the Inspector with .tres BaseUpgradeData resources.
@export var upgrades: Array[BaseUpgradeData] = []

## Per-board, per-upgrade runtime state.
var _state: Dictionary = {}  # BoardType -> upgrade_id -> UpgradeState

## Quick lookup: upgrade_id -> BaseUpgradeData
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
			s.max_level = data.max_level
			_state[board_type][data.id] = s

	# Debug: print initial state
	for board_type in _state:
		var board_name: String = Enums.BoardType.keys()[board_type]
		for upgrade_id in _state[board_type]:
			var s: UpgradeState = _state[board_type][upgrade_id]
			print("[UpgradeManager] %s/%s — level=%d cost=%d" % [
				board_name, upgrade_id, s.level, s.cost
			])


func get_upgrade(id: String) -> BaseUpgradeData:
	return _upgrade_map.get(id)


func get_level(board_type: Enums.BoardType, upgrade_id: String) -> int:
	return _state[board_type][upgrade_id].level


func get_cost(board_type: Enums.BoardType, upgrade_id: String) -> int:
	return _state[board_type][upgrade_id].cost


func get_max_level(board_type: Enums.BoardType, upgrade_id: String) -> int:
	return _state[board_type][upgrade_id].max_level


func get_state(board_type: Enums.BoardType, upgrade_id: String) -> UpgradeState:
	return _state[board_type][upgrade_id]


func can_buy(board_type: Enums.BoardType, upgrade_id: String) -> bool:
	var state: UpgradeState = _state[board_type][upgrade_id]

	# max_level of 0 means uncapped
	if state.max_level > 0 and state.level >= state.max_level:
		return false

	var currency := _currency_for_board(board_type)
	return CurrencyManager.can_afford(currency, state.cost)


func buy(board_type: Enums.BoardType, upgrade_id: String) -> bool:
	if not can_buy(board_type, upgrade_id):
		return false

	var state: UpgradeState = _state[board_type][upgrade_id]

	var currency := _currency_for_board(board_type)
	CurrencyManager.spend(currency, state.cost)

	state.level += 1
	_advance_cost(board_type, upgrade_id)

	upgrade_purchased.emit(upgrade_id, board_type, state.level)
	return true


func _currency_for_board(board_type: Enums.BoardType) -> Enums.CurrencyType:
	match board_type:
		Enums.BoardType.GOLD:
			return Enums.CurrencyType.GOLD_COIN
		Enums.BoardType.ORANGE:
			return Enums.CurrencyType.ORANGE_COIN
		Enums.BoardType.RED:
			return Enums.CurrencyType.RED_COIN
		_:
			return Enums.CurrencyType.GOLD_COIN


func _advance_cost(board_type: Enums.BoardType, upgrade_id: String) -> void:
	var upgrade_state: UpgradeState = _state[board_type][upgrade_id]
	var data: BaseUpgradeData = _upgrade_map[upgrade_id]

	match data.cost_type:
		BaseUpgradeData.CostType.ADDITIVE:
			upgrade_state.cost += upgrade_state.delta
		BaseUpgradeData.CostType.ADDITIVE_ESCALATING:
			upgrade_state.cost += upgrade_state.delta
			upgrade_state.delta += data.delta_escalation
		BaseUpgradeData.CostType.MULTIPLICATIVE:
			upgrade_state.cost = int(upgrade_state.cost * data.cost_multiplier)
