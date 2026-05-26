class_name ChallengeHazardRuntime
extends Node

## Live runtime for a ChallengeHazard. One runtime per authored hazard,
## parented to ChallengeTracker so _process, _exit_tree, and queue_free cascade
## work without extra wiring. Subclasses override the virtuals below.
##
## Callable seams (PeekAnimator precedent) — populated in setup() from the
## board/manager when not pre-injected. Tests inject deterministic variants.

var rng_fn: Callable  ## (max_exclusive: int) -> int
var get_reachable_buckets_fn: Callable  ## (board_type: Enums.BoardType) -> PackedInt32Array
var fail_challenge_fn: Callable  ## (reason: String) -> void
var void_column_fn: Callable  ## (board_type: Enums.BoardType, bucket_index: int) -> void
var detonate_radius_fn: Callable  ## (board_type: Enums.BoardType, bucket_index: int, radius: float) -> void

var _board_manager: BoardManager

## True once the challenge has actually started (the player has dropped a
## first coin). Until then, hazards exist visually but their countdowns are
## paused — fairer than ticking against a player who hasn't even engaged yet.
## ChallengeTracker calls start_ticking() once on the first coin_dropped.
var _ticking: bool = false


## Called by ChallengeTracker when the player drops their first coin. The
## default arms _ticking; subclasses can override for additional bookkeeping
## (e.g. reset countdown timers to full so spawn-to-arm delay is consistent).
func start_ticking() -> void:
	_ticking = true


## Called once after the tracker has connected to boards. Subclasses apply
## initial bucket markings, spawn live state, etc.
func setup(board_manager: BoardManager) -> void:
	_board_manager = board_manager
	if not rng_fn.is_valid():
		rng_fn = func(n: int) -> int: return randi() % maxi(1, n)
	if not get_reachable_buckets_fn.is_valid():
		get_reachable_buckets_fn = _default_get_reachable_buckets
	if not fail_challenge_fn.is_valid():
		fail_challenge_fn = _default_fail_challenge
	if not void_column_fn.is_valid():
		void_column_fn = _default_void_column
	if not detonate_radius_fn.is_valid():
		detonate_radius_fn = _default_detonate_radius


## Forwarded from ChallengeTracker._on_coin_landed. Override to react.
func on_coin_landed(_board_type: Enums.BoardType, _bucket_index: int, _currency_type: Enums.CurrencyType, _amount: int, _multiplier: float) -> void:
	pass


## Called when the tracker tears down (challenge ended). Subclasses clear
## bucket markings, kill tweens, etc. Matches the existing
## ChallengeTracker.disconnect_all() name so the codebase has one teardown verb.
func disconnect_all() -> void:
	pass


# ── Defaults for callable seams ───────────────────────────────────

func _default_get_reachable_buckets(board_type: Enums.BoardType) -> PackedInt32Array:
	var board := _get_board(board_type)
	if board:
		# "Targetable" not "reachable" — bombs only spawn at buckets where a
		# detonation would actually do damage (skips edges + voided buckets).
		return board.get_targetable_bucket_indices()
	return PackedInt32Array()


func _default_fail_challenge(reason: String) -> void:
	# Routed through the parent tracker so its single failed signal stays the
	# one source of truth for challenge failure.
	var parent: Node = get_parent()
	if parent and parent.has_method("hazard_fail"):
		parent.hazard_fail(reason)


func _default_void_column(board_type: Enums.BoardType, bucket_index: int) -> void:
	var board := _get_board(board_type)
	if board:
		board.void_column(bucket_index)


func _default_detonate_radius(board_type: Enums.BoardType, bucket_index: int, radius: float) -> void:
	var board := _get_board(board_type)
	if board:
		board.detonate_radius(bucket_index, radius)


func _get_board(board_type: Enums.BoardType) -> PlinkoBoard:
	if not _board_manager:
		return null
	for board in _board_manager.get_boards():
		if board.board_type == board_type:
			return board
	return null
