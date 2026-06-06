class_name Coin
extends Node3D

signal landed(coin: Coin)
## Emitted on the final bounce, after the direction is chosen and the landing bucket is known.
## The coin is still mid-air, bouncing toward the bucket.
signal final_bounce_started(coin: Coin, predicted_bucket: Bucket)

enum FillState { FULL, FILLING }

var board: PlinkoBoard
var coin_type: Enums.CurrencyType = Enums.CurrencyType.GOLD_COIN:
	set(value):
		coin_type = value
		if is_node_ready():
			_apply_visuals()
var multiplier: float = 1.0
var is_advanced: bool = false
var fill_state: FillState = FillState.FULL
var fill_progress: float = 1.0
## When true, the coin won't be freed on landing — the PrestigeAnimator handles its lifecycle.
var is_prestige_coin: bool = false
## Optional per-coin color override (frenzy coins tint to the upgrade-button
## color so they read as "from the milestone"). Purely visual; set before the
## coin enters the tree so _apply_visuals picks it up. alpha 0 = unset (any
## override sets alpha > 0).
var color_override: Color = Color(0, 0, 0, 0)
var _active_tweens: Array[Tween] = []
## Seconds remaining on the impact-squash recovery animation. 0 = no squash.
## Read by PlinkoBoard._sync_coin_multimesh to derive the per-coin scale.
var impact_squash_remaining: float = 0.0

## Cached at start() and reused per bounce so we don't hit ChallengeProgressManager
## on every row of every coin (hot path — tens of thousands of coins).
var _fall_speed_multiplier: float = 1.0

## Integer lattice position on the triangular board. Advanced deterministically
## each bounce so the deflector lookup is exact and noise-free (no float→peg
## inversion). Starts at (0, 0): row 0 has exactly one peg.
var _row: int = 0
var _col: int = 0

## True once the coin enters a voided column (bomb fallout): it falls straight
## down past the bucket plane and despawns off-screen. No bucket land, no
## currency credit, no landing burst. Set by _begin_void_fall.
var _in_void_fall: bool = false

## Each granted GOLD_COIN_SPEED_BOOST challenge reward adds this fraction to
## gold coins' fall-speed multiplier. 0.2 → first grant = 1.2x speed, third = 1.6x (additive).
## Only gold coins are sped up; other coin types fall at baseline speed.
## The reward's displayed text is derived live from this constant by
## ChallengeRewardData.display_text() (GOLD_COIN_SPEED_BOOST case), so changing
## the value updates every reward display automatically — no .tres edits needed.
const COIN_SPEED_BOOST_PER_UNLOCK := 0.2

## MultiMesh rendering state
var multimesh_index: int = -1
var cached_color: Color = Color.WHITE

func _ready() -> void:
	_apply_visuals()


func _apply_visuals() -> void:
	var mesh_instance := get_node_or_null("MeshInstance3D")
	if not mesh_instance:
		return
	var t: VisualTheme = ThemeProvider.theme
	var has_override: bool = color_override.a > 0.0
	var coin_col: Color = color_override if has_override else t.get_coin_color(coin_type)
	mesh_instance.mesh = t.make_coin_mesh()
	if fill_state == FillState.FILLING:
		var fill_shader: Shader = preload("res://entities/coin/coin_fill.gdshader")
		var mat := ShaderMaterial.new()
		mat.shader = fill_shader
		mat.set_shader_parameter("albedo_color", coin_col)
		mat.set_shader_parameter("fill_progress", fill_progress)
		mesh_instance.material_override = mat
	else:
		mesh_instance.material_override = t.make_coin_material(coin_type)
	# Override wins over silhouette so frenzy coins read in their own color (the
	# multimesh renders the visible coin from cached_color).
	if has_override:
		cached_color = coin_col
	else:
		cached_color = t.coin_silhouette_color if t.coin_silhouette else t.get_coin_color(coin_type)
	if t.coin_shape == VisualTheme.CoinShape.CYLINDER:
		mesh_instance.rotation = Vector3(PI / 2, 0, 0)
	else:
		mesh_instance.rotation = Vector3.ZERO
	_apply_halo(t)


func _apply_halo(t: VisualTheme) -> void:
	# Remove existing halo if re-applying
	var old_halo := get_node_or_null("CoinHalo")
	if old_halo:
		old_halo.queue_free()
	if not t.coin_halo_enabled:
		return
	var halo_shader: Shader = preload("res://entities/coin/coin_halo.gdshader")
	var quad := MeshInstance3D.new()
	quad.name = "CoinHalo"
	var mesh := QuadMesh.new()
	var halo_size: float = t.coin_radius * t.coin_halo_radius * 2.0
	mesh.size = Vector2(halo_size, halo_size)
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = halo_shader
	var halo_col: Color = color_override if color_override.a > 0.0 else t.get_coin_color(coin_type)
	mat.set_shader_parameter("glow_color", halo_col)
	mat.set_shader_parameter("opacity_mult", t.coin_halo_opacity)
	quad.material_override = mat
	quad.position = Vector3(0, 0, -0.02)
	add_child(quad)


func start(target: Vector3) -> void:
	_row = 0
	_col = 0
	var t: VisualTheme = ThemeProvider.theme
	if coin_type == Enums.CurrencyType.GOLD_COIN:
		_fall_speed_multiplier = 1.0 + ChallengeProgressManager.get_gold_coin_speed_boost_count() * COIN_SPEED_BOOST_PER_UNLOCK
	var tween: Tween = create_tween()
	_active_tweens.append(tween)
	tween.tween_property(self, "position", target, t.coin_fall_time / _fall_speed_multiplier) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_bounce_or_despawn)


