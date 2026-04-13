class_name ChallengeClock extends Control

## White pie-slice circle that visualizes challenge time remaining. Updates
## discretely on ChallengeManager.tick (once per second), never continuously —
## the discrete shape change reinforces the per-second pulse both visually and
## in concert with the arcade audio's kick drum on the same tick.

@export var radius: float = 32.0
@export var clock_color: Color = Color.WHITE

var _fraction_remaining: float = 0.0  # 1.0 = full circle, 0.0 = empty


func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	visible = false
	ChallengeManager.tick.connect(_on_tick)
	ChallengeManager.challenge_completed.connect(_on_end)
	ChallengeManager.challenge_failed.connect(_on_end)


## Called by the HUD when a challenge begins.
func start() -> void:
	_fraction_remaining = 1.0
	visible = true
	queue_redraw()


func _on_tick(seconds_remaining: int) -> void:
	var total: int = ChallengeManager.get_total_seconds()
	_fraction_remaining = float(seconds_remaining) / float(maxi(1, total))
	queue_redraw()


func _on_end(_reason := "") -> void:
	visible = false


func _draw() -> void:
	if _fraction_remaining <= 0.0:
		return
	# Filled pie slice, top (12 o'clock) sweeping clockwise over
	# (fraction * 360°). The "mouth" opens on the right and grows downward
	# as time elapses — matches the pac-man-at-45s spec.
	var center := Vector2(radius, radius)
	var segments := 64
	var sweep := TAU * _fraction_remaining
	var points := PackedVector2Array([center])
	for i in segments + 1:
		var angle := -PI / 2.0 + sweep * (float(i) / segments)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, clock_color)
