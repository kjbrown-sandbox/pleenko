class_name ForbiddenBucketHazardRuntime
extends ChallengeHazardRuntime

## Runtime for a ForbiddenBucketHazard. Marks the bucket as forbidden on
## setup; fails the challenge if any coin lands in it. (Degenerate runtime by
## design — no _process work — but follows the uniformity contract so all
## hazards have the same lifecycle.)

var hazard: ForbiddenBucketHazard


func setup(board_manager: BoardManager) -> void:
	super.setup(board_manager)
	var board := _get_board(hazard.board_type)
	if board:
		board.mark_bucket_forbidden(hazard.bucket_index)


func on_coin_landed(board_type: Enums.BoardType, bucket_index: int, _currency_type: Enums.CurrencyType, _amount: int, _multiplier: float) -> void:
	if board_type == hazard.board_type and bucket_index == hazard.bucket_index:
		# Failure string preserved verbatim — tests + existing UX depend on it.
		fail_challenge_fn.call("Landed in forbidden bucket!")
