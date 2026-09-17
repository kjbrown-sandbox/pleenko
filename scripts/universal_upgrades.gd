class_name UniversalUpgrades

## Single source of truth for the "signature" upgrades — the one-per-colour
## upgrades that render in the CoinValues HUD instead of a board's own
## UpgradeSection, and whose effect is GLOBAL (one shared level, every board)
## even though UpgradeManager stores level/cost per board.
##
## Because the level is global but the storage is per-board, each one nominates
## ONE board to be booked under. That board is also where LevelManager grants the
## unlock, so the two must agree — if they drifted, the HUD row and the gameplay
## lookup would read different state and the upgrade would look unbought.
##
## Before this existed the pairing was hand-enumerated at six sites across two
## files. Adding the third (DUD_CHUTE) meant editing all six, and one of them
## (`_get_board_for_upgrade`) answered a miss with a plausible-looking wrong
## board rather than failing — so a missed site would have silently wired a cap
## button to the wrong board's cap. Adding the fourth is now one entry here.
## Listed in tier order for readability; `types()` sorts regardless, so a new
## entry appended here still displays in the right place.
const BOARDS: Dictionary = {
	Enums.UpgradeType.AUTODROPPER: Enums.BoardType.GOLD,
	Enums.UpgradeType.PEG_DEFLECTOR: Enums.BoardType.ORANGE,
	Enums.UpgradeType.AUTO_BUY: Enums.BoardType.RED,
	Enums.UpgradeType.DUD_CHUTE: Enums.BoardType.VIOLET,
	Enums.UpgradeType.BOARD_TILT: Enums.BoardType.BLUE,
	Enums.UpgradeType.LUCKY_PEG: Enums.BoardType.GREEN,
}


static func is_universal(upgrade_type: Enums.UpgradeType) -> bool:
	return BOARDS.has(upgrade_type)


## The board this upgrade's level is booked under. Deliberately has NO fallback:
## a type that isn't universal is a programming error, and a wrong-but-plausible
## answer here is worse than a hard failure.
static func board_for(upgrade_type: Enums.UpgradeType) -> Enums.BoardType:
	assert(BOARDS.has(upgrade_type), "not a universal upgrade")
	return BOARDS[upgrade_type]


## Every signature upgrade, in TIER order — gold, orange, red, violet, blue,
## green — which is the order the HUD lists them in and the order the player
## unlocks them.
##
## Sorted rather than relying on the literal's insertion order: a Dictionary
## iterates in insertion order, so the table would otherwise dictate the UI's
## ordering as a side effect of the order features happened to be BUILT in, and
## appending a seventh entry would silently put it last on screen regardless of
## which board it belongs to.
static func types() -> Array:
	var out: Array = BOARDS.keys()
	out.sort_custom(func(a: Enums.UpgradeType, b: Enums.UpgradeType) -> bool:
		return TierRegistry.get_tier_index(BOARDS[a]) < TierRegistry.get_tier_index(BOARDS[b]))
	return out


## True once the player owns any signature upgrade — drives whether the HUD
## shows its "Universal upgrades" section at all.
static func any_unlocked() -> bool:
	for upgrade_type: Enums.UpgradeType in BOARDS:
		if UpgradeManager.is_unlocked(BOARDS[upgrade_type], upgrade_type):
			return true
	return false
