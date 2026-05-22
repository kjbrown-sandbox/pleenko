class_name CapRaiseRevealAnimator
extends Node

## Plays the once-per-board-tier "cap-raise reveal": when a coin first earns a
## raw currency after a prestige, this borrows the camera for a brief zoom +
## gentle slow-mo. On landing it bursts a stream of cap-raise-currency-colored
## particles from the coin and swoops them to the first cap "+" button; the
## top-left caps explode + reveal in turn, the stream then swoops right to the
## board's upgrade panel, and those caps explode + reveal. The player's eye
## follows the energy to every new button (the level-up "burst + swoop" idiom).
##
## This is NOT prestige. It does not change game state, reload a scene, touch
## PrestigeManager, or enter a PrestigePhase — it sets Engine.time_scale directly
## and restores it, and is fully reversible/abortable with no game-state effect.
## It bails when a prestige is already running and aborts if one starts. The
## trigger clause "this coin is not a prestige coin" lives in
## PlinkoBoard._will_reveal_cap_raise.
##
## Structure follows AutodropperIntroAnimator (child of Main, wired by
## Main._setup_normal(), not active during challenges); per-board signal wiring
## follows PrestigeAnimator (connect_board with an is_connected guard).
##
## Uses PROCESS_MODE_ALWAYS so the camera-follow _process runs at real-time
## speed despite the slow-mo Engine.time_scale.

const _PARTICLE_SIZE := Vector2(6, 6)
const _POP_IN_DURATION := 0.28          ## Seconds for a revealed "+" button to scale in
const _POP_IN_START_SCALE := 0.3        ## Scale a "+" button pops in from

## Set by Main before connect_board — Main.apply_input_lock. Mirrors PeekAnimator.
var apply_input_lock_fn: Callable

var _camera: Camera3D
var _board_manager: BoardManager
var _coin_values: Node                  ## CoinValues HUD (untyped — see main.gd)
var _canvas_layer: CanvasLayer

var _is_animating := false
var _torn_down := false
var _following := false                 ## true while _process should track the coin

var _target_coin: Coin
var _upgrade_section: UpgradeSection     ## the cap-raise board's upgrade panel
var _explosion_color: Color
var _camera_held := false
var _overlay: Control                   ## screen-space parent for the 2D explosion particles
var _peek_animator: PeekAnimator        ## new-board peek is deferred until the reveal finishes
var _coin_screen_pos: Vector2           ## where the coin landed on screen — the swoop's origin


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func setup(camera: Camera3D, board_manager: BoardManager, coin_values: Node,
		canvas_layer: CanvasLayer, peek_animator: PeekAnimator) -> void:
	_camera = camera
	_board_manager = board_manager
	_coin_values = coin_values
	_canvas_layer = canvas_layer
	_peek_animator = peek_animator
	PrestigeManager.prestige_phase_changed.connect(_on_prestige_phase_changed)


## Wire a board's cap_raise_coin_landed signal. Idempotent — Main calls this for
## every board at setup AND for boards unlocked mid-session.
func connect_board(board: PlinkoBoard) -> void:
	if not board.cap_raise_coin_landed.is_connected(_on_cap_raise_coin_landed):
		board.cap_raise_coin_landed.connect(_on_cap_raise_coin_landed)


func _on_cap_raise_coin_landed(coin: Coin, predicted_bucket: Bucket) -> void:
	if _is_animating:
		return
	# Defensive: the animator is only setup() in normal mode (challenges bypass
	# it), so a stray signal without setup must no-op rather than crash.
	if not is_instance_valid(_board_manager):
		return
	# Prestige owns the camera + time_scale — never run the two concurrently.
	if PrestigeManager.current_phase != PrestigeManager.PrestigePhase.NONE:
		return
	if not is_instance_valid(coin) or not is_instance_valid(predicted_bucket):
		return
	var board: PlinkoBoard = coin.board
	if not is_instance_valid(board) or board != _board_manager.get_active_board():
		# Player navigated away mid-air — let the buttons appear normally.
		return

	_is_animating = true
	_torn_down = false
	_target_coin = coin
	_upgrade_section = board.upgrade_section
	var cap_currency: int = TierRegistry.cap_raise_currency(board.board_type)
	_explosion_color = ThemeProvider.theme.get_coin_color(cap_currency)

	_apply_input_lock(true)
	_board_manager.begin_cinematic_camera()
	_camera_held = true
	_coin_values.begin_cap_raise_reveal(board.board_type)
	if is_instance_valid(_upgrade_section):
		_upgrade_section.begin_cap_raise_reveal()
	if is_instance_valid(_peek_animator):
		# Hold any new-board peek until this reveal sequence has finished.
		_peek_animator.set_drain_deferred(true)

	Engine.time_scale = ThemeProvider.theme.cap_raise_slow_mo_scale
	coin.landed.connect(_on_coin_landed, CONNECT_ONE_SHOT)
	_following = true
	set_process(true)


