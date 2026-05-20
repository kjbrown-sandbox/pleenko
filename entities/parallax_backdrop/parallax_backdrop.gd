class_name ParallaxBackdrop
extends Node3D

## Backdrop wrapper that lags behind the gameplay camera to fake parallax under
## an orthographic projection (depth alone produces no parallax — this does).
## Owns one MenuTriangleField child. Signals up, calls down.
##
## Math (per axis): wrapper.global = rest + (cam - rest) * (1 - parallax_factor).
## - parallax_factor = 0 → wrapper sticks to camera, no parallax.
## - parallax_factor = 1 → wrapper stays at rest, full parallax (world-fixed).
## - 0.20 (default) → wrapper moves at 80% of camera speed (subtle lag).

@export_range(0.0, 1.0, 0.01) var parallax_factor: float = 0.20
@export_range(0.0, 1.0, 0.01) var zoom_factor: float = 0.5

var _camera: Camera3D
# Wrapper's own authored anchor position. Z is preserved on the anchor — the
# camera's Z is intentionally ignored, otherwise the wrapper would inherit the
# camera Z (~7) and push the triangles in FRONT of the pegs at world Z=0.
var _anchor: Vector3 = Vector3.ZERO
var _rest_cam: Vector3 = Vector3.ZERO
var _rest_size: float = 0.0
var _initialised: bool = false


func _ready() -> void:
	# Read camera AFTER BoardManager's camera tween writes on the same frame.
	process_priority = 10


func setup(camera: Camera3D) -> void:
	_camera = camera
	# Defer one frame so BoardManager.setup → _snap_camera_to_active_board has run.
	call_deferred("_capture_rest")


func _capture_rest() -> void:
	if _camera == null:
		return
	_anchor = global_position
	_rest_cam = _camera.global_position
	_rest_size = _camera.size
	_initialised = true


## Pure static parallax math — anchors the wrapper at `anchor` and parallaxes
## by the camera's XY delta from `cam_rest`. Z stays at `anchor.z` (the
## camera's Z is deliberately not propagated — see notes on _anchor above).
static func parallax_offset(cam_pos: Vector3, cam_rest: Vector3, anchor: Vector3, factor: float) -> Vector3:
	var follow := 1.0 - factor
	return Vector3(
		anchor.x + (cam_pos.x - cam_rest.x) * follow,
		anchor.y + (cam_pos.y - cam_rest.y) * follow,
		anchor.z)


## Pure static zoom math — scale tracks (cam.size / rest_size) blended by zoom_factor.
static func parallax_scale(cam_size: float, rest_size: float, factor: float) -> float:
	if rest_size <= 0.0:
		return 1.0
	return lerp(1.0, cam_size / rest_size, factor)


func _process(_delta: float) -> void:
	if not _initialised:
		return
	global_position = parallax_offset(
		_camera.global_position, _rest_cam, _anchor, parallax_factor)
	var s := parallax_scale(_camera.size, _rest_size, zoom_factor)
	scale = Vector3(s, s, 1.0)
