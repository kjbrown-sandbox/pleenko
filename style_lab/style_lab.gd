@tool
extends Node3D

## Style Lab — a standalone scene for iterating on visuals.
##
## Static elements (pegs, buckets) update live in the editor via @tool.
## Press F6 to run this scene and see coins dropping with VFX.

@export var theme: VisualTheme:
	set(value):
		theme = value
		if is_node_ready():
			rebuild()

@export_group("Demo Controls")
@export var coin_drop_interval := 0.8          ## seconds between auto-dropped coins
@export var show_all_tiers := true             ## show gold, orange, red side by side
@export var rebuild_trigger := false:          ## toggle in Inspector to force rebuild
	set(_v):
		rebuild_trigger = false
		if is_node_ready():
			rebuild()

# ── Internals ────────────────────────────────────────────────────────
var _board_container: Node3D
var _coin_container: Node3D
var _drop_timer := 0.0
var _coin_index := 0
var _halo_shader: Shader

# Currency type ints (mirrors Enums.CurrencyType values)
const GOLD_COIN := 0
const ORANGE_COIN := 2
const RED_COIN := 4
const RAW_ORANGE := 1
const RAW_RED := 3
const COIN_TYPES := [0, 2, 4]  # GOLD_COIN, ORANGE_COIN, RED_COIN

# ── Lifecycle ────────────────────────────────────────────────────────

func _ready() -> void:
	_board_container = Node3D.new()
	_board_container.name = "Boards"
	add_child(_board_container)

	_coin_container = Node3D.new()
	_coin_container.name = "Coins"
	add_child(_coin_container)

	_halo_shader = Shader.new()
	_halo_shader.code = "
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 0.1);
uniform float opacity_mult = 1.0;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
	float dist = length(UV - vec2(0.5)) * 2.0;
	float falloff = exp(-dist * dist * 3.0);
	float noise = (hash(FRAGCOORD.xy) - 0.5) / 255.0;
	ALBEDO = glow_color.rgb;
	ALPHA = max(falloff * glow_color.a * opacity_mult + noise, 0.0);
}
"

	if not theme:
		theme = VisualTheme.new()

	rebuild()


func _process(delta: float) -> void:
	# Only spawn coins at runtime (F6), not in-editor
	if Engine.is_editor_hint():
		return
	if not theme:
		return

	_drop_timer -= delta
	if _drop_timer <= 0:
		_drop_timer = coin_drop_interval
		_spawn_demo_coin()


# ── Build ────────────────────────────────────────────────────────────

func rebuild() -> void:
	if not theme:
		return

	_setup_environment()
	_clear_children(_board_container)
	_clear_children(_coin_container)

	if show_all_tiers:
		var spacing := theme.space_between_pegs * (theme.board_rows + 2)
		_build_board_slice(Vector3(-spacing, 0, 0), GOLD_COIN)
		_build_board_slice(Vector3.ZERO, ORANGE_COIN)
		_build_board_slice(Vector3(spacing, 0, 0), RED_COIN)
	else:
		_build_board_slice(Vector3.ZERO, GOLD_COIN)