func _process(delta: float) -> void:
	if not _following:
		return
	if not is_instance_valid(_target_coin) or not is_instance_valid(_camera):
		# Coin vanished before landing — wrap up gracefully.
		_on_coin_landed(null)
		return
	# Recover real delta: a _process delta is already multiplied by
	# Engine.time_scale, so divide it back out — the camera then tracks at a
	# constant real-time rate despite the slow-mo. Same correction
	# prestige_animator / coin_burst_field use; the maxf floor guards a freeze.
	var real_delta: float = delta / maxf(Engine.time_scale, 0.0001)
	var t: VisualTheme = ThemeProvider.theme
	var f: float = minf(real_delta * t.cap_raise_camera_follow_rate, 1.0)
	var coin_pos: Vector3 = _target_coin.global_position
	var target: Vector3 = Vector3(coin_pos.x, coin_pos.y, _camera.global_position.z)
	_camera.global_position = _camera.global_position.lerp(target, f)
	_camera.size = lerpf(_camera.size, t.cap_raise_zoom_size, f)


func _on_coin_landed(_coin: Coin) -> void:
	if not _following:
		return
	_following = false
	set_process(false)
	# Capture where the coin landed on screen — the swoop stream starts here.
	# Fall back to screen centre if the coin vanished before landing.
	_coin_screen_pos = get_viewport().get_visible_rect().size * 0.5
	if is_instance_valid(_target_coin) and is_instance_valid(_camera):
		_coin_screen_pos = _camera.unproject_position(_target_coin.global_position)
	_target_coin = null
	Engine.time_scale = 1.0
	# Camera hold + zoom-out runs in parallel so the orange burst can fire the
	# instant the coin lands rather than after the hold.
	_hold_then_release_camera()
	_run_reveal_sequence()


## Carries a swooping particle stream from the coin to the top-left caps, and
## from there to the board panel. The orange burst fires the instant the coin
## lands; the camera hold + zoom-out runs in parallel (_hold_then_release_camera).
func _run_reveal_sequence() -> void:
	var t: VisualTheme = ThemeProvider.theme

	_overlay = Control.new()
	_overlay.top_level = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_overlay)

	# The orange particles burst from the coin the instant it lands. CRITICAL:
	# the cap-raise coin earns the first raw currency, so CoinValues rebuilds its
	# bars on a deferred call THIS frame (a new raw-currency bar appears) — every
	# old bar/button is freed. The cap-raise targets MUST be queried after that
	# rebuild, never before; the burst's scatter phase is that settle window.
	var particles: Array[ColorRect] = _spawn_burst(_coin_screen_pos)
	await get_tree().create_timer(t.cap_raise_swoop_burst_duration).timeout
	if not _is_animating:
		return

	# Pull the freshly-wired (hidden) cap buttons in three groups, revealed in
	# the player's reading order: currency-bar caps, then universal-upgrade
	# caps, then the board's own upgrade panel.
	var currency_targets: Array[Dictionary] = _coin_values.get_pending_currency_cap_targets()
	var universal_targets: Array[Dictionary] = _coin_values.get_pending_universal_cap_targets()
	var board_targets: Array[Dictionary] = []
	if is_instance_valid(_upgrade_section):
		board_targets = _upgrade_section.get_pending_cap_raise_targets()

	# The burst particles swoop up to the first HUD cap.
	var first_hud: Array[Dictionary] = currency_targets if not currency_targets.is_empty() else universal_targets
	if not first_hud.is_empty():
		await _swoop_travel(particles, _target_pos(first_hud[0]))
	else:
		_free_particles(particles)

	# 1. Currency-bar caps explode.
	if not currency_targets.is_empty() and _is_animating:
		await _reveal_each(currency_targets)
	# 2. The freshly-earned raw-currency bar fades into the HUD.
	if _is_animating:
		_coin_values.reveal_delayed_currency_bar()
	# 3. Universal-upgrade caps explode.
	if not universal_targets.is_empty() and _is_animating:
		await _reveal_each(universal_targets)
	# 4. The stream swoops over to the right; the board's own caps explode.
	if not board_targets.is_empty() and _is_animating:
		var last_hud: Array[Dictionary] = universal_targets if not universal_targets.is_empty() else currency_targets
		var swoop_from: Vector2 = _coin_screen_pos
		if not last_hud.is_empty():
			swoop_from = _target_pos(last_hud[last_hud.size() - 1])
		await _swoop(swoop_from, _target_pos(board_targets[0]))
		await _reveal_each(board_targets)

	# Let the last explosion settle, then _teardown releases the deferred peek
	# so the camera pans to the newly-unlocked board only after the reveal.
	if _is_animating:
		await get_tree().create_timer(t.cap_raise_peek_delay).timeout

	_teardown()


