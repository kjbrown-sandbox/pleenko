class_name OfflineCalculator

## Pure static calculator for offline/background earnings.
## Works entirely on serialized save data — no autoloads, no nodes.
## Uses Enums (a class_name, not an autoload) to derive all string keys,
## so a renamed enum value causes a compile error instead of a silent bug.
## Reads board computed state (drop_delay, num_rows, etc.) directly from save
## data rather than re-deriving from upgrade levels.
##
## Processes time in 10-second batches with all boards interleaved per batch.
## This prevents cap waste and cross-board starvation that would occur if
## each board consumed all its time before the next board started.
## Fractional drop and earning accumulators carry between batches to avoid
## truncation error.

const BATCH_SECONDS := 10.0
const MAX_OFFLINE_SECONDS := 259200.0  # 3 days


## Derive string keys from Enums so typos become compile errors.
static func _board_key(board_type: Enums.BoardType) -> String:
	return Enums.BoardType.keys()[board_type]

static func _currency_key(currency_type: Enums.CurrencyType) -> String:
	return Enums.CurrencyType.keys()[currency_type]

static func _primary_currency_key(board_type: Enums.BoardType) -> String:
	return _currency_key(TierRegistry.primary_currency(board_type))

## A currency is considered "ever earned" when its tier's board has been
## prestiged at least once, OR when it's the starting tier (always earnable).
## Currencies with no associated tier are treated as always earnable. That is
## WHITE_COIN, which no board owns: reaching an earring at all is a far deeper
## gate than a prestige, so there is no first-time beat left to protect.
## Used to suppress offline earnings for currencies the player has never
## organically earned — preserves the first-time prestige beat.
static func _is_currency_ever_earned(currency_key: String, prestige_data: Dictionary) -> bool:
	var currency_type: int = Enums.CurrencyType[currency_key]
	var tier: TierData = TierRegistry.get_tier_for_currency(currency_type)
	if not tier:
		return true
	if TierRegistry.is_starting_tier(tier.board_type):
		return true
	return int(prestige_data.get(_board_key(tier.board_type), 0)) > 0


## Takes the full save dictionary and elapsed seconds, returns a modified copy
## with updated currency balances reflecting offline autodropper earnings.
static func calculate(state: Dictionary, elapsed_seconds: float) -> Dictionary:
	if elapsed_seconds <= 0.0:
		return state

	var clamped_elapsed := minf(elapsed_seconds, MAX_OFFLINE_SECONDS)
	var result := state.duplicate(true)

	var boards_data: Dictionary = result.get("boards", {})
	var currency_data: Dictionary = result.get("currency", {})
	var assignments: Dictionary = boards_data.get("assignments", {})
	var board_types: Array = boards_data.get("board_types", [0])
	var board_state: Dictionary = boards_data.get("board_state", {})
	var prestige_data: Dictionary = result.get("prestige", {})

	# Precompute per-assignment configuration
	var configs: Array = []
	var drop_accumulators: Dictionary = {}
	var earning_accumulators: Dictionary = {}

	for board_type in Enums.BoardType.values():
		var board_index: int = board_type
		var board_str: String = _board_key(board_type)

		if float(board_index) not in board_types:
			continue

		var bs: Dictionary = board_state.get(board_str, {})
		var drop_delay: float = bs.get("drop_delay", 0.0)
		if drop_delay <= 0.0:
			continue

		var num_rows: int = bs.get("num_rows", 2)
		# Earring rows are derived state written alongside num_rows. Absent in
		# pre-earrings saves, where 0 reproduces the old layout exactly.
		var earring_rows: int = bs.get("earring_rows", 0)
		var bucket_value_multiplier: int = bs.get("bucket_value_multiplier", 1)
		var multi_drop: int = bs.get("multi_drop_count", 1)

		var probabilities: Array = _get_pascal_probabilities(num_rows)
		var bucket_layout: Array = _get_bucket_layout(
			num_rows, bucket_value_multiplier, board_type, earring_rows)

		# ADVANCED assignments are still read from old saves so their autodroppers
		# aren't silently dropped from the pool, but they now earn exactly what a
		# NORMAL one does: the advanced-bucket system they were built for is gone.
		for assignment_type in ["NORMAL", "ADVANCED"]:
			var assignment_key := "%s_%s" % [board_str, assignment_type]
			var autodropper_count: int = assignments.get(assignment_key, 0)
			if autodropper_count <= 0:
				continue

			var coin_multiplier: float = 1.0
			var costs: Array = _get_drop_costs(board_type)

			var earnings_per_drop: Dictionary = {}
			for i in probabilities.size():
				var bucket: Dictionary = bucket_layout[i]
				var c_key: String = bucket["currency_key"]
				if not _is_currency_ever_earned(c_key, prestige_data):
					continue
				var value: float = bucket["value"]
				var earning: float = probabilities[i] * value * coin_multiplier * multi_drop
				earnings_per_drop[c_key] = earnings_per_drop.get(c_key, 0.0) + earning

			var drop_rate: float = float(autodropper_count) / drop_delay

			drop_accumulators[assignment_key] = 0.0
			earning_accumulators[assignment_key] = {}

			configs.append({
				"key": assignment_key,
				"drop_rate": drop_rate,
				"costs": costs,
				"earnings_per_drop": earnings_per_drop,
			})

	if configs.is_empty():
		return result

	# Process in batches — all boards interleave within each batch
	var remaining := clamped_elapsed
	while remaining > 0.0:
		var batch := minf(BATCH_SECONDS, remaining)
		remaining -= batch

		for config in configs:
			var key: String = config["key"]
			drop_accumulators[key] += config["drop_rate"] * batch
			var drops: int = int(floor(drop_accumulators[key]))
			drop_accumulators[key] -= drops

			if drops <= 0:
				continue

			var costs: Array = config["costs"]
			var earnings_per_drop: Dictionary = config["earnings_per_drop"]

			# Limit by affordability (gross cost per drop)
			var actual_drops: int = drops
			for cost in costs:
				var cost_currency: String = cost[0]
				var cost_per_drop: int = cost[1]
				if cost_per_drop > 0:
					@warning_ignore("integer_division")
					var max_affordable: int = _get_balance(currency_data, cost_currency) / cost_per_drop
					actual_drops = mini(actual_drops, max_affordable)

			if actual_drops <= 0:
				continue

			# Deduct costs
			for cost in costs:
				var cost_currency: String = cost[0]
				var total_cost: int = cost[1] * actual_drops
				var current: int = _get_balance(currency_data, cost_currency)
				_set_balance(currency_data, cost_currency, current - total_cost)

			# Accumulate fractional earnings across batches, apply integer part
			var earn_accum: Dictionary = earning_accumulators[key]
			for c_key in earnings_per_drop:
				var raw_earning: float = earnings_per_drop[c_key] * actual_drops
				earn_accum[c_key] = earn_accum.get(c_key, 0.0) + raw_earning
				var to_add: int = int(floor(earn_accum[c_key]))
				earn_accum[c_key] -= to_add
				if to_add > 0:
					var cap: int = _get_cap(currency_data, c_key)
					var current: int = _get_balance(currency_data, c_key)
					_set_balance(currency_data, c_key, mini(cap, current + to_add))

	return result


