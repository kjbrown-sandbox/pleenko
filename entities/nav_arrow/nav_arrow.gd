class_name NavArrow
extends TintedIcon

## Rotation in radians applied to the icon. 0 = right, PI/2 = down, -PI/2 = up, PI = left.
@export var rotation_angle: float = 0.0


func _ready() -> void:
	super._ready()
	_apply_rotation.call_deferred()


func setup(_rotation_angle: float) -> void:
	rotation_angle = _rotation_angle
	_apply_rotation.call_deferred()


func _apply_rotation() -> void:
	if rotation_angle == 0.0:
		return
	pivot_offset = size / 2.0
	if absf(rotation_angle - PI) < 0.01 or absf(rotation_angle + PI) < 0.01:
		flip_h = true
	else:
		rotation = rotation_angle
