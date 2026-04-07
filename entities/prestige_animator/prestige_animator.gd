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
var _vfx: PrestigeVFX
var _is_animating: bool = false
var _target_coin: Coin
var _target_bucket: Bucket
var _original_camera_pos: Vector3
var _original_camera_size: float
var _phase_elapsed: float = 0.0
var _coin_has_landed: bool = false
var _coin_start_y: float
var _contact_y: float  ## Y position where coin bottom touches bucket top
var _original_coin_color: Color
var _original_bucket_color: Color
var _original_bucket_label_color: Color


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func setup(camera: Camera3D) -> void:
	_camera = camera


func connect_board(board: PlinkoBoard) -> void:
	if not board.prestige_coin_landed.is_connected(_on_prestige_coin_final_bounce):
		board.prestige_coin_landed.connect(_on_prestige_coin_final_bounce)


func _on_prestige_coin_final_bounce(coin: Coin, predicted_bucket: Bucket) -> void:
	if _is_animating:
		return

	_is_animating = true
	_target_coin = coin
	_target_bucket = predicted_bucket
	_phase_elapsed = 0.0
	_coin_has_landed = false

	# Mark the coin so PlinkoBoard won't free it or add currency on landing
	coin.is_prestige_coin = true
	# Eject from MultiMesh so we can individually scale/color the coin
	coin.board.eject_coin_from_multimesh(coin)

	# Listen for when the coin actually lands (touches the bucket)
	coin.landed.connect(_on_prestige_coin_actually_landed, CONNECT_ONE_SHOT)

	# Store camera state for restore on abort
	_original_camera_pos = _camera.global_position
	_original_camera_size = _camera.size
	_coin_start_y = coin.global_position.y
	# Contact Y: coin center sits at the top of the bucket
	var t: VisualTheme = ThemeProvider.theme
	# Contact Y: coin bottom edge meets bucket top edge
	_contact_y = predicted_bucket.global_position.y + t.bucket_height / 2.0 + t.coin_radius
	_original_coin_color = coin.get_color()
	_original_bucket_color = predicted_bucket._base_material.albedo_color
	_original_bucket_label_color = predicted_bucket._label.modulate

	# Determine which board type is being prestiged
	for i in range(1, TierRegistry.get_tier_count()):
		var tier := TierRegistry.get_tier_by_index(i)
		if tier.raw_currency == predicted_bucket.currency_type:
			PrestigeManager.pending_board_type = tier.board_type
			break

	# Spawn VFX handler
	_vfx = PrestigeVFX.new()
	add_child(_vfx)
	_vfx.setup(_camera, coin.board, predicted_bucket, coin)

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

	# Use contact Y (coin bottom touches bucket top) instead of bucket center
	var y_progress := (_coin_start_y - coin_world_pos.y) / maxf(_coin_start_y - _contact_y, 0.01)
	var y_eased := clampf(y_progress, 0.0, 1.0)
	Engine.time_scale = lerpf(t.prestige_slow_mo_scale, t.prestige_freeze_scale, y_eased)

	var palette_white: Color = t.resolve(VisualTheme.Palette.BG_6)

	_target_coin.set_color(_original_coin_color.lerp(palette_white, y_eased))

	# Desaturate pegs and non-target buckets toward background color
	_vfx.update_desaturation(y_eased)

	# Lerp bucket mesh and label toward palette white alongside the coin
	_target_bucket._base_material.albedo_color = _original_bucket_color.lerp(palette_white, y_eased)
	_target_bucket._label.modulate = _original_bucket_label_color.lerp(palette_white, y_eased)

	# Coin bottom reached bucket top — freeze it and trigger contact VFX
	if coin_world_pos.y <= _contact_y:
		_target_coin.kill_tweens()
		_target_coin.global_position.y = _contact_y
		_target_coin.set_color(palette_white)
		_target_bucket._base_material.albedo_color = palette_white
		_target_bucket._label.modulate = palette_white
		_vfx.play_contact(_target_coin.global_position)
		_phase_elapsed = 0.0
		PrestigeManager.enter_phase(PrestigeManager.PrestigePhase.FREEZE)


func _process_freeze(t: VisualTheme) -> void:
	# World is near-frozen. After a beat, start the coin expand.
	if _phase_elapsed >= t.prestige_freeze_duration:
		_phase_elapsed = 0.0
		_start_coin_expand()
		PrestigeManager.enter_phase(PrestigeManager.PrestigePhase.EXPAND)


func _process_expand(_real_delta: float, t: VisualTheme) -> void:
	if not is_instance_valid(_target_coin):
		_transition_to_prestige_screen()
		return

	# Scale the coin up over time to fill the screen
	var progress: float = clampf(_phase_elapsed / t.prestige_expand_duration, 0.0, 1.0)
	# Cubic ease-in: very slow at start, accelerates dramatically toward the end
	var eased: float = progress * progress * progress * progress

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

	# Ensure coin is palette-white for expand phase
	_target_coin.set_color(t.resolve(VisualTheme.Palette.BG_6))


func _transition_to_prestige_screen() -> void:
	_is_animating = false
	set_process(false)

	# Clean up VFX
	if _vfx:
		_vfx.cleanup()
		_vfx.queue_free()
		_vfx = null

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
	if _vfx:
		_vfx.cleanup()
		_vfx.queue_free()
		_vfx = null
	_camera.global_position = _original_camera_pos
	_camera.size = _original_camera_size
