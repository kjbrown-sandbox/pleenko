class_name BombHazardRuntime
extends ChallengeHazardRuntime

## Lifecycle owner for a BombHazard. Per-bomb state lives here; the board owns
## the per-bucket visual + defuse multiplier so finalize_coin_landing applies
## the multiplier consistently with the gameplay-target mechanic.
##
## Flow (per bomb):
##   spawn → tick down → on integer-second update countdown label
##     → coin lands here?  -> defuse (apply multiplier, repick + reset timer)
##     → timer hits zero?  -> detonate (void_column, repick + reset timer)
##
## Repick uses `get_reachable_buckets_fn` minus other live bomb buckets, so
## bombs never overlap and never spawn in a voided column.

var hazard: BombHazard

# Live bombs: one entry per active bomb. Bucket index = -1 → "needs a slot"
# (e.g. no reachable buckets at spawn — placeholder until one frees up).
var _bombs: Array[Dictionary] = []


func setup(board_manager: BoardManager) -> void:
	super.setup(board_manager)
	_bombs.clear()
	for i in hazard.bomb_count:
		_spawn_bomb()
	set_process(true)


func _process(delta: float) -> void:
	if not _ticking:
		return
	if _bombs.is_empty():
		return
	for bomb in _bombs:
		if bomb["bucket_index"] < 0:
			# Tried to spawn but no targetable buckets — keep trying.
			_try_repick(bomb)
			continue
		bomb["time_remaining"] -= delta
		var new_sec: int = maxi(0, int(ceil(bomb["time_remaining"])))
		if new_sec != bomb["last_int_second"]:
			bomb["last_int_second"] = new_sec
			_apply_countdown(bomb)
		if bomb["time_remaining"] <= 0.0:
			_detonate(bomb)


func on_coin_landed(_board_type: Enums.BoardType, bucket_index: int, _currency_type: Enums.CurrencyType, _amount: int, _multiplier: float) -> void:
	if _board_type != hazard.board_type:
		return
	for bomb in _bombs:
		if bomb["bucket_index"] == bucket_index:
			_defuse(bomb)
			return


func disconnect_all() -> void:
	var board := _get_board(hazard.board_type)
	if board:
		for bomb in _bombs:
			if bomb["bucket_index"] >= 0:
				board.unmark_bucket_bomb(bomb["bucket_index"])
	_bombs.clear()


# ── Internals ───────────────────────────────────────────────────────

func _spawn_bomb() -> void:
	var bomb: Dictionary = {
		"bucket_index": -1,
		"time_remaining": hazard.timer_seconds,
		"last_int_second": -1,
	}
	_bombs.append(bomb)
	_try_repick(bomb)


func _try_repick(bomb: Dictionary) -> void:
	var taken: PackedInt32Array = PackedInt32Array()
	for other in _bombs:
		if other != bomb and other["bucket_index"] >= 0:
			taken.append(other["bucket_index"])
	var allowed: PackedInt32Array = PackedInt32Array()
	# Targetable, not just reachable: skip edges + voided buckets. A bomb on
	# an edge bucket would detonate into nothing because edge columns have no
	# pegs above them.
	for idx in get_reachable_buckets_fn.call(hazard.board_type):
		if not taken.has(idx):
			allowed.append(idx)
	if allowed.is_empty():
		bomb["bucket_index"] = -1
		return
	var next_idx: int = WanderingBucketSelector.pick(allowed, bomb["bucket_index"], rng_fn)
	bomb["bucket_index"] = next_idx
	bomb["time_remaining"] = _synced_initial_time_remaining()
	bomb["last_int_second"] = int(ceil(bomb["time_remaining"]))
	var board := _get_board(hazard.board_type)
	if board:
		board.mark_bucket_bomb(next_idx, hazard.defuse_multiplier)
		board.set_bomb_countdown(next_idx, bomb["last_int_second"])
		board.bomb_spawned.emit(hazard.board_type, next_idx, hazard.timer_seconds)


## time_remaining for a freshly-placed bomb, synced to the challenge timer's
## integer-second beat. Without this, a defuse mid-beat would start the next
## countdown immediately, ticking down on its own off-beat cadence for the
## rest of its life. With it, the bomb's first tick lands on the next beat;
## subsequent ticks ride the same rhythm as the challenge timer + audio.
##
## Pre-ticking (initial spawn at challenge setup) skips the sync — at that
## point the challenge timer is still parked at its integer starting value,
## so straight `timer_seconds` is already aligned and gives the full fuse.
func _synced_initial_time_remaining() -> float:
	if not _ticking:
		return hazard.timer_seconds
	var ct: float = ChallengeManager.get_time_remaining()
	var time_until_next_beat: float = fmod(ct, 1.0)
	if time_until_next_beat <= 0.0001:
		return hazard.timer_seconds
	# (timer_seconds - 1) + tubn — ceil is still timer_seconds initially,
	# and the first integer crossing happens exactly `tubn` seconds from now,
	# matching the challenge timer's next tick.
	return (hazard.timer_seconds - 1.0) + time_until_next_beat


func _apply_countdown(bomb: Dictionary) -> void:
	var board := _get_board(hazard.board_type)
	if not board:
		return
	board.set_bomb_countdown(bomb["bucket_index"], bomb["last_int_second"])
	AudioManager.play_bomb_tick(bomb["last_int_second"], hazard.board_type)


func _defuse(bomb: Dictionary) -> void:
	var board := _get_board(hazard.board_type)
	if board:
		board.unmark_bucket_bomb(bomb["bucket_index"])
		board.bomb_defused.emit(hazard.board_type, bomb["bucket_index"], hazard.defuse_multiplier)
	AudioManager.play_bomb_defuse(hazard.board_type)
	bomb["bucket_index"] = -1
	_try_repick(bomb)


func _detonate(bomb: Dictionary) -> void:
	var detonated_index: int = bomb["bucket_index"]
	var board := _get_board(hazard.board_type)
	if board:
		board.unmark_bucket_bomb(detonated_index)
		board.bomb_detonated.emit(hazard.board_type, detonated_index)
	# void_column() fires the detonation SFX itself — don't double-play here
	# or two pool players stack and undo the -14 dB ceiling we set.
	void_column_fn.call(hazard.board_type, detonated_index)
	bomb["bucket_index"] = -1
	_try_repick(bomb)
