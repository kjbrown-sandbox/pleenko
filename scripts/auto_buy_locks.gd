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

## "<BoardType>:<UpgradeType>" -> {board_type, upgrade_type}.
##
## The VALUE is the already-decoded pair, not just `true`: pairs() is read on
## every currency change (i.e. every coin landing), and re-splitting the key
## string there would allocate per lock per landing to undo an encoding we
## control. The string stays the KEY because that is what gets serialized —
## JSON-safe, and stable across an enum rename.
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
	_locked[key] = {"board_type": board_type, "upgrade_type": upgrade_type}
	return true



## Every locked pair as {board_type, upgrade_type}, for the drain loop. A fresh
## Array each call, so a caller may mutate the lock set while iterating.
func pairs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_locked.values())
	return out


func clear() -> void:
	_locked.clear()


func serialize() -> Array:
	return _locked.keys()


## Restores from a save, dropping anything the current capacity no longer allows.
## Capacity can shrink between sessions (a prestige wipes upgrade levels), and
## silently running more auto-buys than the player owns slots for would be a
## quiet cheat rather than a visible one.
##
## Ordinals are range-checked, not just parsed: an out-of-range board would reach
## UpgradeManager as _state[99] and raise mid-drain, which in GDScript (no
## `finally`) would leave the drain's re-entrancy flag latched and silently kill
## auto-buy for the rest of the session.
func restore(raw: Array) -> void:
	_locked.clear()
	var slots: int = capacity()
	for entry in raw:
		if not (entry is String):
			continue
		var parts: PackedStringArray = (entry as String).split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		var board_type: int = int(parts[0])
		var upgrade_type: int = int(parts[1])
		if not Enums.BoardType.values().has(board_type):
			continue
		if not Enums.UpgradeType.values().has(upgrade_type):
			continue
		if _locked.size() >= slots:
			break
		# Re-encode rather than reusing `entry`: a save could carry a key that
		# parses fine but is not byte-identical to what key_for produces ("01:2",
		# "+1:2"), and storing THAT would consume a slot is_locked() can never
		# match — a lock the player owns but can never see or release.
		_locked[key_for(board_type, upgrade_type)] = {
			"board_type": board_type, "upgrade_type": upgrade_type,
		}