func _setup_environment() -> void:
	# Background via WorldEnvironment
	var env_node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if not env_node:
		env_node = WorldEnvironment.new()
		env_node.name = "WorldEnvironment"
		add_child(env_node)
		if Engine.is_editor_hint():
			env_node.owner = self

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = theme.background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = theme.ambient_light_color
	env.ambient_light_energy = theme.ambient_light_energy
	env_node.environment = env

	# Directional light (skip if unshaded — not needed)
	var light := get_node_or_null("DemoLight") as DirectionalLight3D
	if theme.unshaded:
		if light:
			light.queue_free()
	else:
		if not light:
			light = DirectionalLight3D.new()
			light.name = "DemoLight"
			add_child(light)
			if Engine.is_editor_hint():
				light.owner = self
		light.light_color = theme.directional_light_color
		light.light_energy = theme.directional_light_energy
		light.rotation_degrees = theme.directional_light_angle

	# Camera (only at runtime — editor uses its own camera)
	if not Engine.is_editor_hint():
		var cam := get_node_or_null("DemoCamera") as Camera3D
		if not cam:
			cam = Camera3D.new()
			cam.name = "DemoCamera"
			add_child(cam)
		# Frame the boards — zoom to fit content with minimal padding
		var vertical_spacing := theme.space_between_pegs * sqrt(3) / 2
		var board_height := vertical_spacing * theme.board_rows
		var y_center := -board_height / 2.0
		var board_total_width: float
		if show_all_tiers:
			board_total_width = theme.space_between_pegs * (theme.board_rows + 2) * 2 + theme.board_rows * theme.space_between_pegs
		else:
			board_total_width = theme.board_rows * theme.space_between_pegs
		# Use wider of height/width to determine z distance
		var z_dist := maxf(board_height, board_total_width) * 0.85
		cam.position = Vector3(0, y_center, z_dist)
		cam.look_at(Vector3(0, y_center, 0))


func _build_board_slice(offset: Vector3, currency_type: int) -> void:
	var board_root := Node3D.new()
	board_root.position = offset
	_board_container.add_child(board_root)
	if Engine.is_editor_hint():
		board_root.owner = get_tree().edited_scene_root

	var vertical_spacing := theme.space_between_pegs * sqrt(3) / 2
	var peg_mesh := theme.make_peg_mesh()
	var peg_list: Array[MeshInstance3D] = []

	# ── Pegs ──
	for row in range(theme.board_rows):
		var x_start := -row * theme.space_between_pegs / 2.0
		var y := -vertical_spacing * row
		for col in range(row + 1):
			var peg := MeshInstance3D.new()
			peg.mesh = peg_mesh
			# Each peg gets its own material for independent glow
			var peg_mat := theme.make_peg_material()
			peg.material_override = peg_mat
			peg.set_meta("own_mat", peg_mat)
			peg.position = Vector3(
				x_start + col * theme.space_between_pegs, y, 0
			)
			# Rotate cylinder pegs to face camera
			if theme.peg_shape == VisualTheme.PegShape.CYLINDER:
				peg.rotation = Vector3(PI / 2, 0, 0)
			board_root.add_child(peg)
			peg_list.append(peg)
			if Engine.is_editor_hint():
				peg.owner = get_tree().edited_scene_root
	board_root.set_meta("pegs", peg_list)

	# ── Buckets ──
	var num_buckets := theme.board_rows + 1
	var bucket_x_offset := -theme.space_between_pegs * (num_buckets - 1) / 2.0
	var bucket_y := -vertical_spacing * theme.board_rows + (vertical_spacing / 3)
	var bucket_mesh := theme.make_bucket_mesh()

	for i in range(num_buckets):
		var bucket := MeshInstance3D.new()
		bucket.mesh = bucket_mesh

		# Edge buckets use a different color (simulating advanced buckets)
		var bucket_currency := currency_type
		@warning_ignore("integer_division")
		var dist_from_center: int = abs(i - num_buckets / 2)
		if dist_from_center >= 3 and currency_type != RED_COIN:
			# Show "advanced" color on edges
			match currency_type:
				GOLD_COIN:
					bucket_currency = RAW_ORANGE
				ORANGE_COIN:
					bucket_currency = RAW_RED

		bucket.material_override = theme.make_bucket_material(bucket_currency)
		bucket.position = Vector3(
			bucket_x_offset + i * theme.space_between_pegs, bucket_y, 0
		)
		board_root.add_child(bucket)
		if Engine.is_editor_hint():
			bucket.owner = get_tree().edited_scene_root

		# Bucket value label
		var label := Label3D.new()
		label.text = str(1 + dist_from_center)
		label.font_size = theme.bucket_label_font_size
		label.outline_size = theme.label_outline_size
		if theme.label_font:
			label.font = theme.label_font
		label.position = Vector3(0, theme.bucket_label_offset, 0.05)
		label.modulate = theme.get_bucket_color(bucket_currency)
		bucket.add_child(label)
		if Engine.is_editor_hint():
			label.owner = get_tree().edited_scene_root

	# ── Board glow (soft radial gradient behind the board center) ──
	if theme.board_glow_enabled and theme.board_glow_opacity > 0:
		var glow_y := -vertical_spacing * theme.board_rows / 2.0
		var glow := MeshInstance3D.new()
		var glow_mesh := QuadMesh.new()
		glow_mesh.size = Vector2(theme.board_glow_radius * 2, theme.board_glow_radius * 2)
		glow.mesh = glow_mesh

		var glow_shader := ShaderMaterial.new()
		glow_shader.shader = _halo_shader
		var glow_color := theme.get_coin_color(currency_type)
		glow_color.a = theme.board_glow_opacity
		glow_shader.set_shader_parameter("glow_color", glow_color)
		glow.material_override = glow_shader
		glow.position = Vector3(0, glow_y, -0.1)
		board_root.add_child(glow)
		if Engine.is_editor_hint():
			glow.owner = get_tree().edited_scene_root

	# ── Static coin display (one coin sitting at top, visible in editor) ──
	var display_coin := MeshInstance3D.new()
	display_coin.mesh = theme.make_coin_mesh()
	display_coin.material_override = theme.make_coin_material(currency_type)
	display_coin.position = Vector3(0, vertical_spacing * 0.5, 0)
	if theme.coin_shape == VisualTheme.CoinShape.CYLINDER:
		display_coin.rotation = Vector3(PI / 2, 0, 0)
	board_root.add_child(display_coin)
	if Engine.is_editor_hint():
		display_coin.owner = get_tree().edited_scene_root


