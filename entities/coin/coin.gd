class_name Coin
extends Node3D

var board: PlinkoBoard
var coin_type: Enums.CurrencyType = Enums.CurrencyType.GOLD_COIN:
	set(value):
		coin_type = value
		if is_node_ready():
			_apply_visuals()
var multiplier: float = 1.0

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
	tween.tween_property(self, "position", target, t.coin_fall_time) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_bounce_or_despawn)

func _bounce_or_despawn() -> void:
	if position.y < board.buckets_container.position.y + 0.5:
		board.on_coin_landed(self)
	else:
		var t: VisualTheme = ThemeProvider.theme
		var x_tween: Tween = create_tween()
		var direction = 1 if randf() < 0.5 else -1
		x_tween.tween_property(self, "position:x", position.x + direction * board.space_between_pegs / 2, t.coin_fall_time) \
			.set_ease(Tween.EASE_IN_OUT) \
			.set_trans(Tween.TRANS_LINEAR)

		var y_tween: Tween = create_tween()
		y_tween.tween_property(self, "position:y", position.y + t.coin_bounce_height, t.coin_fall_time / 3) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		y_tween.tween_property(self, "position:y", position.y - board.vertical_spacing, t.coin_fall_time * 2 / 3) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		y_tween.tween_callback(_bounce_or_despawn)
