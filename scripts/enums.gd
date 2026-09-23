class_name Enums

enum BoardType {
	GOLD,
	ORANGE,
	RED,
	VIOLET,
	BLUE,
	GREEN
}

## One entry per board colour, plus WHITE_COIN.
##
## Serialized by NAME in save files (CurrencyManager uses
## Enums.CurrencyType.keys()), but by ORDINAL in data/tiers/*.tres
## (`primary_currency = 1`) and mirrored as raw ints in visual_theme.gd /
## style_lab.gd. Reordering means editing all three.
##
## The former RAW_* currencies (the "unrefined" half of each tier) were retired
## along with the advanced-bucket system that paid them out; the enum was
## renumbered at the same time, so a save predating SAVE_VERSION 7 has its
## balances dropped rather than remapped.
enum CurrencyType {
	GOLD_COIN,
	ORANGE_COIN,
	RED_COIN,
	VIOLET_COIN,
	BLUE_COIN,
	GREEN_COIN,
	## Minted ONLY by earring buckets, on every board. Deliberately tier-less:
	## TierRegistry.get_tier_for_currency returns null for it, and its cap raises
	## are priced in white rather than a next tier's currency.
	WHITE_COIN,
}

enum UpgradeType {
	ADD_ROW,
	BUCKET_VALUE,
	DROP_RATE,
	QUEUE,
	AUTODROPPER,
	ADVANCED_AUTODROPPER,
	PEG_DEFLECTOR,  ## Always append last — .tres files and saves store `type` as an int.
}

## Left/right bounce convention. +1 = right (+x): moving RIGHT off lattice cell
## (row, col) lands on (row+1, col+1); LEFT on (row+1, col).
## See PlinkoBoard.next_lattice_cell / position_x_for.
enum Direction {
	LEFT = -1,
	RIGHT = 1,
}

enum PeekKind {
	BOARD,
	CHALLENGES,
}
