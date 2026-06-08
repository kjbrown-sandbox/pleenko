class_name DropGate
extends Node3D

## Purely-visual pinball-style drop gate beneath the coin spawn, sized to match an
## inactive bucket (same width, same thinness). Two flaps split at the centre and
## hinge at the OUTER edges (double doors): closed they form a seamless flat bar;
## open they swing down to vertical. No collision — the drop is still governed
## entirely by the board's drop timer. PlinkoBoard calls open()/close() in sync
## with that timer (signals up, calls down; this node emits nothing).
##
## Cadence: closed during the cooldown, opens at drop-ready, closes as the coin
## passes through. With no coin queued at ready it holds open until one arrives.

enum State { CLOSED, OPENING, OPEN, CLOSING }

## Swing timings (seconds). Close is a touch slower so the gate reads as weighted.
const OPEN_SECONDS := 0.12
const CLOSE_SECONDS := 0.16

var _state: State = State.OPEN
## Normalised swing: 0 = closed (flat bar), 1 = open (flaps vertical).
var _angle: float = 1.0
## A close requested mid-open: deferred until the flaps reach vertical so the
## player always sees the full down-then-up swing for a drop.
var _close_requested: bool = false
var _left_pivot: Node3D
var _right_pivot: Node3D


func _ready() -> void:
	_build()
	_apply_angle()
	# Starts idle-open (waiting for a coin); no per-frame work until a transition.
	set_process(false)


func _build() -> void:
	var t: VisualTheme = ThemeProvider.theme
	# Roughly 2/3 of a bucket's width; same thinness as an inactive bucket.
	var gate_width: float = t.bucket_width * (2.0 / 3.0)
	var flap_width: float = gate_width * 0.5
	var thickness: float = t.bucket_height
	var depth: float = t.bucket_depth

	var mat := StandardMaterial3D.new()
	mat.albedo_color = t.peg_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Hinge each flap at the OUTER edge of the gate (like double doors opening at
	# the centre): left pivot at the left edge, right pivot at the right edge.
	_left_pivot = _make_flap(mat, flap_width, thickness, depth, -1.0)
	_right_pivot = _make_flap(mat, flap_width, thickness, depth, 1.0)
	_left_pivot.position.x = -gate_width * 0.5
	_right_pivot.position.x = gate_width * 0.5
	add_child(_left_pivot)
	add_child(_right_pivot)


## Pivot Node3D at a gate edge holding a flap that extends toward the centre seam,
## so rotating the pivot hinges the flap at the outer edge. `side` is -1 (left
## flap, hinged at the left edge, extends +x toward centre) or +1 (right flap,
## hinged at the right edge, extends -x toward centre).
func _make_flap(mat: StandardMaterial3D, flap_width: float, thickness: float, depth: float, side: float) -> Node3D:
	var pivot := Node3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(flap_width, thickness, depth)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(-side * flap_width * 0.5, 0.0, 0.0)
	pivot.add_child(mi)
	return pivot


## Drop-ready: swing the flaps down to vertical.
func open() -> void:
	_close_requested = false
	if _state == State.OPEN or _state == State.OPENING:
		return
	_state = State.OPENING
	set_process(true)


## Coin passed through: swing the flaps back up to horizontal. If still opening,
## the close runs once vertical is reached (full down-then-up motion).
func close() -> void:
	_close_requested = true
	if _state == State.OPEN:
		_state = State.CLOSING
		set_process(true)


func _process(delta: float) -> void:
	# Divide out time_scale so the swing stays real-time during prestige slow-mo
	# (the CoinBurstField idiom).
	var d: float = delta / maxf(Engine.time_scale, 0.0001)
	match _state:
		State.OPENING:
			_angle = minf(1.0, _angle + d / OPEN_SECONDS)
			if _angle >= 1.0:
				_state = State.CLOSING if _close_requested else State.OPEN
		State.CLOSING:
			_angle = maxf(0.0, _angle - d / CLOSE_SECONDS)
			if _angle <= 0.0:
				_state = State.CLOSED
	_apply_angle()
	if _state == State.OPEN or _state == State.CLOSED:
		set_process(false)


func _apply_angle() -> void:
	# Free ends meet at the centre seam. Left flap (hinged at left edge, extends
	# +x) swings its centre end down with -z; right flap (extends -x) with +z.
	var swing: float = _angle * (PI * 0.5)
	if _left_pivot:
		_left_pivot.rotation.z = -swing
	if _right_pivot:
		_right_pivot.rotation.z = swing
