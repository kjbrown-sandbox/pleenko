class_name PrestigeAnimator
extends Node

## Orchestrates the cinematic prestige sequence:
## 1. SLOW_MO: Camera zooms in on coin during its final bounce into the bucket
## 2. FREEZE: World freezes the moment coin touches the bucket
## 3. EXPAND: Coin turns palette-white and scales up to fill the entire screen
## 4. TRANSITION: Scene changes to PrestigeScreen
##
## Uses PROCESS_MODE_ALWAYS so _process runs at real-time speed despite Engine.time_scale.

const PrestigeScreenScene: PackedScene = preload("res://entities/prestige_screen/prestige_screen.tscn")

var _camera: Camera3D
var _is_animating: bool = false
var _target_coin: Coin
var _target_bucket: Bucket
var _original_camera_pos: Vector3
var _original_camera_size: float
var _phase_elapsed: float = 0.0
var _coin_has_landed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func setup(camera: Camera3D) -> void:
	_camera = camera


func connect_board(board: PlinkoBoard) -> void:
	if not board.prestige_coin_landed.is_connected(_on_prestige_coin_landed):
		board.prestige_coin_landed.connect(_on_prestige_coin_landed)


func _on_prestige_coin_landed(coin: Coin, predicted_bucket: Bucket) -> void:
	if _is_animating:
		return

	_is_animating = true
	_target_coin = coin
	_target_bucket = predicted_bucket
	_phase_elapsed = 0.0
	_coin_has_landed = false

	# Mark the coin so PlinkoBoard won't free it or add currency on landing
	coin.is_prestige_coin = true

	# Listen for when the coin actually lands (touches the bucket)
	coin.landed.connect(_on_prestige_coin_actually_landed, CONNECT_ONE_SHOT)

	# Store camera state for restore on abort
	_original_camera_pos = _camera.global_position
	_original_camera_size = _camera.size

	# Determine which board type is being prestiged
	for i in range(1, TierRegistry.get_tier_count()):
		var tier := TierRegistry.get_tier_by_index(i)
		if tier.raw_currency == predicted_bucket.currency_type:
			PrestigeManager.pending_board_type = tier.board_type
			break

	# Enter slow-mo — the coin is still mid-bounce, heading toward the bucket
	PrestigeManager.enter_phase(PrestigeManager.PrestigePhase.SLOW_MO)
	set_process(true)


func _on_prestige_coin_actually_landed(_coin: Coin) -> void:
	_coin_has_landed = true


func _process(delta: float) -> void:
	if not _is_animating:
		set_process(false)
		return

	# Recover real-time delta (Godot applies time_scale even with PROCESS_MODE_ALWAYS)
	var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
	_phase_elapsed += real_delta

	var t: VisualTheme = ThemeProvider.theme

	match PrestigeManager.current_phase:
		PrestigeManager.PrestigePhase.SLOW_MO:
			_process_slow_mo(real_delta, t)
		PrestigeManager.PrestigePhase.FREEZE:
			_process_freeze(t)
		PrestigeManager.PrestigePhase.EXPAND:
			_process_expand(real_delta, t)


func _process_slow_mo(real_delta: float, t: VisualTheme) -> void:
	if not is_instance_valid(_target_coin):
		_abort_animation()
		return

	# Lerp camera toward the coin as it bounces toward the bucket
	var coin_world_pos := _target_coin.global_position
	var target_cam_pos := Vector3(coin_world_pos.x, coin_world_pos.y, _camera.global_position.z)
	_camera.global_position = _camera.global_position.lerp(target_cam_pos, real_delta * 3.0)
	_camera.size = lerpf(_camera.size, t.prestige_camera_zoom_size, real_delta * 3.0)

	# Transition to FREEZE when the coin actually touches the bucket
	if _coin_has_landed:
		_phase_elapsed = 0.0
		PrestigeManager.enter_phase(PrestigeManager.PrestigePhase.FREEZE)


func _process_freeze(t: VisualTheme) -> void:
	# World is near-frozen. After a beat, start the coin expand.
	if _phase_elapsed >= t.prestige_freeze_duration:
		_phase_elapsed = 0.0
		_start_coin_expand()
		PrestigeManager.enter_phase(PrestigeManager.PrestigePhase.EXPAND)


func _process_expand(real_delta: float, t: VisualTheme) -> void:
	if not is_instance_valid(_target_coin):
		_transition_to_prestige_screen()
		return

	# Scale the coin up over time to fill the screen
	var progress: float = clampf(_phase_elapsed / t.prestige_expand_duration, 0.0, 1.0)
	# Ease in for a smooth acceleration
	var eased: float = progress * progress

	# Calculate scale needed to fill the orthographic view.
	# Camera.size is half the vertical extent, coin_radius is the mesh radius.
	var fill_scale: float = (_camera.size * 2.5) / maxf(t.coin_radius, 0.01)
	var current_scale: float = lerpf(1.0, fill_scale, eased)
	_target_coin.scale = Vector3.ONE * current_scale

	if _phase_elapsed >= t.prestige_expand_duration:
		_transition_to_prestige_screen()


func _start_coin_expand() -> void:
	if not is_instance_valid(_target_coin):
		return

	var t: VisualTheme = ThemeProvider.theme

	# Turn the coin palette-white
	var mesh_instance := _target_coin.get_node_or_null("MeshInstance3D")
	if mesh_instance:
		var white_mat := StandardMaterial3D.new()
		var palette_white: Color = t.resolve(VisualTheme.Palette.BG_6)
		white_mat.albedo_color = palette_white
		if t.unshaded:
			white_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_instance.material_override = white_mat

	# Snap camera to coin position so the coin is centered
	var coin_pos := _target_coin.global_position
	_camera.global_position = Vector3(coin_pos.x, coin_pos.y, _camera.global_position.z)


func _transition_to_prestige_screen() -> void:
	_is_animating = false
	set_process(false)

	# Clean up the coin
	if is_instance_valid(_target_coin):
		_target_coin.queue_free()

	# Trigger the actual prestige state change
	PrestigeManager.trigger_prestige(PrestigeManager.pending_board_type)
	PrestigeManager.enter_phase(PrestigeManager.PrestigePhase.TRANSITION)

	# Transition to the prestige screen instantly (coin already fills the screen white)
	SceneManager.set_new_scene(PrestigeScreenScene, true)


func _abort_animation() -> void:
	_is_animating = false
	set_process(false)
	PrestigeManager.reset_time_scale()
	_camera.global_position = _original_camera_pos
	_camera.size = _original_camera_size
