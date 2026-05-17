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

## Left/right bounce convention. +1 = right (+x): a coin moving right does
## next_x = position.x + RIGHT * space_between_pegs / 2 (see Coin._bounce_or_despawn).
enum Direction {
	LEFT = -1,
	RIGHT = 1,
}

enum PeekKind {
	BOARD,
	CHALLENGES,
}
