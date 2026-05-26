class_name ForbiddenBucketRevealAnimator
extends Node

## Plays a brief pre-landing zoom when a coin is about to fall into a forbidden
## bucket: borrows the camera + slows time so the player feels the impending
## detonation. On `coin.landed` it restores time, holds the zoom for a beat,
## then returns the camera to the active board. The actual radial explosion is
## owned by ForbiddenBucketHazardRuntime → PlinkoBoard.detonate_radius —
## this animator is camera-only, no destruction work.
##
## Structure mirrors CapRaiseRevealAnimator (PROCESS_MODE_ALWAYS so the
## camera-follow runs at real-time speed despite the slow-mo); the HUD reveal
## sequence + peek deferment are removed. Wired by Main._setup_challenge —
## forbidden buckets only exist in challenges, so this animator never runs in
## normal mode.

## Set by Main before connect_board — Main.apply_input_lock.
var apply_input_lock_fn: Callable

var _camera: Camera3D
var _board_manager: BoardManager

var _is_animating := false
var _torn_down := false
var _following := false                 ## true while _process should track the coin
var _camera_held := false

var _target_coin: Coin


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func setup(camera: Camera3D, board_manager: BoardManager) -> void:
	_camera = camera
	_board_manager = board_manager
	board_manager.board_switched.connect(_on_board_switched)
	PrestigeManager.prestige_phase_changed.connect(_on_prestige_phase_changed)


## Wire a board's forbidden_bucket_coin_landed signal. Idempotent — Main calls
## this for every board at setup AND for boards unlocked mid-challenge.
func connect_board(board: PlinkoBoard) -> void:
	if not board.forbidden_bucket_coin_landed.is_connected(_on_forbidden_bucket_coin_landed):
		board.forbidden_bucket_coin_landed.connect(_on_forbidden_bucket_coin_landed)


func _on_forbidden_bucket_coin_landed(coin: Coin, predicted_bucket: Bucket) -> void:
	if _is_animating:
		return
	if not is_instance_valid(_board_manager):
		return
	# Prestige owns the camera + time_scale — never run the two concurrently.
	if PrestigeManager.current_phase != PrestigeManager.PrestigePhase.NONE:
		return
	if not is_instance_valid(coin) or not is_instance_valid(predicted_bucket):
		return
	var board: PlinkoBoard = coin.board
	if not is_instance_valid(board) or board != _board_manager.get_active_board():
		# Player navigated away mid-air — let the detonation play unembellished.
		return

	_is_animating = true
	_torn_down = false
	_target_coin = coin

	_apply_input_lock(true)
	_board_manager.begin_cinematic_camera()
	_camera_held = true
	Engine.time_scale = ThemeProvider.theme.forbidden_zoom_slow_mo_scale
	# Beat grid + chord progression keep ticking at wall-clock rate so the
	# chord-bed doesn't stretch + active buckets stay in sync with their
	# audio chord during the zoom. Restored in _teardown.
	AudioManager.set_real_time_delta(true)
	coin.landed.connect(_on_coin_landed, CONNECT_ONE_SHOT)
	_following = true
	set_process(true)


func _process(delta: float) -> void:
	if not _following:
		return
	if not is_instance_valid(_target_coin) or not is_instance_valid(_camera):
		_on_coin_landed(null)
		return
	# A _process delta is already multiplied by Engine.time_scale, so divide it
	# back out — the camera tracks at a constant real-time rate during slow-mo.
	# Same correction CapRaiseRevealAnimator + PrestigeAnimator + CoinBurstField
	# all use; the maxf floor guards a freeze.
	var real_delta: float = delta / maxf(Engine.time_scale, 0.0001)
	var t: VisualTheme = ThemeProvider.theme
	var f: float = minf(real_delta * t.forbidden_camera_follow_rate, 1.0)
	var coin_pos: Vector3 = _target_coin.global_position
	var target: Vector3 = Vector3(coin_pos.x, coin_pos.y, _camera.global_position.z)
	_camera.global_position = _camera.global_position.lerp(target, f)
	_camera.size = lerpf(_camera.size, t.forbidden_zoom_size, f)


func _on_coin_landed(_coin: Coin) -> void:
	if not _is_animating or not _following:
		return
	_following = false
	set_process(false)
	_target_coin = null
	Engine.time_scale = 1.0
	# Hold the zoom briefly so the radial detonation reads as the punchline.
	await get_tree().create_timer(ThemeProvider.theme.forbidden_hold_duration).timeout
	if _torn_down:
		return
	_teardown()


func _on_prestige_phase_changed(phase: PrestigeManager.PrestigePhase) -> void:
	# Prestige must own the camera + time_scale alone — abort if one starts.
	if phase != PrestigeManager.PrestigePhase.NONE and _is_animating:
		_teardown()


func _on_board_switched(_board: PlinkoBoard) -> void:
	# A board switch mid-cinematic would strand the camera on the old board —
	# abort cleanly. Mirrors CapRaiseRevealAnimator's identical guard.
	if _is_animating:
		_teardown()


func _exit_tree() -> void:
	_teardown()


## Idempotent full restore — runs on normal finish, prestige abort, board switch,
## and scene teardown.
func _teardown() -> void:
	if _torn_down or not _is_animating:
		return
	_torn_down = true
	_is_animating = false
	_following = false
	set_process(false)
	_target_coin = null
	Engine.time_scale = 1.0
	AudioManager.set_real_time_delta(false)
	if _camera_held and is_instance_valid(_board_manager):
		_board_manager.end_cinematic_camera()
	_camera_held = false
	_apply_input_lock(false)


func _apply_input_lock(locked: bool) -> void:
	if apply_input_lock_fn.is_valid():
		apply_input_lock_fn.call(locked)
