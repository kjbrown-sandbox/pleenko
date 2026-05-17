class_name Enums

enum BoardType {
	GOLD,
	ORANGE,
	RED,
	VIOLET,
	BLUE,
	GREEN
}

enum CurrencyType {
	GOLD_COIN,
	RAW_ORANGE,
	ORANGE_COIN,
	RAW_RED,
	RED_COIN,
	RAW_VIOLET,
	VIOLET_COIN,
	RAW_BLUE,
	BLUE_COIN,
	RAW_GREEN,
	GREEN_COIN
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