func kill_tweens() -> void:
	for tween in _active_tweens:
		if tween and tween.is_valid():
			tween.kill()
	_active_tweens.clear()


func get_color() -> Color:
	return cached_color


func set_color(color: Color) -> void:
	cached_color = color
	var mesh_instance := get_node_or_null("MeshInstance3D")
	if mesh_instance and mesh_instance.material_override is ShaderMaterial:
		mesh_instance.material_override.set_shader_parameter("albedo_color", color)


func set_fill(progress: float) -> void:
	fill_progress = progress
	var mesh_instance := get_node_or_null("MeshInstance3D")
	if mesh_instance and mesh_instance.material_override is ShaderMaterial:
		mesh_instance.material_override.set_shader_parameter("fill_progress", progress)


func complete_fill() -> void:
	fill_state = FillState.FULL
	fill_progress = 1.0
	_apply_visuals()


func set_mesh_visible(vis: bool) -> void:
	var mesh_instance := get_node_or_null("MeshInstance3D")
	if mesh_instance:
		mesh_instance.visible = vis


func _bounce_or_despawn() -> void:
	if _in_void_fall:
		# Tween chain already drives the off-screen fall + queue_free.
		return
	if board.is_terminal_cell(_row, _col):
		landed.emit(self)
		return

	board.flash_nearest_peg(global_position, coin_type)
	var t: VisualTheme = ThemeProvider.theme
	# Trigger the impact squash on peg contact.
	if t.coin_impact_squash_enabled:
		impact_squash_remaining = t.coin_impact_squash_duration

	# Deflector (if placed at this peg) forces the direction; else 50/50.
	var direction: int = board.resolve_bounce_direction(_row, _col, randf())
	# Drive the deflector reaction VFX while _row/_col still point at the peg we
	# just bounced off (they're reassigned below). Pure view, no gameplay effect.
	board.notify_deflector_resolved(_row, _col, direction)
	var next_cell: Vector2i = board.next_lattice_cell(_row, _col, direction)

	# Voided column: the destination peg has been destroyed by a bomb
	# detonation — drift in the chosen direction then fall off-screen. We
	# pass `direction` so the coin keeps the momentum from the peg it just
	# bounced off (rather than dropping straight down, which reads as a hard
	# cut). See _begin_void_fall.
	if board.is_lattice_cell_voided(next_cell.x, next_cell.y):
		_begin_void_fall(direction)
		return

	var target: Vector3 = board.cell_to_world(next_cell.x, next_cell.y)
	var next_x: float = target.x
	var next_y: float = target.y

	# Check if this is the final bounce (next cell is the bucket row)
	if board.is_terminal_cell(next_cell.x, next_cell.y):
		var predicted_bucket: Bucket = board.get_bucket(
			board.predicted_bucket_index(next_cell.x, next_cell.y))
		if predicted_bucket:
			final_bounce_started.emit(self, predicted_bucket)

	_row = next_cell.x
	_col = next_cell.y

	# Add randomness so bounces don't look uniform
	var bounce_height: float = t.coin_bounce_height * randf_range(0.3, 1.7)
	var fall_time: float = t.coin_fall_time * randf_range(0.9, 1.1) / _fall_speed_multiplier

	var x_tween: Tween = create_tween()
	_active_tweens.append(x_tween)
	x_tween.tween_property(self, "position:x", next_x, fall_time) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_LINEAR)

	var y_tween: Tween = create_tween()
	_active_tweens.append(y_tween)
	y_tween.tween_property(self, "position:y", position.y + bounce_height, fall_time / 3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	y_tween.tween_property(self, "position:y", next_y, fall_time * 2 / 3) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	y_tween.tween_callback(_bounce_or_despawn)


## Switches the coin into "fall through a voided column" mode. The coin keeps
## the horizontal momentum it picked at the last peg (constant X drift in the
## bounce direction) while Y accelerates downward — feels like it tipped past
## the saw line rather than instantly cutting to a vertical drop. After it's
## clear of the board it queue_frees. No bucket land, no currency, no burst.
##
## Caller passes the bounce direction we picked at the source peg so the X
## drift matches the choice the coin "made" before reaching the void.
func _begin_void_fall(direction: int) -> void:
	_in_void_fall = true
	kill_tweens()
	var t: VisualTheme = ThemeProvider.theme
	# Far enough below the bucket plane that any camera framing has the coin
	# off-screen before queue_free.
	var target_y: float = board.cell_to_world(board.num_rows + 3, _col).y
	var fall_duration: float = t.coin_fall_time * 2.5 / _fall_speed_multiplier
	# Horizontal momentum: continue in `direction` at a constant slow drift
	# (about half a bucket width over the whole fall). Independent of the Y
	# easing so the trajectory reads as "kept moving, then gravity took over".
	var drift_x: float = board.space_between_pegs * 0.5 * float(direction)
	var target_x: float = position.x + drift_x
	var tween_y: Tween = create_tween()
	_active_tweens.append(tween_y)
	tween_y.tween_property(self, "position:y", target_y, fall_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	var tween_x: Tween = create_tween()
	_active_tweens.append(tween_x)
	tween_x.tween_property(self, "position:x", target_x, fall_duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_LINEAR)
	tween_y.tween_callback(queue_free)
