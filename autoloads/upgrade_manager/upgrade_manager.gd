extends Node

class UpgradeState:
	var level: int = 0
	var cost: int = 0
	var delta: int = 0
	var base_cap: int = 0     ## from BaseUpgradeData.max_level; 0 = uncapped
	var current_cap: int = 0  ## starts at base_cap; raised by cap upgrades
	var cap_level: int = 0    ## number of cap raises purchased

## Broad "something about this upgrade changed, repaint" signal. Fires for a
## bought level, a bought CAP RAISE (level unchanged!), and force_apply. Listen
## to this for UI refreshes; listen to upgrade_bought for anything that should
## happen once per paid level.
signal upgrade_purchased(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType, new_level: int)
## A level was PAID FOR — by a click or by the auto-buy drain. Distinct from
## upgrade_purchased, which is the broad "something about this upgrade changed,
## repaint" signal and also fires for cap raises and for force_apply.
##
## UpgradeSection applies a per-board upgrade's board effect off THIS one. It has
## to be the narrow signal: buy_cap_raise emits upgrade_purchased with the level
## UNCHANGED, so hanging the effect there granted a free add_two_rows for
## cap-raise money (and desynced geometry from level, since the rows evaporated
## on the next load). force_apply is likewise excluded — challenge starting
## conditions call it and then build their boards separately.
signal upgrade_bought(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType, new_level: int)
signal upgrade_unlocked(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType)
signal cap_raise_unlocked(board_type: Enums.BoardType)
signal autodropper_unlocked
## A pair's auto-buy lock was toggled. UpgradeRow listens to repaint its toggle,
## and every OTHER row listens too: spending the last slot has to grey out the
## toggles on rows that are now unlockable.
signal auto_buy_changed(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType, locked: bool)

## Populate this array in the Inspector with .tres BaseUpgradeData resources.
@export var upgrades: Array[BaseUpgradeData] = []

## Optional gate callable: Callable(upgrade_type: Enums.UpgradeType) -> bool
## Set by ChallengeManager to block upgrades during challenges.
var upgrade_gate: Callable

## Per-board, per-upgrade runtime state.
var _state: Dictionary = {}  # BoardType -> UpgradeType -> UpgradeState

## Quick lookup: UpgradeType -> BaseUpgradeData
var _upgrade_map: Dictionary = {}

## Tracks which upgrades are unlocked per board.
var _unlocked: Dictionary = {}  # BoardType -> UpgradeType -> bool

## Tracks whether cap raising is available per board (next board must be unlocked).
var _cap_raise_available: Dictionary = {}  # BoardType -> bool


func _ready() -> void:
	# Build lookup map
	for data in upgrades:
		_upgrade_map[data.type] = data

	_init_state()

	# The slot count IS the upgrade's level, so the locks read it back through
	# this manager rather than holding a copy that could drift after a prestige.
	auto_buy_locks.capacity_fn = current_auto_buy_slots

	# Listen for level rewards to unlock upgrades
	LevelManager.rewards_claimed.connect(_on_rewards_claimed)
	LevelManager.reconcile_reward.connect(_on_reconcile_reward)
	CurrencyManager.currency_changed.connect(_on_currency_changed)


func _init_state() -> void:
	for board_type in Enums.BoardType.values():
		_state[board_type] = {}
		_unlocked[board_type] = {}
		_cap_raise_available[board_type] = false
		for data in upgrades:
			var s := UpgradeState.new()
			s.cost = data.base_cost
			s.delta = data.cost_delta
			s.base_cap = data.max_level
			s.current_cap = data.max_level
			_state[board_type][data.type] = s
			_unlocked[board_type][data.type] = false


func reset() -> void:
	_init_state()
	# Locks go with the levels: a prestige wipes the slots that paid for them, so
	# keeping the locks would auto-buy on credit the player no longer owns.
	auto_buy_locks.clear()

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