## Holds the zoom on the coin a beat after landing, then returns the camera to
## the board. Runs in parallel with the particle swoop so the orange burst fires
## the instant the coin lands. _teardown covers the camera if this never runs.
func _hold_then_release_camera() -> void:
	await get_tree().create_timer(ThemeProvider.theme.cap_raise_hold_duration).timeout
	if _is_animating and _camera_held:
		_board_manager.end_cinematic_camera()
		_camera_held = false


## Explode + reveal each target in turn, cap_raise_explosion_interval apart.
func _reveal_each(targets: Array) -> void:
	var t: VisualTheme = ThemeProvider.theme
	for target in targets:
		if not _is_animating:
			return  # aborted — _teardown force-reveals the rest
		_explode_and_reveal(target)
		await get_tree().create_timer(t.cap_raise_explosion_interval).timeout


## Spawns a particle stream at `from_pos` and scatters it outward — the "burst"
## half of the level-up burst+swoop idiom. Returns the particles so a later
## _swoop_travel() can carry them to a destination.
func _spawn_burst(from_pos: Vector2) -> Array[ColorRect]:
	var particles: Array[ColorRect] = []
	if not is_instance_valid(_overlay):
		return particles
	var t: VisualTheme = ThemeProvider.theme
	for i in t.cap_raise_explosion_particle_count:
		var particle := ColorRect.new()
		particle.size = _PARTICLE_SIZE
		particle.color = _explosion_color
		particle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		particle.position = from_pos - _PARTICLE_SIZE * 0.5
		_overlay.add_child(particle)
		particles.append(particle)
		var angle: float = randf() * TAU
		var dist: float = t.cap_raise_explosion_radius * randf_range(0.4, 1.0)
		var scatter: Vector2 = particle.position + Vector2(cos(angle), sin(angle)) * dist
		var burst_dur: float = t.cap_raise_swoop_burst_duration * randf_range(0.7, 1.0)
		particle.create_tween().tween_property(particle, "position", scatter, burst_dur) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	return particles


## Swoops an already-spawned particle stream to `to_pos`, each particle freeing
## itself on arrival. Awaits the longest possible travel so the stream has
## fully landed before the caller's next beat.
func _swoop_travel(particles: Array[ColorRect], to_pos: Vector2) -> void:
	if not _is_animating:
		_free_particles(particles)
		return
	var t: VisualTheme = ThemeProvider.theme
	var dest: Vector2 = to_pos - _PARTICLE_SIZE * 0.5
	for particle in particles:
		if not is_instance_valid(particle):
			continue
		var swoop_dur: float = t.cap_raise_swoop_duration * randf_range(0.85, 1.15)
		var tween := particle.create_tween()
		tween.tween_property(particle, "position", dest, swoop_dur) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(particle.queue_free)
	await get_tree().create_timer(t.cap_raise_swoop_duration * 1.15).timeout


