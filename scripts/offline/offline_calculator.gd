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

static func _advanced_currency_key(board_type: Enums.BoardType) -> String:
	var adv: int = TierRegistry.advanced_bucket_currency(board_type)
	if adv < 0:
		return ""
	return _currency_key(adv)


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
	var advanced_buckets: Dictionary = boards_data.get("advanced_buckets", {})

	# Precompute per-assignment configuration
	var configs: Array = []
	var drop_accumulators: Dictionary = {}
	var earning_accumulators: Dictionary = {}

	for board_type in Enums.BoardType.values():
		var board_index: int = board_type
		var board_str: String = _board_key(board_type)

		if board_index not in board_types:
			continue

		var bs: Dictionary = board_state.get(board_str, {})
		var drop_delay: float = bs.get("drop_delay", 0.0)
		if drop_delay <= 0.0:
			continue

		var num_rows: int = bs.get("num_rows", 2)
		var bucket_value_multiplier: int = bs.get("bucket_value_multiplier", 1)
		var advanced_coin_multiplier: float = bs.get("advanced_coin_multiplier", 2.0)
		var distance_for_advanced: int = bs.get("distance_for_advanced_buckets", 3)
		var multi_drop: int = bs.get("multi_drop_count", 1)
		var show_advanced: bool = advanced_buckets.get(board_str, false)

		var probabilities: Array = _get_pascal_probabilities(num_rows)
		var bucket_layout: Array = _get_bucket_layout(
			num_rows, bucket_value_multiplier, distance_for_advanced,
			show_advanced, board_type)

		for assignment_type in ["NORMAL", "ADVANCED"]:
			var assignment_key := "%s_%s" % [board_str, assignment_type]
			var autodropper_count: int = assignments.get(assignment_key, 0)
			if autodropper_count <= 0:
				continue

			var adv_currency_key := _advanced_currency_key(board_type)
			if assignment_type == "ADVANCED" and adv_currency_key == "":
				continue

			var coin_multiplier: float = advanced_coin_multiplier if assignment_type == "ADVANCED" else 1.0
			var costs: Array = _get_drop_costs(board_type, assignment_type)

			var earnings_per_drop: Dictionary = {}
			for i in probabilities.size():
				var bucket: Dictionary = bucket_layout[i]
				var c_key: String = bucket["currency_key"]
				var value: int = bucket["value"]
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


static func _get_bucket_layout(num_rows: int, bucket_value_multiplier: int, distance_for_advanced: int, show_advanced: bool, board_type: Enums.BoardType) -> Array:
	var num_buckets: int = num_rows + 1
	var primary_currency: String = _primary_currency_key(board_type)
	var advanced_currency: String = _advanced_currency_key(board_type)
	var layout: Array = []

	for i in num_buckets:
		@warning_ignore("integer_division")
		var distance_from_center: int = int(abs(i - num_buckets / 2))
		var value: int = 1
		var currency_key: String = primary_currency

		if distance_from_center >= distance_for_advanced and show_advanced and advanced_currency != "":
			currency_key = advanced_currency
			distance_from_center -= distance_for_advanced

		value += distance_from_center * bucket_value_multiplier
		layout.append({"currency_key": currency_key, "value": value})

	return layout


static func _get_drop_costs(board_type: Enums.BoardType, assignment_type: String) -> Array:
	if assignment_type == "ADVANCED":
		return [[_advanced_currency_key(board_type), 1]]

	var costs := TierRegistry.get_drop_costs(board_type)
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
