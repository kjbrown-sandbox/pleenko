extends Node

## The ordered tier chain. Index 0 is always the starting tier (gold).
@export var tiers: Array[TierData] = []

# Lookup tables built in _ready()
var _by_board: Dictionary = {}        # BoardType -> TierData
var _by_primary: Dictionary = {}      # CurrencyType -> TierData
var _index_of: Dictionary = {}        # BoardType -> int

const BASE_DROP_DELAY := 2.0


func _ready() -> void:
	_rebuild_lookups()


func _rebuild_lookups() -> void:
	_by_board.clear()
	_by_primary.clear()
	_index_of.clear()
	for i in tiers.size():
		var tier := tiers[i]
		_by_board[tier.board_type] = tier
		_by_primary[tier.primary_currency] = tier
		_index_of[tier.board_type] = i


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


func cap_raise_currency(board_type: Enums.BoardType) -> int:
	var next := get_next_tier(board_type)
	return next.primary_currency if next else -1


## Null for WHITE_COIN, which is deliberately tier-less — it is minted by every
## board's earrings and owned by none. Callers that reach for a tier to derive a
## cap or a cap-raise price must special-case white (see CurrencyManager).
func get_tier_for_currency(currency_type: int) -> TierData:
	if currency_type in _by_primary:
		return _by_primary[currency_type]
	return null


# ── Drop costs ──────────────────────────────────────────────────────

func get_drop_costs(board_type: Enums.BoardType) -> Array:
	var tier := get_tier(board_type)
	if not tier:
		return []
	var idx: int = _index_of[board_type]

	# Tier 0 (gold): just 1 of its own primary currency
	if idx == 0:
		return [[tier.primary_currency, 1]]

	# Every later board is fueled by the previous tier's PRIMARY currency
	# (e.g. orange costs 100 gold).
	var prev := tiers[idx - 1]
	var costs: Array = [[prev.primary_currency, tier.previous_currency_cost]]

	# Late boards additionally cost WHITE, which only earrings mint. A player who
	# reaches one of these boards before growing any earrings genuinely cannot
	# drop on it yet — that is intended, not a soft-lock to rescue: the way
	# forward is to cap the main board and grow earrings.
	var white_cost: int = WhiteCurrency.drop_cost(idx)
	if white_cost > 0:
		costs.append([Enums.CurrencyType.WHITE_COIN, white_cost])
	return costs


# ── Timing ──────────────────────────────────────────────────────────

## Uniform across tiers today; takes board_type so per-tier tuning stays a
## one-line change here rather than a call-site migration.
func get_base_drop_delay(_board_type: Enums.BoardType) -> float:
	return BASE_DROP_DELAY + 1

