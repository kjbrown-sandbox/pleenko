class_name AutoBuyLocks
extends RefCounted

## Which (board, upgrade) pairs the player has locked to auto-buy, and the rule
## for how many they may lock at once — red's signature upgrade.
##
## Pure RefCounted: no autoloads, no scene tree, no purchasing. UpgradeManager
## owns the instance and does the buying; this owns only the set and its rule,
## so the capacity semantics are testable without any currency in play.
##
## Locks are per (board, upgrade) PAIR: gold's Add Rows and orange's Add Rows are
## two separate locks. That follows how UpgradeManager stores levels, and it is
## why one slot buys comparatively little — there are six boards' worth of pairs
## to spend slots on.

## () -> int, how many pairs may be locked. Defaults to none so a bare instance
## refuses everything rather than silently allowing unlimited locks.
var capacity_fn: Callable = func() -> int: return 0

## "<BoardType>:<UpgradeType>" -> true. A Dictionary rather than an Array so
## membership is O(1) on the per-frame drain path.
var _locked: Dictionary = {}


## Stable key for a pair. Ints rather than enum names: this is what gets
## serialized, and names would break if an enum were ever renamed, while the
## ordinals are already treated as permanent (see Enums.UpgradeType).
static func key_for(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> String:
	return "%d:%d" % [int(board_type), int(upgrade_type)]


func capacity() -> int:
	return maxi(0, capacity_fn.call())


func count() -> int:
	return _locked.size()


func is_locked(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	return _locked.has(key_for(board_type, upgrade_type))


## Slots left. Negative capacity changes (a prestige reset mid-session) can leave
## more locked than allowed, so this floors at zero rather than going negative.
func free_slots() -> int:
	return maxi(0, capacity() - count())


## Whether locking this pair would be allowed right now. Already-locked pairs
## answer true so a caller can toggle one off without a capacity check.
func can_lock(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	return is_locked(board_type, upgrade_type) or count() < capacity()


## Toggles a pair. Returns the state it ended in, so the caller can tell the
## difference between "unlocked it" and "refused to lock it" — both leave the
## pair unlocked, and a UI that conflated them would silently swallow a click on
## a full slot roster.
func toggle(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> bool:
	var key: String = key_for(board_type, upgrade_type)
	if _locked.has(key):
		_locked.erase(key)
		return false
	if count() >= capacity():
		return false
	_locked[key] = true
	return true


func unlock(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> void:
	_locked.erase(key_for(board_type, upgrade_type))


## Every locked pair as {board_type, upgrade_type}, for the drain loop.
func pairs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: String in _locked:
		var parts: PackedStringArray = key.split(":")
		if parts.size() != 2:
			continue
		out.append({
			"board_type": int(parts[0]) as Enums.BoardType,
			"upgrade_type": int(parts[1]) as Enums.UpgradeType,
		})
	return out


func clear() -> void:
	_locked.clear()


func serialize() -> Array:
	return _locked.keys()


## Restores from a save, dropping anything the current capacity no longer allows.
## Capacity can shrink between sessions (a prestige wipes upgrade levels), and
## silently running more auto-buys than the player owns slots for would be a
## quiet cheat rather than a visible one.
func restore(raw: Array) -> void:
	_locked.clear()
	var slots: int = capacity()
	for entry in raw:
		if not (entry is String):
			continue
		var parts: PackedStringArray = (entry as String).split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		if _locked.size() >= slots:
			break
		_locked[entry] = true