# ── Runtime coin spawning (F6 only) ────────────────────────────────

func _spawn_demo_coin() -> void:
	if not theme:
		return

	# Pick which board to drop on
	var currency: int = COIN_TYPES[_coin_index % COIN_TYPES.size()]
	if not show_all_tiers:
		currency = GOLD_COIN
	_coin_index += 1

	var vertical_spacing := theme.space_between_pegs * sqrt(3) / 2

	# Determine board offset
	var board_offset := Vector3.ZERO
	if show_all_tiers:
		var spacing := theme.space_between_pegs * (theme.board_rows + 2)
		match currency:
			GOLD_COIN:
				board_offset = Vector3(-spacing, 0, 0)
			ORANGE_COIN:
				board_offset = Vector3.ZERO
			RED_COIN:
				board_offset = Vector3(spacing, 0, 0)

	var drop_pos := board_offset + Vector3(0, vertical_spacing * 0.5, 0)

	var coin := MeshInstance3D.new()
	coin.mesh = theme.make_coin_mesh()
	coin.material_override = theme.make_coin_material(currency)
	coin.position = drop_pos + Vector3(0, 0.5, 0)
	if theme.coin_shape == VisualTheme.CoinShape.CYLINDER:
		coin.rotation = Vector3(PI / 2, 0, 0)
	_coin_container.add_child(coin)

	# Scale-in VFX
	if theme.coin_spawn_scale_from < 1.0:
		coin.scale = Vector3.ONE * theme.coin_spawn_scale_from
		var scale_tween := create_tween()
		scale_tween.tween_property(coin, "scale", Vector3.ONE, theme.coin_spawn_scale_duration) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Initial drop to first row, then start bouncing
	var drop_tween := create_tween()
	drop_tween.tween_property(coin, "position", drop_pos, 0.3) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	drop_tween.tween_callback(func():
		if is_instance_valid(coin):
			_animate_coin_drop(coin, board_offset, currency, vertical_spacing)
	)


