extends Node

## The ordered tier chain. Index 0 is always the starting tier (gold).
@export var tiers: Array[TierData] = []

# Lookup tables built in _ready()
var _by_board: Dictionary = {}        # BoardType -> TierData
var _by_primary: Dictionary = {}      # CurrencyType -> TierData
var _by_raw: Dictionary = {}          # CurrencyType (raw) -> TierData
var _index_of: Dictionary = {}        # BoardType -> int

const BASE_DROP_DELAY := 2.0


func _ready() -> void:
	_rebuild_lookups()


func _rebuild_lookups() -> void:
	_by_board.clear()
	_by_primary.clear()
	_by_raw.clear()
	_index_of.clear()
	for i in tiers.size():
		var tier := tiers[i]
		_by_board[tier.board_type] = tier
		_by_primary[tier.primary_currency] = tier
		_index_of[tier.board_type] = i
		if tier.raw_currency >= 0:
			_by_raw[tier.raw_currency] = tier


# ── Tier lookups ────────────────────────────────────────────────────

func get_tier(board_type: Enums.BoardType) -> TierData:
	return _by_board.get(board_type)


func get_tier_by_index(index: int) -> TierData:
	if index < 0 or index >= tiers.size():
		return null
	return tiers[index]


func get_tier_index(board_type: Enums.BoardType) -> int:
	return _index_of.get(board_type, -1)


func get_tier_count() -> int:
	return tiers.size()


func get_previous_tier(board_type: Enums.BoardType) -> TierData:
	var idx: int = _index_of.get(board_type, -1)
	if idx <= 0:
		return null
	return tiers[idx - 1]


func get_next_tier(board_type: Enums.BoardType) -> TierData:
	var idx: int = _index_of.get(board_type, -1)
	if idx < 0 or idx >= tiers.size() - 1:
		return null
	return tiers[idx + 1]


func has_next_tier(board_type: Enums.BoardType) -> bool:
	return get_next_tier(board_type) != null


func is_starting_tier(board_type: Enums.BoardType) -> bool:
	return _index_of.get(board_type, -1) == 0


# ── Currency lookups ────────────────────────────────────────────────

func primary_currency(board_type: Enums.BoardType) -> int:
	var tier := get_tier(board_type)
	return tier.primary_currency if tier else -1


func raw_currency(board_type: Enums.BoardType) -> int:
	var tier := get_tier(board_type)
	return tier.raw_currency if tier else -1


func advanced_bucket_currency(board_type: Enums.BoardType) -> int:
	var next := get_next_tier(board_type)
	return next.raw_currency if next else -1


func cap_raise_currency(board_type: Enums.BoardType) -> int:
	var next := get_next_tier(board_type)
	return next.primary_currency if next else -1


func get_tier_for_currency(currency_type: int) -> TierData:
	if currency_type in _by_primary:
		return _by_primary[currency_type]
	if currency_type in _by_raw:
		return _by_raw[currency_type]
	return null


func is_raw_currency(currency_type: int) -> bool:
	return currency_type in _by_raw


# ── Drop costs ──────────────────────────────────────────────────────

func get_drop_costs(board_type: Enums.BoardType) -> Array:
	var tier := get_tier(board_type)
	if not tier:
		return []
	var idx: int = _index_of[board_type]

	# Tier 0 (gold): just 1 of its own primary currency
	if idx == 0:
		return [[tier.primary_currency, 1]]

	var prev := tiers[idx - 1]
	var costs: Array = [[tier.raw_currency, 1]]

	# Tier 1: previous tier has no raw currency, use its primary
	# Tier 2+: use previous tier's raw currency
	if prev.raw_currency < 0:
		costs.append([prev.primary_currency, tier.previous_currency_cost])
	else:
		costs.append([prev.raw_currency, tier.previous_currency_cost])

	return costs


# ── Timing ──────────────────────────────────────────────────────────

func get_base_drop_delay(board_type: Enums.BoardType) -> float:
	var idx: int = _index_of.get(board_type, 0)
	return BASE_DROP_DELAY + 1
	
