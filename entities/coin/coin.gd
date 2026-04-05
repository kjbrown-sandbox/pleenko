class_name Coin
extends Node3D

signal landed(coin: Coin)
## Emitted on the final bounce, after the direction is chosen and the landing bucket is known.
## The coin is still mid-air, bouncing toward the bucket.
signal final_bounce_started(coin: Coin, predicted_bucket: Bucket)

var board: PlinkoBoard
var coin_type: Enums.CurrencyType = Enums.CurrencyType.GOLD_COIN:
	set(value):
		coin_type = value
		if is_node_ready():
			_apply_visuals()
var multiplier: float = 1.0
## When true, the coin won't be freed on landing — the PrestigeAnimator handles its lifecycle.
var is_prestige_coin: bool = false
var _active_tweens: Array[Tween] = []

func _ready() -> void:
	_apply_visuals()


func _apply_visuals() -> void:
	var mesh_instance := get_node_or_null("MeshInstance3D")
	if not mesh_instance:
		return
	var t: VisualTheme = ThemeProvider.theme
	mesh_instance.mesh = t.make_coin_mesh()
	mesh_instance.material_override = t.make_coin_material(coin_type)
	if t.coin_shape == VisualTheme.CoinShape.CYLINDER:
		mesh_instance.rotation = Vector3(PI / 2, 0, 0)
	else:
		mesh_instance.rotation = Vector3.ZERO


func start(target: Vector3) -> void:
	var t: VisualTheme = ThemeProvider.theme
	var tween: Tween = create_tween()
	_active_tweens.append(tween)
	tween.tween_property(self, "position", target, t.coin_fall_time) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_bounce_or_despawn)


func kill_tweens() -> void:
	for tween in _active_tweens:
		if tween and tween.is_valid():
			tween.kill()
	_active_tweens.clear()


func get_color() -> Color:
	var mesh_instance := get_node_or_null("MeshInstance3D")
	if mesh_instance and mesh_instance.material_override is ShaderMaterial:
		return mesh_instance.material_override.get_shader_parameter("albedo_color")
	return ThemeProvider.theme.gold_normal


func set_color(color: Color) -> void:
	var mesh_instance := get_node_or_null("MeshInstance3D")
	if mesh_instance and mesh_instance.material_override is ShaderMaterial:
		mesh_instance.material_override.set_shader_parameter("albedo_color", color)


func set_clip_y(y: float) -> void:
	var mesh_instance := get_node_or_null("MeshInstance3D")
	if mesh_instance and mesh_instance.material_override is ShaderMaterial:
		mesh_instance.material_override.set_shader_parameter("clip_y", y)

func _bounce_or_despawn() -> void:
	if position.y < board.buckets_container.position.y + 0.5:
		landed.emit(self)
	else:
		var t: VisualTheme = ThemeProvider.theme
		var direction = 1 if randf() < 0.5 else -1
		var next_x: float = position.x + direction * board.space_between_pegs / 2.0
		var next_y: float = position.y - board.vertical_spacing

		# Check if this is the final bounce (next position will be below bucket row)
		if next_y < board.buckets_container.position.y + 0.5:
			var predicted_bucket: Bucket = board.get_nearest_bucket(
				board.global_position.x + next_x)
			if predicted_bucket:
				final_bounce_started.emit(self, predicted_bucket)

		# Add randomness so bounces don't look uniform
		var bounce_height: float = t.coin_bounce_height * randf_range(0.3, 1.7)
		var fall_time: float = t.coin_fall_time * randf_range(0.9, 1.1)

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
