extends Node

const LEVELS_PER_TIER := 10
const TIER_THRESHOLDS := [7, 13, 35, 55, 100, 150, 200, 300, 400, 500]

var levels: Array[LevelData] = []
var current_level: int = 0

## Queue of level-ups waiting for the player to claim.
var _pending: Array = []  # Array of { level: int, level_data: LevelData }

## Emitted when a level-up is ready to show. UI should display the dialog.
signal level_up_ready(level: int, level_data: LevelData)

## Emitted after the player claims rewards. Other systems react to this.
signal rewards_claimed(level: int, rewards: Array[RewardData])

## Emitted whenever the level changes (for progress UI).
signal level_changed(new_level: int)


func _ready() -> void:
	_build_level_table()
	CurrencyManager.currency_changed.connect(_on_currency_changed)


func reset() -> void:
	current_level = 0
	_pending.clear()


func rebuild_levels() -> void:
	_build_level_table()


func _build_level_table() -> void:
	levels.clear()

	# Always build gold tier
	_build_tier_levels(Enums.BoardType.GOLD)

	# Add tiers unlocked via prestige
	for i in range(1, TierRegistry.get_tier_count()):
		var tier: TierData = TierRegistry.get_tier_by_index(i)
		if PrestigeManager.is_board_unlocked_permanently(tier.board_type):
			_build_tier_levels(tier.board_type)
		else:
			break  # Tiers unlock sequentially


func _build_tier_levels(board_type: Enums.BoardType) -> void:
	var next_tier: TierData = TierRegistry.get_next_tier(board_type)
	var currency_type: Enums.CurrencyType = TierRegistry.primary_currency(board_type)
	var tier_name: String = FormatUtils.board_name(board_type)

	for slot in LEVELS_PER_TIER:
		var data := LevelData.new()
		data.threshold = TIER_THRESHOLDS[slot]
		data.currency_type = currency_type

		match slot:
			0:  # Unlock ADD_ROW
				data.message = "You have unlocked Add Row for %s." % tier_name
				data.rewards = [_unlock_upgrade(Enums.UpgradeType.ADD_ROW, board_type)]
			1:  # Unlock BUCKET_VALUE
				data.message = "You have unlocked Bucket Value for %s." % tier_name
				data.rewards = [_unlock_upgrade(Enums.UpgradeType.BUCKET_VALUE, board_type)]
			2:  # Drop advanced coin
				_set_advanced_drop(data, next_tier, board_type)
			3:  # Unlock DROP_RATE
				data.message = "You have unlocked Drop Rate for %s." % tier_name
				data.rewards = [_unlock_upgrade(Enums.UpgradeType.DROP_RATE, board_type)]
			4:  # Unlock QUEUE
				data.message = "You have unlocked Queue for %s." % tier_name
				data.rewards = [_unlock_upgrade(Enums.UpgradeType.QUEUE, board_type)]
			5:  # Drop advanced coin
				_set_advanced_drop(data, next_tier, board_type)
			6:  # Special slot (autodroppers)
				_set_special_slot(data, board_type, next_tier)
			7:  # Drop advanced coin
				_set_advanced_drop(data, next_tier, board_type)
			8:  # Drop advanced coin
				_set_advanced_drop(data, next_tier, board_type)
			9:  # Unlock advanced buckets
				if next_tier:
					var adv_name: String = FormatUtils.board_name(next_tier.board_type)
					data.message = "You have unlocked %s Buckets!" % adv_name
					data.rewards = [_unlock_advanced_bucket(board_type)]
				else:
					data.message = "Keep going!"
					data.rewards = []

		levels.append(data)


func _set_advanced_drop(data: LevelData, next_tier: TierData, board_type: Enums.BoardType) -> void:
	if next_tier:
		var adv_name: String = FormatUtils.board_name(next_tier.board_type)
		data.message = "A %s coin will be dropped!" % adv_name
		data.rewards = [_drop_coins(1, next_tier.raw_currency, board_type)]
	else:
		data.message = "Keep going!"
		data.rewards = []


func _set_special_slot(data: LevelData, board_type: Enums.BoardType, next_tier: TierData) -> void:
	if board_type == Enums.BoardType.ORANGE:
		data.message = "You have unlocked Autodropper."
		data.rewards = [_unlock_autodropper(), _unlock_upgrade(Enums.UpgradeType.AUTODROPPER, board_type)]
	elif board_type == Enums.BoardType.RED:
		data.message = "You have unlocked Advanced Autodropper."
		data.rewards = [_unlock_advanced_autodropper(), _unlock_upgrade(Enums.UpgradeType.ADVANCED_AUTODROPPER, board_type)]
	else:
		# Gold: drop advanced coin
		_set_advanced_drop(data, next_tier, board_type)


