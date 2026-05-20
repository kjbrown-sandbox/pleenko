class_name MenuTriangleField
extends Node3D

## Decorative drifting-triangle backdrop for the main menu, sitting BEHIND the
## 3D peg lattice for a sense of subtle depth ("more is happening").
##
## Why menu-local, NOT the gameplay `bg_particles` system: this is intentionally
## independent of `VisualTheme.bg_particles_enabled` and is always shown on the
## menu. It shares no state with `entities/background_particles/`; it only
## *copies that node's proven pooled pattern* (a fixed instance pool that fades
## in / holds / fades out and recycles — never allocates or frees at runtime).
##
## Why a fixed pool, not a spawn Timer (the sibling MenuBoard coin model): zero
## per-spawn churn on an idle screen, one draw call, and the pool size is the
## hard instance cap by construction.
##
## Why filled triangles in shades very close to the background: low contrast so
## overlaps read as soft tonal depth, not hard stripes.
##
## Color is re-read on each recycle (and live each `_process`), so theme swaps
## fade through naturally as the pool turns over — no `theme_changed`
## subscription needed.

## Pool size. Fixed — never grows — so an idle menu can't leak instances; this
## count IS the hard cap by construction.
@export var triangle_count: int = 120

## Z of the backdrop. Pegs/coins ride z=0 (see MenuBoard `COIN_Z_OFFSET`); this
## sits behind them so triangles never occlude the lattice.
@export var triangle_z: float = -3.0

## Centre of the spawn band in node-local XY (the menu uses a hand-tuned world
## rect; gameplay parents this under ParallaxBackdrop and centres at (0,0) so
## the spawn band tracks the camera). Half-size is the spawn extent.
@export var spawn_zone_center: Vector2 = Vector2(0.0, -17.0)
@export var spawn_zone_half_extent: Vector2 = Vector2(34.0, 28.0)

## 15% padding so triangles drift in from off-screen rather than popping.
const MENU_TRI_SPAWN_PAD := 1.15

## Per-triangle world size is randomised between these (centroid-to-vertex *2-ish).
@export var triangle_size_min: float = 1.5
@export var triangle_size_max: float = 7.0

## Drift speed CEILING in units/sec (each picks randf_range(half, this)).
@export var triangle_drift_speed: float = 0.35

## When true, every triangle picks ONE of the theme's two configured shades
## (`triangle_light_color` / `triangle_dark_color`) as a flat raw colour —
## no theme-background-derived darken/lighten. The menu leaves this false
## (background-tinted greys); the gameplay backdrop sets it true.
@export var use_theme_triangle_shades: bool = false

## Per-triangle PEAK alpha is rolled randomly in [min, max] at spawn — varies
## triangle-to-triangle, multiplied into the fade-in/hold/fade-out curve. Menu
## defaults to a flat 1.0 (no variation); the gameplay backdrop overrides to
## 0.2/0.8 so dense overlap doesn't wash the background.
@export_range(0.0, 1.0, 0.01) var min_peak_alpha: float = 1.0
@export_range(0.0, 1.0, 0.01) var max_peak_alpha: float = 1.0

## Spin speed MAGNITUDE in rad/sec (each picks randf_range(-this, this)).
const MENU_TRI_ROT_SPEED := 0.2

## One value for BOTH the fade-in and the fade-out ramp (seconds).
const MENU_TRI_FADE_SEC := 2.5

## Fully-visible duration between the fade ramps (seconds).
const MENU_TRI_HOLD_SEC := 6.0

## How far each triangle's colour departs from the background (0..1, fed to
## Color.darkened/lightened). Colour itself is theme-sourced; only this
## magnitude is a local tuning const.
const MENU_TRI_COLOR_SHIFT := 0.10

## On a light background, bias toward darkening (vs lightening) and vice-versa,
## so triangles read against the bg either way.
const DARKEN_BIAS := 0.7

const TRI_SHADER := preload("res://entities/plinko_board/drop_burst_multimesh.gdshader")


## Per-triangle animation state (mirrors background_particles' ParticleState).
class TriangleState:
	var elapsed := 0.0
	var total_life := 0.0
	var start_pos := Vector3.ZERO
	var drift := Vector3.ZERO
	var rotation_speed := 0.0
	var current_rotation := 0.0
	var size := 0.0
	var base_color := Color.WHITE
	var peak_alpha := 1.0


var _triangles: Array[TriangleState] = []
var _mm_instance: MultiMeshInstance3D
var _hidden_xform := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, -9999.0, 0.0))


func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	_build_multimesh()
	_init_triangles(t)


func _build_multimesh() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = triangle_count
	mm.mesh = _make_triangle_mesh()

	for i in triangle_count:
		mm.set_instance_transform(i, _hidden_xform)

	_mm_instance = MultiMeshInstance3D.new()
	_mm_instance.multimesh = mm
	# Shared, already-warm shader: unshaded, blend_mix, depth_draw_never.
	# Negative render_priority forces these to draw BEFORE (behind) the pegs —
	# the pegs are also transparent (per-row alpha), so without this the
	# distance-sorted transparent pass could paint a triangle over a peg.
	# Triangles must never cover the pegs.
	var mat := ShaderMaterial.new()
	mat.shader = TRI_SHADER
	mat.render_priority = -1
	_mm_instance.material_override = mat
	add_child(_mm_instance)


