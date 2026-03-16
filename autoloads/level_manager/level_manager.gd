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


func reset() -> void:
	current_level = 0
	_pending.clear()


func _build_level_table() -> void:
	levels = [
		# Level 1
		_level(7, "You have unlocked the shop.", [
			_unlock_upgrade(Enums.UpgradeType.ADD_ROW, Enums.BoardType.GOLD),
		]),
		# Level 2
		_level(13, "You have unlocked Bucket Value.", [
			_unlock_upgrade(Enums.UpgradeType.BUCKET_VALUE, Enums.BoardType.GOLD),
		]),
		# Level 3
		_level(35, "An ORANGE coin will be dropped!", [
			_drop_coins(1, Enums.CurrencyType.ORANGE_COIN, 3, Enums.BoardType.GOLD),
		]),
		# Level 4
		_level(55, "You have unlocked Drop Rate.", [
			_unlock_upgrade(Enums.UpgradeType.DROP_RATE, Enums.BoardType.GOLD),
		]),
		# Level 5
		_level(100, "An ORANGE coin will be dropped!", [
			_drop_coins(1, Enums.CurrencyType.ORANGE_COIN, 3, Enums.BoardType.GOLD),
		]),
		# Level 6
		_level(150, "An ORANGE coin will be dropped!", [
			_drop_coins(1, Enums.CurrencyType.ORANGE_COIN, 3, Enums.BoardType.GOLD),
		]),
		# Level 7
		_level(200, "You have unlocked Queue.", [
			_unlock_upgrade(Enums.UpgradeType.QUEUE, Enums.BoardType.GOLD),
		]),
		# Level 8
		_level(300, "An ORANGE coin will be dropped!", [
			_drop_coins(1, Enums.CurrencyType.ORANGE_COIN, 3, Enums.BoardType.GOLD),
		]),
		# Level 8
		_level(400, "An ORANGE coin will be dropped!", [
			_drop_coins(1, Enums.CurrencyType.ORANGE_COIN, 3, Enums.BoardType.GOLD),
		]),
		# Level 9
		_level(500, "You have unlocked Orange Buckets!", [_unlock_advanced_bucket(Enums.BoardType.GOLD)]),
		# Level 10
		_level(600, "You have unlocked Add 2 Rows for Orange.", [
			_unlock_upgrade(Enums.UpgradeType.ADD_ROW, Enums.BoardType.ORANGE),
		]),
		# Level 11
		_level(700, "You have unlocked Bucket Value for Orange.", [
			_unlock_upgrade(Enums.UpgradeType.BUCKET_VALUE, Enums.BoardType.ORANGE),
		]),
		# Level 12
		_level(800, "You have unlocked Drop Rate for Orange.", [
			_unlock_upgrade(Enums.UpgradeType.DROP_RATE, Enums.BoardType.ORANGE),
		]),
		# Level 13
		_level(900, "A RED coin will be dropped!", [
			_drop_coins(1, Enums.CurrencyType.RED_COIN, 1, Enums.BoardType.ORANGE),
		]),
		# Level 14
		_level(1000, "You have unlocked Queue for Orange.", [
			_unlock_upgrade(Enums.UpgradeType.QUEUE, Enums.BoardType.ORANGE),
		]),
		# Level 15
		_level(1250, "You have unlocked Autodropper.", [
			_unlock_autodropper(),
			_unlock_upgrade(Enums.UpgradeType.AUTODROPPER, Enums.BoardType.ORANGE),
		]),
		# Level 16
		_level(1500, "A RED coin will be dropped!", [
			_drop_coins(1, Enums.CurrencyType.RED_COIN, 1, Enums.BoardType.ORANGE),
		]),
		# Level 17
		_level(2000, "You have unlocked Red Buckets!", []),
		# Level 18
		_level(2250, "You have unlocked Bucket Value for Red.", [
			_unlock_upgrade(Enums.UpgradeType.BUCKET_VALUE, Enums.BoardType.RED),
		]),
		# Level 19
		_level(2500, "You have unlocked Drop Rate for Red.", [
			_unlock_upgrade(Enums.UpgradeType.DROP_RATE, Enums.BoardType.RED),
		]),
		# Level 20
		_level(2750, "You have unlocked Queue for Red.", [
			_unlock_upgrade(Enums.UpgradeType.QUEUE, Enums.BoardType.RED),
		]),
		# Level 21
		_level(3000, "Keep going!", []),
		# Level 22
		_level(3500, "Keep going!", []),
		# Level 23
		_level(4000, "Keep going!", []),
		# Level 24
		_level(5000, "Keep going!", []),
		# Level 25
		_level(10000, "Keep going!", []),
	]


## Helper to create a LevelData resource inline.
func _level(threshold: int, message: String, rewards: Array[RewardData]) -> LevelData:
	var data := LevelData.new()
	data.threshold = threshold
	data.message = message
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
func _drop_coins(count: int, coin_type: Enums.CurrencyType, mult: int, target: Enums.BoardType) -> RewardData:
	var r := RewardData.new()
	r.type = RewardData.RewardType.DROP_COINS
	r.coin_count = count
	r.coin_type = coin_type
	r.coin_multiplier = mult
	r.target_board = target
	return r

## Helper to create an UNLOCK_AUTODROPPER reward.
func _unlock_autodropper() -> RewardData:
	var r := RewardData.new()
	r.type = RewardData.RewardType.UNLOCK_AUTODROPPER
	return r


## Helper to create a UNLOCK_BUCKET reward.
func _unlock_advanced_bucket(target: Enums.BoardType) -> RewardData:
	var r := RewardData.new()
	r.type = RewardData.RewardType.UNLOCK_ADVANCED_BUCKET
	r.target_board = target
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


func serialize() -> Dictionary:
	return { "current_level": current_level }


func deserialize(data: Dictionary) -> void:
	current_level = data.get("current_level", 0)
	level_changed.emit(current_level)