func _animate_coin_drop(coin: MeshInstance3D, board_offset: Vector3,
		currency: int, vertical_spacing: float, row: int = 0) -> void:
	var fall_time := theme.coin_fall_time
	var bounce_height := theme.coin_bounce_height

	# ── Peg glow VFX ──
	_flash_nearest_peg(coin.position, board_offset, currency)

	var direction := 1.0 if randf() < 0.5 else -1.0
	var next_x := coin.position.x + direction * theme.space_between_pegs / 2
	var next_y := coin.position.y - vertical_spacing

	# Check if this bounce would land the coin at or past bucket level
	var bucket_y := board_offset.y - vertical_spacing * theme.board_rows + (vertical_spacing / 3)
	var is_landing := next_y < bucket_y + 0.5 or row + 1 >= theme.board_rows

	# Horizontal movement
	var x_tween := create_tween()
	x_tween.tween_property(coin, "position:x", next_x, fall_time) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_LINEAR)

	# Vertical arc: up then down
	var y_tween := create_tween()
	y_tween.tween_property(coin, "position:y", coin.position.y + bounce_height, fall_time / 3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	y_tween.tween_property(coin, "position:y", next_y, fall_time * 2 / 3) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	y_tween.tween_callback(func():
		if not is_instance_valid(coin):
			return
		if is_landing:
			_on_demo_coin_landed(coin, board_offset, currency, vertical_spacing)
		else:
			_animate_coin_drop(coin, board_offset, currency, vertical_spacing, row + 1)
	)


func _on_demo_coin_landed(coin: MeshInstance3D, board_offset: Vector3,
		currency: int, _vertical_spacing: float) -> void:
	if not is_instance_valid(coin):
		return

	# ── Bucket pulse VFX ──
	_pulse_nearest_bucket(coin.position, board_offset)

	# ── Floating text ──
	var multiplier := randi_range(1, 5)
	if multiplier > 1:
		_show_demo_floating_text(coin.position, multiplier, multiplier * 3, currency)

	# ── Particle scatter — coin disappears into small fragments ──
	var land_pos := coin.position
	coin.queue_free()
	_spawn_scatter_particles(land_pos, currency)


# ── VFX helpers ──────────────────────────────────────────────────────

func _flash_nearest_peg(coin_pos: Vector3, board_offset: Vector3, currency: int) -> void:
	if not _board_container:
		return

	# Find the right board_root
	var target_board: Node3D = null
	for board_root in _board_container.get_children():
		if board_root.position.distance_to(board_offset) < 0.01:
			target_board = board_root
			break
	if not target_board:
		return

	# Use cached peg list (stored as metadata during build)
	var pegs: Array = target_board.get_meta("pegs", [])
	var closest_peg: MeshInstance3D = null
	var closest_dist := INF

	for peg: MeshInstance3D in pegs:
		if not is_instance_valid(peg):
			continue
		var dist := coin_pos.distance_to(peg.global_position)
		if dist < closest_dist and dist < theme.space_between_pegs * 0.8:
			closest_dist = dist
			closest_peg = peg

	if not closest_peg:
		return

	# Each peg gets its own material so glows don't interfere
	# Create one if it doesn't have its own yet
	var peg_mat: StandardMaterial3D = closest_peg.get_meta("own_mat", null)
	if not peg_mat:
		peg_mat = theme.make_peg_material()
		closest_peg.set_meta("own_mat", peg_mat)
		closest_peg.material_override = peg_mat

	# Set to coin color immediately, then tween back
	var glow_color := theme.get_coin_color(currency)
	peg_mat.albedo_color = glow_color

	# Kill any existing glow tween on this peg
	var old_tween: Tween = closest_peg.get_meta("glow_tween", null)
	if old_tween and old_tween.is_valid():
		old_tween.kill()

	var glow_tween := create_tween()
	glow_tween.tween_property(peg_mat, "albedo_color", theme.peg_color, theme.peg_glow_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	closest_peg.set_meta("glow_tween", glow_tween)

	# ── Peg halo — soft radial glow that fades with the peg ──
	if theme.peg_glow_halo_enabled and _halo_shader:
		var halo := MeshInstance3D.new()
		var halo_mesh := QuadMesh.new()
		halo_mesh.size = Vector2(theme.peg_glow_halo_radius, theme.peg_glow_halo_radius)
		halo.mesh = halo_mesh

		var halo_mat := ShaderMaterial.new()
		halo_mat.shader = _halo_shader
		var halo_color := glow_color
		halo_color.a = theme.peg_glow_halo_opacity
		halo_mat.set_shader_parameter("glow_color", halo_color)
		halo_mat.set_shader_parameter("opacity_mult", 1.0)
		halo.material_override = halo_mat
		halo.position = Vector3(closest_peg.global_position.x, closest_peg.global_position.y, closest_peg.global_position.z - 0.05)
		_coin_container.add_child(halo)

		var halo_tween := create_tween()
		halo_tween.tween_property(halo_mat, "shader_parameter/opacity_mult", 0.0, theme.peg_glow_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		halo_tween.tween_callback(halo.queue_free)


func _pulse_nearest_bucket(coin_pos: Vector3, board_offset: Vector3) -> void:
	if not _board_container:
		return

	var closest_bucket: MeshInstance3D = null
	var closest_dist := INF

	for board_root in _board_container.get_children():
		if board_root.position != board_offset:
			continue
		for child in board_root.get_children():
			if child is MeshInstance3D and child.mesh is BoxMesh:
				var dist: float = absf(coin_pos.x - child.global_position.x)
				if dist < closest_dist:
					closest_dist = dist
					closest_bucket = child

	if not closest_bucket:
		return

	var pulse := create_tween()
	var target_scale := Vector3.ONE * theme.bucket_pulse_scale
	pulse.tween_property(closest_bucket, "scale", target_scale, theme.bucket_pulse_duration * 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	pulse.tween_property(closest_bucket, "scale", Vector3.ONE, theme.bucket_pulse_duration * 0.6) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)


func _show_demo_floating_text(pos: Vector3, multiplier: int, total: int, currency: int) -> void:
	var label := Label3D.new()
	label.text = "x%d = %d" % [multiplier, total]
	label.font_size = 40
	label.outline_size = theme.label_outline_size
	if theme.label_font:
		label.font = theme.label_font
	label.position = Vector3(pos.x, pos.y + 0.3, pos.z + 0.05)
	label.modulate = theme.get_coin_color(currency)
	_coin_container.add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y + theme.floating_text_rise, theme.floating_text_duration)
	tween.parallel().tween_property(label, "modulate:a", 0.0, theme.floating_text_duration * 0.5) \
		.set_delay(theme.floating_text_duration * 0.5)
	tween.tween_callback(label.queue_free)


func _spawn_scatter_particles(pos: Vector3, currency: int) -> void:
	var color := theme.get_coin_color(currency)
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = theme.coin_radius * 0.25
	particle_mesh.height = theme.coin_radius * 0.5

	for i in range(theme.coin_land_particle_count):
		var particle := MeshInstance3D.new()
		particle.mesh = particle_mesh
		# Each particle needs its own material for independent alpha fade
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		if theme.unshaded:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		particle.material_override = mat
		particle.position = pos
		_coin_container.add_child(particle)

		# Spread 150 degrees centered downward (-90deg = down, so range is -165 to -15 in deg)
		var angle := randf_range(deg_to_rad(-165), deg_to_rad(-15))
		var speed := theme.coin_land_particle_speed * randf_range(0.5, 1.0)
		var target_pos := pos + Vector3(cos(angle) * speed * 0.3, sin(angle) * speed * 0.3, 0)
		var dur := theme.coin_land_particle_duration

		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(particle, "position", target_pos, dur) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_property(particle, "scale", Vector3.ZERO, dur) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.chain().tween_callback(particle.queue_free)


# ── Utilities ────────────────────────────────────────────────────────

func _clear_children(node: Node) -> void:
	if not node:
		return
	for child in node.get_children():
		child.queue_free()
