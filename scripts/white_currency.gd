class_name WhiteCurrency

## Pure static rules for WHITE_COIN — the one tier-less currency in the game.
##
## White is minted ONLY by earring buckets (every board's earrings mint it) and
## spent ONLY on two things: drops on the late boards, and its own cap raises.
## It has no board, no upgrades, and no raw/refined pair, which is why
## TierRegistry.get_tier_for_currency returns null for it.
##
## Pure static module (same shape as Lattice / EarringGeometry): no scene tree,
## no autoloads, no VisualTheme. The mint curve and the gate table are the two
## things most likely to need balance passes, so they live here where they can be
## read and tested without standing up a board.

## Each tier mints white worth 3x the tier below: gold 1x, orange 3x, red 9x,
## violet 27x, blue 81x, green 243x. Gold earrings are the cheapest white in the
## game, green's the richest.
const TIER_MULTIPLIER := 3

## Tier INDEX (TierRegistry.get_tier_index) of the first board whose drops cost
## white. Everything below it is deliberately white-free, so the early and mid
## game play exactly as they did before white existed — a player first meets the
## currency at violet.
const FIRST_GATED_TIER_INDEX := 3

## White a single drop costs on each gated board, indexed from
## FIRST_GATED_TIER_INDEX: violet 1, blue 100, green 1000.
##
## Authored, NOT derived from TIER_MULTIPLIER. The jumps are far steeper than the
## x3 mint curve on purpose: violet's own earrings out-earn its drop cost and so
## sustain themselves, while blue and green run at a deliberate white deficit and
## have to be funded by the whole board stack's earrings. That asymmetry is the
## point — white is the one resource the endgame cannot farm locally.
const DROP_COSTS: Array[int] = [1, 100, 1000]

## Cap that white starts with, and the amount each cap raise adds. White has no
## next tier to price a raise against, so raises are paid in white itself.
const STARTING_CAP := 500
const CAP_RAISE_AMOUNT := 500


## Binomial coefficient C(n, k) — how many distinct left/right bounce sequences
## land a coin in column k of an n-row lattice. Iterative and integer-only:
## factorials overflow long before the row counts we care about stop being valid.
static func binomial(n: int, k: int) -> int:
	if k < 0 or k > n or n < 0:
		return 0
	var kk: int = mini(k, n - k)
	var result: int = 1
	for i in kk:
		result = result * (n - i) / (i + 1)
	return result


## White paid by one earring bucket at `col` of an `earring_rows`-row earring on
## a board at `tier_index`.
##
## The value is the binomial reciprocal 2^rows / C(rows, col), scaled by the
## tier multiplier. The reciprocal makes every bucket in an earring worth the
## same in EXPECTATION — a bucket reached one time in 256 pays 256 — so the
## payout is mathematically fair but wildly swingy. That is the entire point: an
## earring is a lottery, not a wage. The two corners are the jackpots and the
## middle is small change.
##
## Rounded to an int (currencies are ints) and floored at 1, so the shallow
## middle of a large earring can never pay nothing.
static func bucket_value(earring_rows: int, col: int, tier_index: int) -> int:
	var ways: int = binomial(earring_rows, col)
	if ways <= 0:
		return 1
	var fair: float = pow(2.0, float(earring_rows)) / float(ways)
	var scaled: float = fair * pow(float(TIER_MULTIPLIER), float(maxi(0, tier_index)))
	return maxi(1, roundi(scaled))


## Expected white per coin that enters an earring of this size, before the tier
## multiplier. Because every bucket is EV-equal at 1 "fair unit", the expectation
## is just the bucket count — a handy sanity check for balance passes, and the
## reason the curve needs no separate normalisation constant.
static func expected_value_units(earring_rows: int) -> int:
	return earring_rows + 1


## True when drops on the board at `tier_index` require white.
static func is_gated_tier(tier_index: int) -> bool:
	return tier_index >= FIRST_GATED_TIER_INDEX


## White a single drop costs on the board at `tier_index`, or 0 when that board is
## not gated. Reads the authored DROP_COSTS table — the primary balance knob.
##
## A tier past the end of the table reuses the last entry rather than running off
## it, so appending a seventh tier degrades to "as expensive as green" instead of
## crashing.
static func drop_cost(tier_index: int) -> int:
	if not is_gated_tier(tier_index):
		return 0
	var idx: int = tier_index - FIRST_GATED_TIER_INDEX
	return DROP_COSTS[mini(idx, DROP_COSTS.size() - 1)]