## Effective ceiling on an upgrade's level. 0 means uncapped.
##
## This is `current_cap` folded together with any HARD cap. current_cap can be
## RAISED by the cap-raise system, so a hard ceiling expressed only as
## BaseUpgradeData.max_level would evaporate after enough cap raises. Every
## purchasability gate (can_buy, can_buy_cap_raise, force_apply, UpgradeRow)
## reads this one function so they cannot disagree.
func get_max_level(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> int:
	var cap: int = _state[board_type][upgrade_type].current_cap
	var hard: int = _hard_cap(upgrade_type)
	if hard < 0:
		return cap
	if cap <= 0:
		return hard
	return mini(cap, hard)


## Hard ceiling for an upgrade type, or -1 when it has none.
##
## ADD_ROW is the only one: once a board's earrings meet at the centre there is
## nothing left for the upgrade to grow. Only applies when earrings are enabled
## — an uncapped challenge board keeps today's unbounded cap-raise behaviour.
func _hard_cap(upgrade_type: Enums.UpgradeType) -> int:
	if upgrade_type != Enums.UpgradeType.ADD_ROW:
		return -1
	if not ChallengeManager.boards_grow_earrings():
		return -1
	return EarringGeometry.max_add_row_level()


## True when this upgrade's current cap has already reached its hard ceiling, so
## buying a cap raise would raise a cap that can never be spent — a wasted-spend
## soft-lock if left enabled.
func is_at_hard_cap(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	var hard: int = _hard_cap(upgrade_type)
	return hard >= 0 and _state[board_type][upgrade_type].current_cap >= hard


func get_state(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> UpgradeState:
	return _state[board_type][upgrade_type]


func is_unlocked(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	return _unlocked[board_type][upgrade_type]


## RETIRED upgrades can never be unlocked, by save restore or by reward.
##
## NEITHER half of a retired upgrade may be deleted, for two DIFFERENT reasons:
##   - Its .tres registration (data/advanced_autodropper.tres) stays because
##     deserialize() indexes _state[board][type] for every Enums.UpgradeType.
##     Unregistering it would CRASH any save that recorded the key.
##   - Its enum VALUE stays because UpgradeType ordinals are persisted as ints —
##     by .tres files (peg_deflector.tres hardcodes `type = 6`) and by
##     ChallengeProgressManager's permanent_upgrades blob. Deleting ordinal 5
##     would silently renumber PEG_DEFLECTOR 6 -> 5 and repoint both at the wrong
##     upgrade. That one corrupts data instead of crashing, so it is the more
##     dangerous of the two.
##
## Refusing the unlock is what actually makes a retired upgrade unreachable.
## _clear_retired_state() then drops any level/cost an old save carried, so
## nothing can recompute a pool from it later.
const RETIRED_UPGRADES: Array[Enums.UpgradeType] = [
	Enums.UpgradeType.ADVANCED_AUTODROPPER,
]


func is_retired(upgrade_type: Enums.UpgradeType) -> bool:
	return upgrade_type in RETIRED_UPGRADES


## Zeroes every board's stored state for retired upgrades. Called at the end of
## deserialize so an old save's purchased levels can't be read back by anything
## that derives a value from upgrade level (e.g. BoardManager's legacy
## normal_pool fallback), and so they stop being re-serialized.
func _clear_retired_state() -> void:
	for upgrade_type in RETIRED_UPGRADES:
		for board_type in Enums.BoardType.values():
			var s: UpgradeState = _state[board_type][upgrade_type]
			s.level = 0
			s.cap_level = 0
			s.current_cap = s.base_cap
			_unlocked[board_type][upgrade_type] = false


func unlock(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> void:
	if is_retired(upgrade_type):
		_unlocked[board_type][upgrade_type] = false
		return
	if _unlocked[board_type][upgrade_type]:
		return
	_unlocked[board_type][upgrade_type] = true
	upgrade_unlocked.emit(upgrade_type, board_type)
	print("[UpgradeManager] Unlocked %s on %s" % [
		Enums.UpgradeType.keys()[upgrade_type],
		Enums.BoardType.keys()[board_type]
	])


func can_buy(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	if upgrade_gate.is_valid() and not upgrade_gate.call(upgrade_type):
		return false
	if not is_unlocked(board_type, upgrade_type):
		return false

	var state: UpgradeState = _state[board_type][upgrade_type]

	# get_max_level of 0 means uncapped
	var max_level: int = get_max_level(board_type, upgrade_type)
	if max_level > 0 and state.level >= max_level:
		return false

	var currency := TierRegistry.primary_currency(board_type)
	return CurrencyManager.can_afford(currency, state.cost)


func buy(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	if not can_buy(board_type, upgrade_type):
		return false

	var state: UpgradeState = _state[board_type][upgrade_type]

	var currency := TierRegistry.primary_currency(board_type)
	CurrencyManager.spend(currency, state.cost)

	state.level += 1
	_advance_cost(board_type, upgrade_type)

	upgrade_purchased.emit(upgrade_type, board_type, state.level)
	upgrade_bought.emit(upgrade_type, board_type, state.level)
	return true


## Grants a level with no cost and no unlock check (StartingUpgrades, prestige
## rewards). Still honours the hard cap — past it the level would be unbuildable
## geometry, not just an unaffordable purchase.
func force_apply(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> void:
	var state: UpgradeState = _state[board_type][upgrade_type]
	var hard: int = _hard_cap(upgrade_type)
	if hard >= 0 and state.level >= hard:
		return
	state.level += 1
	_advance_cost(board_type, upgrade_type)
	upgrade_purchased.emit(upgrade_type, board_type, state.level)


func _on_rewards_claimed(_level: int, rewards: Array[RewardData]) -> void:
	for reward in rewards:
		if reward.type == RewardData.RewardType.UNLOCK_UPGRADE:
			if ChallengeManager.is_active_challenge and not ChallengeManager.is_upgrade_allowed(reward.upgrade_type):
				continue
			unlock(reward.board_type, reward.upgrade_type)
		elif reward.type == RewardData.RewardType.UNLOCK_AUTODROPPER:
			autodropper_unlocked.emit()


func _on_reconcile_reward(reward: RewardData) -> void:
	if reward.type == RewardData.RewardType.UNLOCK_UPGRADE:
		unlock(reward.board_type, reward.upgrade_type)


func is_cap_raise_available(board_type: Enums.BoardType) -> bool:
	return _cap_raise_available[board_type]


func get_cap_raise_cost(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> int:
	var state: UpgradeState = _state[board_type][upgrade_type]
	return 1 + 2 * state.cap_level


func can_buy_cap_raise(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	if not _cap_raise_available[board_type]:
		return false
	var state: UpgradeState = _state[board_type][upgrade_type]
	# Can't raise cap on uncapped upgrades
	if state.base_cap == 0:
		return false
	# Nor past a hard ceiling — the raise would buy a level that can never be
	# purchased, spending higher-tier currency for nothing.
	if is_at_hard_cap(board_type, upgrade_type):
		return false
	var currency: int = TierRegistry.cap_raise_currency(board_type)
	if currency == -1:
		return false
	return CurrencyManager.can_afford(currency, get_cap_raise_cost(board_type, upgrade_type))


func buy_cap_raise(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	if not can_buy_cap_raise(board_type, upgrade_type):
		return false
	var state: UpgradeState = _state[board_type][upgrade_type]
	var currency: int = TierRegistry.cap_raise_currency(board_type)
	CurrencyManager.spend(currency, get_cap_raise_cost(board_type, upgrade_type))
	state.current_cap += 1
	state.cap_level += 1
	upgrade_purchased.emit(upgrade_type, board_type, state.level)
	return true


# ── Auto-buy ──────────────────────────────────────────────────────────────────
# Red's signature upgrade. The player locks (board, upgrade) pairs to slots, and
# a locked pair buys itself the instant it becomes affordable.
#
# The purchase path is deliberately RE-ENTRANT-GUARDED: buy() spends currency,
# which emits currency_changed, which lands back here. Without _draining that is
# unbounded recursion on the very first affordable purchase, not a subtle bug.

## Booked under RED. Unlike the other signature upgrades this has no board
## mechanic, so the constant lives with the manager rather than on PlinkoBoard —
## and it defers to UniversalUpgrades, which is the single source of truth for
## every signature upgrade's nominated board.
const AUTO_BUY_BOARD := Enums.BoardType.RED

## Ceiling on purchases per drain, so one enormous balance can't stall a frame.
##
## Leftovers wait for the next EXTERNAL currency change — the next coin landing,
## typically. The currency_changed a purchase itself emits is deliberately
## swallowed by _draining, so it cannot continue the backlog.
const MAX_AUTO_BUYS_PER_DRAIN := 32

## Ceiling for the one-shot catch-up after a load. Far higher because returning
## from a long idle is exactly the case where a big backlog is EXPECTED, and
## trickling it out 32 per coin landing would leave the player watching their
## own upgrades arrive for minutes. Still bounded so a corrupt save cannot hang
## the load.
const MAX_AUTO_BUYS_ON_LOAD := 2000

var auto_buy_locks := AutoBuyLocks.new()

## True while _drain_auto_buys is running, so the currency_changed it provokes
## re-enters into a no-op instead of recursing.
var _draining: bool = false

## True for the duration of catch_up_auto_buys — see is_catching_up().
var _catching_up: bool = false


## Slots the player owns, i.e. the upgrade's level. Static so the HUD can read it
## without an instance, matching the other signature upgrades' current_* helpers.
static func current_auto_buy_slots() -> int:
	if ChallengeManager.is_active_challenge:
		# Challenges reset UpgradeManager, so this is already 0 today; stating it
		# keeps the exclusion a decision rather than a consequence of reset order.
		return 0
	return UpgradeManager.get_level(AUTO_BUY_BOARD, Enums.UpgradeType.AUTO_BUY)


## Buys every locked pair the player can currently afford.
##
## Ordering is deliberately whatever the lock set yields rather than cheapest- or
## costliest-first: any priority rule would quietly decide FOR the player which
## of their own locked upgrades matters most, and the player already expressed
## that preference by choosing which pairs to lock.
func _drain_auto_buys(limit: int = MAX_AUTO_BUYS_PER_DRAIN) -> void:
	if _draining:
		return
	if auto_buy_locks.count() == 0:
		return
	_draining = true
	var bought: int = 0
	var progressed: bool = true
	# The inner loop buys each locked pair AT MOST once, so repeated levels of the
	# same pair need repeat passes. That is what this outer loop is for — not
	# cascading affordability, which a purchase can only ever reduce.
	while progressed and bought < limit:
		progressed = false
		# pairs() is a snapshot on purpose: buy() emits upgrade_purchased to many
		# listeners mid-loop, and iterating the live set would break if one of
		# them ever mutated it.
		for pair: Dictionary in auto_buy_locks.pairs():
			if bought >= limit:
				break
			var board_type: Enums.BoardType = pair["board_type"]
			var upgrade_type: Enums.UpgradeType = pair["upgrade_type"]
			# can_buy covers the challenge gate, the unlock flag, the cap AND
			# affordability, so a capped pair simply stops buying while KEEPING
			# its lock — the player decides when to free that slot.
			if buy(board_type, upgrade_type):
				bought += 1
				progressed = true
	_draining = false


## Spends whatever accumulated while the game was closed.
##
## Offline earnings are credited into the save blob BEFORE any manager
## deserializes, so the currency_changed that CurrencyManager fires on load
## arrives while the lock set is still empty — the normal drain cannot see it.
## Without this call a player returns from a long idle to a full wallet and
## nothing bought, then watches purchases trickle in 32 per coin landing.
##
## Deliberately a one-shot at the END of loading rather than a simulation
## interleaved with offline earnings: upgrades bought here do NOT retroactively
## boost the idle period that paid for them. That under-credits slightly, and is
## the tradeoff for not having OfflineCalculator model a moving economy.
##
## Must run after BoardManager.deserialize — the board effects these purchases
## trigger are applied against real boards.
func catch_up_auto_buys() -> void:
	_catching_up = true
	_drain_auto_buys(MAX_AUTO_BUYS_ON_LOAD)
	_catching_up = false


## True while the post-load catch-up is running. Read by UpgradeSection to skip
## the celebration animations: the player has just loaded, there is nothing to
## celebrate yet, and a backlog would queue every animation into one frame where
## only the last is visible anyway.
func is_catching_up() -> bool:
	return _catching_up


## Toggles a pair's auto-buy lock. Returns the state it ended in; false can mean
## either "unlocked" or "refused, no slots free", which the caller distinguishes
## via auto_buy_locks.free_slots().
func toggle_auto_buy(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	var locked: bool = auto_buy_locks.toggle(board_type, upgrade_type)
	auto_buy_changed.emit(board_type, upgrade_type, locked)
	if locked:
		# Buy immediately rather than waiting for the next currency tick, so
		# locking something already affordable does what the player just asked.
		_drain_auto_buys()
	return locked


func _on_currency_changed(_type: Enums.CurrencyType, _new_balance: int, _new_cap: int) -> void:
	# Cap raises are no longer unlocked by earning a raw currency. They are now
	# enabled explicitly via enable_cap_raise() on the 2nd board-completion beat
	# (see PlinkoBoard._on_final_bounce_started).
	#
	# Auto-buy rides this signal so a locked upgrade is bought the instant the
	# coin that paid for it lands, rather than on a poll the player can outrace.
	_drain_auto_buys()


## Enables cap raises for a board (its caps can now be raised with the next tier's
## currency). Called on the 2nd board completion, BEFORE cap_raise_coin_landed is
## emitted so the reveal animator sees is_cap_raise_available() == true.
func enable_cap_raise(board_type: Enums.BoardType) -> void:
	if _cap_raise_available[board_type]:
		return
	_cap_raise_available[board_type] = true
	cap_raise_unlocked.emit(board_type)


func serialize() -> Dictionary:
	var data := {}

	# Serialize per-board, per-upgrade state
	var state_data := {}
	for board_type in _state:
		var board_key: String = Enums.BoardType.keys()[board_type]
		state_data[board_key] = {}
		for upgrade_type in _state[board_type]:
			var upgrade_key: String = Enums.UpgradeType.keys()[upgrade_type]
			var s: UpgradeState = _state[board_type][upgrade_type]
			state_data[board_key][upgrade_key] = {
				"level": s.level,
				"cost": s.cost,
				"delta": s.delta,
				"current_cap": s.current_cap,
				"cap_level": s.cap_level,
			}
	data["state"] = state_data

	# Serialize unlocks
	var unlocked_data := {}
	for board_type in _unlocked:
		var board_key: String = Enums.BoardType.keys()[board_type]
		unlocked_data[board_key] = {}
		for upgrade_type in _unlocked[board_type]:
			var upgrade_key: String = Enums.UpgradeType.keys()[upgrade_type]
			unlocked_data[board_key][upgrade_key] = _unlocked[board_type][upgrade_type]
	data["unlocked"] = unlocked_data
	data["auto_buy_locks"] = auto_buy_locks.serialize()

	# Serialize cap raise availability
	var cap_raise_data := {}
	for board_type in _cap_raise_available:
		var board_key: String = Enums.BoardType.keys()[board_type]
		cap_raise_data[board_key] = _cap_raise_available[board_type]
	data["cap_raise_available"] = cap_raise_data

	return data


func deserialize(data: Dictionary) -> void:
	# Restore per-board, per-upgrade state
	var state_data: Dictionary = data.get("state", {})
	for board_type in Enums.BoardType.values():
		var board_key: String = Enums.BoardType.keys()[board_type]
		if board_key not in state_data:
			continue
		for upgrade_type in Enums.UpgradeType.values():
			var upgrade_key: String = Enums.UpgradeType.keys()[upgrade_type]
			if upgrade_key not in state_data[board_key]:
				continue
			var entry: Dictionary = state_data[board_key][upgrade_key]
			var s: UpgradeState = _state[board_type][upgrade_type]
			s.level = entry.get("level", 0)
			s.cost = entry.get("cost", 0)
			s.delta = entry.get("delta", 0)
			s.current_cap = entry.get("current_cap", s.base_cap)
			s.cap_level = entry.get("cap_level", 0)

	# Restore unlocks
	var unlocked_data: Dictionary = data.get("unlocked", {})
	for board_type in Enums.BoardType.values():
		var board_key: String = Enums.BoardType.keys()[board_type]
		if board_key not in unlocked_data:
			continue
		for upgrade_type in Enums.UpgradeType.values():
			var upgrade_key: String = Enums.UpgradeType.keys()[upgrade_type]
			if upgrade_key not in unlocked_data[board_key]:
				continue
			if unlocked_data[board_key][upgrade_key]:
				unlock(board_type, upgrade_type)

	# Restore cap raise availability
	var cap_raise_data: Dictionary = data.get("cap_raise_available", {})
	for board_type in Enums.BoardType.values():
		var board_key: String = Enums.BoardType.keys()[board_type]
		if board_key in cap_raise_data and cap_raise_data[board_key]:
			_cap_raise_available[board_type] = true
			cap_raise_unlocked.emit(board_type)

	# Last: an old save may carry levels for an upgrade that has since been
	# retired. unlock() already refused the flag; this drops the rest.
	_clear_retired_state()

	# After levels are restored, so capacity() sees the real slot count — restore
	# drops any locks beyond it rather than honouring more than the player owns.
	# Deliberately LAST. CurrencyManager deserializes before this manager and ends
	# with notify_all(), which fires currency_changed for every currency — so the
	# lock set must still be empty at that point, or a load would auto-buy against
	# boards BoardManager has not configured yet. Moving this earlier breaks that.
	auto_buy_locks.restore(data.get("auto_buy_locks", []))


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