## Helper to create a LevelData resource inline.
func _level(threshold: int, message: String, p_currency_type: Enums.CurrencyType, rewards: Array[RewardData]) -> LevelData:
	var data := LevelData.new()
	data.threshold = threshold
	data.message = message
	data.currency_type = p_currency_type
	data.rewards = rewards
	return data


## Helper to create an UNLOCK_UPGRADE reward.
func _unlock_upgrade(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType) -> RewardData:
	var r := RewardData.new()
	r.type = RewardData.RewardType.UNLOCK_UPGRADE
	r.upgrade_type = upgrade_type
	r.board_type = board_type
	return r


## Helper to create a DROP_COINS reward.
func _drop_coins(count: int, coin_type: Enums.CurrencyType, target: Enums.BoardType) -> RewardData:
	var r := RewardData.new()
	r.type = RewardData.RewardType.DROP_COINS
	r.coin_count = count
	r.coin_type = coin_type
	r.target_board = target
	return r

## Helper to create an UNLOCK_AUTODROPPER reward.
func _unlock_autodropper() -> RewardData:
	var r := RewardData.new()
	r.type = RewardData.RewardType.UNLOCK_AUTODROPPER
	return r


func _unlock_advanced_autodropper() -> RewardData:
	var r := RewardData.new()
	r.type = RewardData.RewardType.UNLOCK_ADVANCED_AUTODROPPER
	return r


## Helper to create a UNLOCK_BUCKET reward.
func _unlock_advanced_bucket(target: Enums.BoardType) -> RewardData:
	var r := RewardData.new()
	r.type = RewardData.RewardType.UNLOCK_ADVANCED_BUCKET
	r.target_board = target
	return r


func _on_currency_changed(type: Enums.CurrencyType, new_balance: int, _new_cap: int) -> void:
	if type != get_active_currency():
		return

	var was_empty := _pending.is_empty()

	while current_level < levels.size():
		var next_level_data: LevelData = levels[current_level]
		# Only advance if this level tracks the currency that changed
		if next_level_data.currency_type != type:
			break
		if new_balance >= next_level_data.threshold:
			current_level += 1
			_pending.append({ "level": current_level, "level_data": next_level_data })
			level_changed.emit(current_level)
			print("[LevelManager] Level %d reached (threshold=%d)" % [current_level, next_level_data.threshold])
		else:
			break

	if was_empty and not _pending.is_empty():
		var entry = _pending[0]
		level_up_ready.emit(entry["level"], entry["level_data"])


func claim_rewards() -> void:
	if _pending.is_empty():
		return

	var entry = _pending.pop_front()
	var level: int = entry["level"]
	var level_data: LevelData = entry["level_data"]

	print("[LevelManager] Claiming rewards for level %d" % level)

	rewards_claimed.emit(level, level_data.rewards)

	if not _pending.is_empty():
		var next = _pending[0]
		level_up_ready.emit(next["level"], next["level_data"])


func get_active_currency() -> Enums.CurrencyType:
	if current_level >= levels.size():
		if levels.is_empty():
			return Enums.CurrencyType.GOLD_COIN
		return levels[levels.size() - 1].currency_type
	return levels[current_level].currency_type


func get_total_levels() -> int:
	return levels.size()


func get_tier_for_level(level: int) -> Enums.BoardType:
	var tier_index := (level - 1) / LEVELS_PER_TIER
	var tier: TierData = TierRegistry.get_tier_by_index(tier_index)
	return tier.board_type if tier else Enums.BoardType.GOLD


func get_next_threshold() -> int:
	if current_level >= levels.size():
		return -1
	return levels[current_level].threshold


func get_progress() -> float:
	if current_level >= levels.size():
		return 1.0
	var threshold: int = levels[current_level].threshold
	var balance: int = CurrencyManager.get_balance(get_active_currency())
	return float(balance) / float(threshold) if threshold > 0 else 0.0


func serialize() -> Dictionary:
	return { "current_level": current_level }


func deserialize(data: Dictionary) -> void:
	current_level = data.get("current_level", 0)
	_build_level_table()
	level_changed.emit(current_level)
