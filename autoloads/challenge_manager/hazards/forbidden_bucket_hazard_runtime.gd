class_name ForbiddenBucketHazardRuntime
extends ChallengeHazardRuntime

## Runtime for a ForbiddenBucketHazard. Marks the bucket as forbidden on setup;
## on contact, detonates a circular blast around it (pegs + buckets fall, blast
## radius added to PlinkoBoard's voided-radii set so future coins fall through).
## The challenge KEEPS RUNNING — destruction is permanent damage, not a fail.

var hazard: ForbiddenBucketHazard


func setup(board_manager: BoardManager) -> void:
	super.setup(board_manager)
	var board := _get_board(hazard.board_type)
	if board:
		board.mark_bucket_forbidden(hazard.bucket_index)


func on_coin_landed(board_type: Enums.BoardType, bucket_index: int, _currency_type: Enums.CurrencyType, _amount: int, _multiplier: float) -> void:
	if board_type != hazard.board_type or bucket_index != hazard.bucket_index:
		return
	# Defer one frame: this listener fires from inside PlinkoBoard.coin_landed.emit,
	# mid-`finalize_coin_landing`. Detonating here would vaporise the just-landed
	# coin while the rest of finalize_coin_landing still references it. A
	# call_deferred runs after the landing event finishes — boom on the very next
	# frame, indistinguishable visually.
	detonate_radius_fn.call_deferred(hazard.board_type, hazard.bucket_index, hazard.detonation_radius)
