class_name Coin
extends Node3D

@export var fall_time: float = 0.5
@export var bounce_height: float = 0.2

# enum State { INITIAL_DROP, BOUNCING }
# var current_state: State = State.INITIAL_DROP

# The board that spawned this coin — set by the board before calling start()
var board: PlinkoBoard
var coin_type: Enums.CurrencyType = Enums.CurrencyType.GOLD_COIN:
	set(value):
		coin_type = value
		_apply_color()
var multiplier: int = 1

const COIN_COLORS := {
	Enums.CurrencyType.GOLD_COIN: Color(1, 0.941176, 0),
	Enums.CurrencyType.RAW_ORANGE: Color(1, 0.5, 0),
	Enums.CurrencyType.ORANGE_COIN: Color(1, 0.5, 0),
	Enums.CurrencyType.RAW_RED: Color(1, 0.15, 0.15),
	Enums.CurrencyType.RED_COIN: Color(1, 0.15, 0.15),
}

func _ready() -> void:
	_apply_color()


func _apply_color() -> void:
	var mesh_instance := get_node_or_null("MeshInstance3D")
	if not mesh_instance:
		return
	var color: Color = COIN_COLORS.get(coin_type, COIN_COLORS[Enums.CurrencyType.GOLD_COIN])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_instance.material_override = mat


func start(target: Vector3) -> void:
	# create_tween() makes a new Tween object attached to this node.
	var tween: Tween = create_tween()
	# tween_property(object, property_path, final_value, duration)
	tween.tween_property(self, "position", target, fall_time) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_bounce_or_despawn)

func _bounce_or_despawn() -> void:
	if position.y < board.buckets_container.position.y + 0.5:
		board.on_coin_landed(self)
	else:
		var x_tween: Tween = create_tween()
		var direction = 1 if randf() < 0.5 else -1
		x_tween.tween_property(self, "position:x", position.x + direction * board.space_between_pegs / 2, fall_time) \
			.set_ease(Tween.EASE_IN_OUT) \
			.set_trans(Tween.TRANS_LINEAR)
		
		var y_tween: Tween = create_tween()
		y_tween.tween_property(self, "position:y", position.y + bounce_height, fall_time / 3) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		y_tween.tween_property(self, "position:y", position.y - board.vertical_spacing, fall_time * 2 / 3) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		y_tween.tween_callback(_bounce_or_despawn)
