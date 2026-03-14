extends Node

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


func _build_level_table() -> void:
	levels = [
		_level(10, "You can now add rows to your board!", [
			_unlock(Enums.UpgradeType.ADD_ROW, Enums.BoardType.GOLD),
		]),
		_level(25, "Bucket values can now be upgraded!", [
			_unlock(Enums.UpgradeType.BUCKET_VALUE, Enums.BoardType.GOLD),
		]),
		_level(50, "Here are some free coins!", [
			_drop_coins(5),
		]),
		_level(75, "You can now upgrade your drop rate!", [
			_unlock(Enums.UpgradeType.DROP_RATE, Enums.BoardType.GOLD),
		]),
		_level(120, "You unlocked the coin queue!", [
			_unlock(Enums.UpgradeType.QUEUE, Enums.BoardType.GOLD),
		]),
	]


## Helper to create a LevelData resource inline.
func _level(threshold: int, message: String, rewards: Array[RewardData]) -> LevelData:
	var data := LevelData.new()
	data.threshold = threshold
	data.message = message
	data.rewards = rewards
	return data


## Helper to create an UNLOCK_UPGRADE reward.
func _unlock(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType) -> RewardData:
	var r := RewardData.new()
	r.type = RewardData.RewardType.UNLOCK_UPGRADE
	r.upgrade_type = upgrade_type
	r.board_type = board_type
	return r


## Helper to create a DROP_COINS reward.
func _drop_coins(count: int) -> RewardData:
	var r := RewardData.new()
	r.type = RewardData.RewardType.DROP_COINS
	r.coin_count = count
	return r


func _on_currency_changed(type: Enums.CurrencyType, new_balance: int, _new_cap: int) -> void:
	if type != Enums.CurrencyType.GOLD_COIN:
		return

	while current_level < levels.size():
		var next_level_data: LevelData = levels[current_level]
		if new_balance >= next_level_data.threshold:
			current_level += 1
			_pending.append({ "level": current_level, "level_data": next_level_data })
			level_changed.emit(current_level)
			print("[LevelManager] Level %d reached (threshold=%d)" % [current_level, next_level_data.threshold])
		else:
			break

	if _pending.size() == 1:
		var entry = _pending[0]
		level_up_ready.emit(entry["level"], entry["level_data"])


func claim_rewards() -> void:
	if _pending.is_empty():
		return

	var entry = _pending.pop_front()
	var level: int = entry["level"]
	var level_data: LevelData = entry["level_data"]

	print("[LevelManager] Claiming rewards for level %d" % level)

	for reward in level_data.rewards:
		if reward.type == RewardData.RewardType.DROP_COINS:
			CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, reward.coin_count)

	rewards_claimed.emit(level, level_data.rewards)

	if not _pending.is_empty():
		var next = _pending[0]
		level_up_ready.emit(next["level"], next["level_data"])


func get_next_threshold() -> int:
	if current_level >= levels.size():
		return -1
	return levels[current_level].threshold


func get_progress() -> float:
	if current_level >= levels.size():
		return 1.0
	var threshold: int = levels[current_level].threshold
	var gold: int = CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN)
	return float(gold) / float(threshold) if threshold > 0 else 0.0
