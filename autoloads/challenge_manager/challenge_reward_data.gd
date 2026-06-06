class_name ChallengeRewardData
extends Resource

enum RewardType {
	UNLOCK,
	STARTING_MODIFIER,
	PERMANENT_UPGRADE,
}

enum UnlockType {
	HOLD_TO_DROP,
}

# Append-only: ChallengeProgressManager serializes modifier_type by ordinal
# (no version guard), so reordering or inserting values silently corrupts
# existing saves. Add new modifiers at the end only.
enum ModifierType {
	STARTING_AUTODROPPERS,
	STARTING_COINS,
	MULTI_DROP,
	ADVANCED_COIN_MULTIPLIER,  # DORMANT: raw/advanced coins removed (single-currency model)
	BUCKET_VALUE_PERCENT,
	GOLD_COIN_SPEED_BOOST,
	QUEUE_RATE_BONUS,
	CENTER_BUCKET_VALUE,        # flat +N to the board's middle bucket (doesn't scale via upgrades)
	DROP_COST_REDUCTION,        # -N fuel currency per drop on this board (floored at 1)
	GOLDEN_BUCKET_MULTIPLIER,   # +N to the wandering golden-bucket payout (base 2x)
}

@export var type: RewardType
@export var unlock_type: UnlockType
@export var modifier_type: ModifierType
@export var modifier_amount: float = 1.0
@export var currency_type: Enums.CurrencyType
@export var board_type: Enums.BoardType
@export var upgrade_type: Enums.UpgradeType


## Canonical human-readable reward text. Single source of truth — used by both
## the pre-challenge info panel and the post-challenge reward modal so the two
## can never drift. Generated from the structured fields; there is no
## hand-written description string.
func display_text() -> String:
	match type:
		RewardType.UNLOCK:
			return "Unlocked: %s" % UnlockType.keys()[unlock_type].capitalize().replace("_", " ")
		RewardType.STARTING_MODIFIER:
			return _starting_modifier_text()
		RewardType.PERMANENT_UPGRADE:
			# board_type/upgrade_type both lower-cased so they read inline
			# as one phrase ("+1 gold drop rate level").
			var board: String = FormatUtils.board_name(board_type, false)
			var upgrade: String = FormatUtils.upgrade_name(upgrade_type)
			return "+%d %s %s level" % [int(modifier_amount), board, upgrade]
	return ""


func _starting_modifier_text() -> String:
	# Board name used as a lower-case adjective, never a "(Board)" parenthetical.
	var board: String = FormatUtils.board_name(board_type, false)
	match modifier_type:
		ModifierType.STARTING_COINS:
			return "+%d starting %s" % [int(modifier_amount), FormatUtils.currency_name(currency_type, false)]
		ModifierType.MULTI_DROP:
			return "+%d %s multi-drop" % [int(modifier_amount), board]
		ModifierType.ADVANCED_COIN_MULTIPLIER:
			# board_type is intentionally ignored: this reward only ever applies
			# to the gold board, whose advanced buckets pay out raw orange
			# (gold-only by design, like GOLD_COIN_SPEED_BOOST).
			return "+%.1f raw orange multiplier" % modifier_amount
		ModifierType.BUCKET_VALUE_PERCENT:
			return "+%d%% %s bucket value" % [int(modifier_amount * 100), board]
		ModifierType.CENTER_BUCKET_VALUE:
			return "+%d %s middle bucket value" % [int(modifier_amount), board]
		ModifierType.DROP_COST_REDUCTION:
			# Cost is paid in the previous tier's primary currency (the "fuel").
			var prev: TierData = TierRegistry.get_previous_tier(board_type)
			var fuel: String = FormatUtils.currency_name(prev.primary_currency, false) if prev else "fuel"
			return "%s coins cost %d less %s" % [board.capitalize(), int(modifier_amount), fuel]
		ModifierType.GOLDEN_BUCKET_MULTIPLIER:
			return "+%.1f %s golden bucket multiplier" % [modifier_amount, board]
		ModifierType.STARTING_AUTODROPPERS:
			return "+%d starting %s autodroppers" % [int(modifier_amount), board]
		# GOLD_COIN_SPEED_BOOST / QUEUE_RATE_BONUS pull their magnitude live from
		# the gameplay constants — those constants are the canonical source for
		# the displayed numbers, so the text can never go stale against them.
		ModifierType.GOLD_COIN_SPEED_BOOST:
			return "+%d%% gold coin fall speed" % int(Coin.COIN_SPEED_BOOST_PER_UNLOCK * 100)
		ModifierType.QUEUE_RATE_BONUS:
			return "+%d%% gold queue bonus" % int(PlinkoBoard.QUEUE_RATE_BONUS_PER_UNLOCK * 100)
	return ""