## Burst + scatter + swoop in one call — the level-up "burst + swoop" idiom.
## Used for the HUD→board hop, which happens well after the CoinValues rebuild
## so it needs no settle window of its own.
func _swoop(from_pos: Vector2, to_pos: Vector2) -> void:
	if not _is_animating:
		return
	var particles: Array[ColorRect] = _spawn_burst(from_pos)
	await get_tree().create_timer(ThemeProvider.theme.cap_raise_swoop_burst_duration).timeout
	if not _is_animating:
		_free_particles(particles)
		return
	await _swoop_travel(particles, to_pos)


## Frees an un-swooped particle stream (abort, or no target to travel to).
func _free_particles(particles: Array[ColorRect]) -> void:
	for particle in particles:
		if is_instance_valid(particle):
			particle.queue_free()


## Screen point a target's swoop/explosion centres on — its "+" button spot.
func _target_pos(target: Dictionary) -> Vector2:
	var node: Control = target.get("node")
	if is_instance_valid(node):
		return _button_screen_pos(node)
	return _coin_screen_pos


func _explode_and_reveal(target: Dictionary) -> void:
	var node: Control = target.get("node")
	var plus_button: Control = target.get("plus_button")
	var reveal: Callable = target.get("reveal")
	if is_instance_valid(node):
		_spawn_explosion(_button_screen_pos(node))
	if reveal.is_valid():
		reveal.call()
	if is_instance_valid(plus_button):
		_pop_in(plus_button)


## Screen-space point to centre an explosion on — the row's right edge, where
## the "+" button materialises (it is roughly as wide as the row is tall).
func _button_screen_pos(node: Control) -> Vector2:
	var rect: Rect2 = node.get_global_rect()
	return Vector2(rect.end.x - rect.size.y * 0.5, rect.get_center().y)


## A radial 2D firework of cap-raise-currency-colored particles at `center`.
func _spawn_explosion(center: Vector2) -> void:
	if not is_instance_valid(_overlay):
		return
	var t: VisualTheme = ThemeProvider.theme
	for i in t.cap_raise_explosion_particle_count:
		var particle := ColorRect.new()
		particle.size = _PARTICLE_SIZE
		particle.color = _explosion_color
		particle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		particle.position = center - _PARTICLE_SIZE * 0.5
		_overlay.add_child(particle)

		var angle: float = randf() * TAU
		var dist: float = t.cap_raise_explosion_radius * randf_range(0.5, 1.0)
		var dest: Vector2 = particle.position + Vector2(cos(angle), sin(angle)) * dist
		var dur: float = t.cap_raise_explosion_duration * randf_range(0.7, 1.0)

		var tween := particle.create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "position", dest, dur) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(particle, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(particle.queue_free)


## Scale-in pop so a revealed "+" button reads as created by its explosion.
func _pop_in(button: Control) -> void:
	button.pivot_offset = button.size * 0.5
	button.scale = Vector2(_POP_IN_START_SCALE, _POP_IN_START_SCALE)
	var tween := button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, _POP_IN_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _on_prestige_phase_changed(phase: PrestigeManager.PrestigePhase) -> void:
	# A prestige must own the camera + time_scale alone — abort if one starts.
	if phase != PrestigeManager.PrestigePhase.NONE and _is_animating:
		_teardown()


func _exit_tree() -> void:
	_teardown()


## Idempotent full restore — runs on normal finish, prestige abort, and scene
## teardown. The panels' end_cap_raise_reveal() force-shows every cap "+" button
## that the sequence did not reach, so none can be stranded.
func _teardown() -> void:
	if _torn_down or not _is_animating:
		return
	_torn_down = true
	_is_animating = false
	_following = false
	set_process(false)
	_target_coin = null
	Engine.time_scale = 1.0
	if _camera_held and is_instance_valid(_board_manager):
		_board_manager.end_cinematic_camera()
	_camera_held = false
	if is_instance_valid(_coin_values):
		_coin_values.end_cap_raise_reveal()
	if is_instance_valid(_upgrade_section):
		_upgrade_section.end_cap_raise_reveal()
	_upgrade_section = null
	if is_instance_valid(_overlay):
		_overlay.queue_free()
		_overlay = null
	_apply_input_lock(false)
	# Release the new-board peek — it drains now (or stays empty if none queued).
	if is_instance_valid(_peek_animator):
		_peek_animator.set_drain_deferred(false)


func _apply_input_lock(locked: bool) -> void:
	if apply_input_lock_fn.is_valid():
		apply_input_lock_fn.call(locked)