## One flat equilateral triangle centred on its centroid (so per-instance
## Basis.scaled pivots about the centre, like background_particles' quad).
func _make_triangle_mesh() -> ArrayMesh:
	var r := 0.5  # centroid -> vertex; per-instance size scales this
	var h := r * sqrt(3.0) / 2.0
	var verts := PackedVector3Array([
		Vector3(0.0, r, 0.0),
		Vector3(-h, -r * 0.5, 0.0),
		Vector3(h, -r * 0.5, 0.0),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


func _init_triangles(t: VisualTheme) -> void:
	_triangles.resize(triangle_count)
	var total_cycle := MENU_TRI_FADE_SEC + MENU_TRI_HOLD_SEC + MENU_TRI_FADE_SEC
	for i in triangle_count:
		var tri := TriangleState.new()
		_randomize_triangle(tri, t)
		# Stagger so they don't all sync on first load.
		tri.elapsed = randf() * total_cycle
		_triangles[i] = tri


func _process(delta: float) -> void:
	if _triangles.is_empty():
		return
	var mm := _mm_instance.multimesh
	var t: VisualTheme = ThemeProvider.theme
	for i in _triangles.size():
		var tri := _triangles[i]
		tri.elapsed += delta
		if tri.elapsed >= tri.total_life:
			_recycle_triangle(tri, t)
		tri.current_rotation += tri.rotation_speed * delta
		var alpha := compute_alpha(tri.elapsed, MENU_TRI_FADE_SEC, MENU_TRI_HOLD_SEC) * tri.peak_alpha
		var pos: Vector3 = tri.start_pos + tri.drift * tri.elapsed
		var basis := Basis.IDENTITY.scaled(Vector3.ONE * tri.size).rotated(
			Vector3.FORWARD, tri.current_rotation)
		mm.set_instance_transform(i, Transform3D(basis, pos))
		mm.set_instance_color(i, Color(
			tri.base_color.r, tri.base_color.g, tri.base_color.b, alpha))


## Pure piecewise fade curve: ramp up over `fade`, hold at 1, ramp down over
## `fade`. Static + float-only so it's unit-testable on a bare instance.
static func compute_alpha(elapsed: float, fade: float, hold: float) -> float:
	if elapsed <= 0.0:
		return 0.0
	if elapsed < fade:
		return elapsed / fade
	var fade_out_start := fade + hold
	if elapsed <= fade_out_start:
		return 1.0
	var total_life := fade_out_start + fade
	if elapsed >= total_life:
		return 0.0
	return 1.0 - (elapsed - fade_out_start) / fade


func _recycle_triangle(tri: TriangleState, t: VisualTheme) -> void:
	_randomize_triangle(tri, t)
	tri.elapsed = 0.0
	tri.current_rotation = 0.0


func _randomize_triangle(tri: TriangleState, t: VisualTheme) -> void:
	tri.total_life = MENU_TRI_FADE_SEC + MENU_TRI_HOLD_SEC + MENU_TRI_FADE_SEC
	tri.size = randf_range(triangle_size_min, triangle_size_max)
	tri.rotation_speed = randf_range(-MENU_TRI_ROT_SPEED, MENU_TRI_ROT_SPEED)
	tri.base_color = _pick_color(t)
	tri.peak_alpha = randf_range(min_peak_alpha, max_peak_alpha)
	var rect := _spawn_rect()
	tri.start_pos = Vector3(
		randf_range(rect.position.x, rect.end.x),
		randf_range(rect.position.y, rect.end.y),
		triangle_z)
	var angle := randf() * TAU
	var speed := randf_range(triangle_drift_speed * 0.5, triangle_drift_speed)
	tri.drift = Vector3(cos(angle) * speed, sin(angle) * speed, 0.0)


## Colour very close to the background (theme-sourced), nudged toward whichever
## direction reads against it. Mirrors background_particles._pick_color.
## Short-circuits to a coin-flip pick between the theme's two configured
## shades (triangle_light_color / triangle_dark_color) when two-shade mode is on.
func _pick_color(t: VisualTheme) -> Color:
	if use_theme_triangle_shades:
		return t.triangle_light_color if randf() < 0.5 else t.triangle_dark_color
	var bg: Color = t.background_color
	var shift := MENU_TRI_COLOR_SHIFT
	var luminance := bg.get_luminance()
	if luminance > 0.5:
		if randf() < DARKEN_BIAS:
			return bg.darkened(randf_range(shift * 0.5, shift))
		return bg.lightened(randf_range(shift * 0.3, shift * 0.7))
	if randf() < DARKEN_BIAS:
		return bg.lightened(randf_range(shift * 0.5, shift))
	return bg.darkened(randf_range(shift * 0.3, shift * 0.7))


## Pure static rect helper — unit-testable on a bare instance (no scene tree).
static func spawn_rect_for(center: Vector2, half_extent: Vector2, pad: float) -> Rect2:
	var half_w := half_extent.x * pad
	var half_h := half_extent.y * pad
	return Rect2(
		center.x - half_w,
		center.y - half_h,
		half_w * 2.0,
		half_h * 2.0)


func _spawn_rect() -> Rect2:
	return spawn_rect_for(spawn_zone_center, spawn_zone_half_extent, MENU_TRI_SPAWN_PAD)