static func _get_pascal_probabilities(num_rows: int) -> Array:
	var row: Array = [1]
	for i in num_rows:
		var new_row: Array = [1]
		for j in range(row.size() - 1):
			new_row.append(row[j] + row[j + 1])
		new_row.append(1)
		row = new_row

	var total: float = pow(2, num_rows)
	var probabilities: Array = []
	for val in row:
		probabilities.append(float(val) / total)
	return probabilities


## Per-bucket currency + value for the offline model.
##
##
## `earring_rows` > 0 means the two edge buckets are gateways: they pay no
## primary currency themselves, and the coin falls through into an earring that
## pays WHITE. Without this the edges would be credited as the highest-value
## buckets on the board while awarding nothing in live play.
##
## A gateway is credited the earring's EXPECTED white (WhiteCurrency.expected_value)
## rather than simulating the earring's own lattice. That is exact, not an
## approximation — the expectation weights every earring bucket by its binomial
## probability, which is the same distribution the simulation would sample. It is
## kept as a float for that reason: rounding a ~2.09 expectation to an int would
## quietly lose several percent of white per drop. (The transporter, reachable on
## 1 in 2^earring_rows of those landings once the earrings meet, pays 0; at the
## meeting size that is a 0.4% over-credit and is deliberately not modelled.)
static func _get_bucket_layout(num_rows: int, bucket_value_multiplier: int, board_type: Enums.BoardType, earring_rows: int = 0) -> Array:
	var num_buckets: int = num_rows + 1
	var primary_currency: String = _primary_currency_key(board_type)
	var white_key: String = _currency_key(Enums.CurrencyType.WHITE_COIN)
	var tier_index: int = TierRegistry.get_tier_index(board_type)
	var layout: Array = []

	for i in num_buckets:
		@warning_ignore("integer_division")
		var distance_from_center: int = int(abs(i - num_buckets / 2))
		# Float, because a gateway's value is an expectation rather than a bucket
		# label — rounding it here would lose a few percent of white per drop.
		var value: float = float(1 + distance_from_center * bucket_value_multiplier)
		var currency_key: String = primary_currency

		if EarringGeometry.is_gateway_bucket(i, num_buckets, earring_rows):
			currency_key = white_key
			value = WhiteCurrency.expected_value(earring_rows, tier_index)
		layout.append({"currency_key": currency_key, "value": value})

	return layout


static func _get_drop_costs(board_type: Enums.BoardType) -> Array:
	var costs: Array = TierRegistry.get_drop_costs(board_type)
	var result: Array = []
	for cost in costs:
		result.append([_currency_key(cost[0]), cost[1]])
	return result


static func _get_balance(currency_data: Dictionary, currency_key: String) -> int:
	return int(currency_data.get(currency_key, {}).get("balance", 0))


static func _set_balance(currency_data: Dictionary, currency_key: String, value: int) -> void:
	if currency_key in currency_data:
		currency_data[currency_key]["balance"] = value


static func _get_cap(currency_data: Dictionary, currency_key: String) -> int:
	return int(currency_data.get(currency_key, {}).get("cap", 500))
