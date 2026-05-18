class_name DeflectorEditor
extends Node3D

## Player-facing peg-deflector placement UI. Pure view + input: it raycasts the
## mouse onto the board, asks the board (the model) what a click means, and
## emits an intent UP. PlinkoBoard mutates _deflectors and calls refresh() DOWN.
## Signals up, calls down.
##
## Interaction: hovering an empty peg shows a small translucent arrow on the
## side of the peg the cursor is on (left/right) — clicking places a deflector
## on that side. Hovering a peg that already has one shows an X above it —
## clicking removes it.

## dir is an Enums.Direction (+1 right / -1 left), or 0 to remove a deflector.
signal deflector_change_requested(peg_index: int, dir: int)

const IconScene := preload("res://entities/icon/icon.tscn")
const CloseIcon := preload("res://assets/icons/close.png")
const ArrowShader := preload("res://entities/deflector_editor/deflector_arrow.gdshader")

const PICK_RADIUS_FACTOR := 0.6     ## fraction of space_between_pegs counted as a hit
const ARROW_SIDE_FACTOR := 0.26     ## how far the arrow sits to the side of the peg
const X_SCREEN_OFFSET_Y := 42.0     ## px the remove-X floats above the peg on screen
const Z_LIFT := 0.06                ## render overlays slightly in front of pegs

var _board: PlinkoBoard
var _ghost_arrow: MeshInstance3D     # shown while hovering an empty, placeable peg
# Remove-X is a screen-space TintedIcon (themed glyph + hover tint), not a 3D
# mesh — it sits on its own CanvasLayer and tracks the hovered peg.
var _x_canvas: CanvasLayer
var _x_icon: TintedIcon
var _x_peg := -1                     # peg the remove-X currently targets, or -1
var _placed: Array[MeshInstance3D] = []  # pooled solid arrows, one per deflector
# peg_idx -> {elapsed, color, pulse, duration} for an active HIT/MISS reaction.
# The arrow snaps to `color` on the bounce; _process eases it back to the peg
# colour (and, when `pulse`, scales it up then back to 1.0) over `duration`.
# No tween — same allocation-free _process fade PlinkoBoard.flash_nearest_peg
# uses for peg flashes. Cleared wherever the pooled arrows are re-bound or
# re-materialised (refresh / theme / deactivate / exit) so a half-finished
# reaction can't leave the wrong arrow stuck coloured or scaled.
var _active_glows: Dictionary = {}

# Enable gates — input runs only when all are satisfied.
var _input_allowed := true  # toggled by Main.apply_input_lock (peek/prestige)
var _is_active := true      # this board is the visible/active one
var _capacity := 0          # global Deflector cap (0 = not owned)

var _hovered_peg := -1
var _last_mouse := Vector2.ZERO

# Discoverability pulse — runs on the ghost arrow (and an optional center-peg
# hint) until the player places their first-ever deflector.
var _pulse_tween: Tween
var _hint: MeshInstance3D
var _hint_tween: Tween


func setup(board: PlinkoBoard) -> void:
	_board = board
	_build_visuals()
	_apply_theme()
	ThemeProvider.theme_changed.connect(_apply_theme)
	if not OnboardingProgress.has_placed_deflector():
		_pulse_tween = _loop_pulse(_ghost_arrow)
	_update_input_enabled()
	set_process(false)  # only runs while a HIT glow is active


func _exit_tree() -> void:
	if ThemeProvider.theme_changed.is_connected(_apply_theme):
		ThemeProvider.theme_changed.disconnect(_apply_theme)
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	_clear_glows()


# ── External control (called DOWN by PlinkoBoard / BoardManager / Main) ──

func set_capacity(n: int) -> void:
	_capacity = n
	_update_input_enabled()
	refresh()


func set_active(active: bool) -> void:
	_is_active = active
	if not active:
		_hide_hover()
		_clear_glows()
	_update_input_enabled()


func set_input_allowed(allowed: bool) -> void:
	_input_allowed = allowed
	if not allowed:
		_hide_hover()
	_update_input_enabled()


## Rebuild placed-arrow visuals from the board model. Called after every
## placement/removal and at the end of build_board() (peg positions shift).
func refresh() -> void:
	if not is_instance_valid(_board) or _placed == null:
		return
	# Pool slots are about to be re-bound by index — drop any active glow first
	# so it can't keep colouring a now-different peg's arrow.
	_clear_glows()
	var keys: Array = _board.get_deflector_keys()
	for i in keys.size():
		var peg_idx: int = keys[i]
		var dir: int = _board.get_deflector_dir(peg_idx)
		var arrow := _get_or_make_arrow(i)
		_orient_arrow(arrow, _board.get_peg_local_position(peg_idx), dir)
		arrow.visible = true
	for j in range(keys.size(), _placed.size()):
		_placed[j].visible = false
	if OnboardingProgress.has_placed_deflector():
		_stop_pulses()
	_update_hover(_last_mouse)


# ── Input ──

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_last_mouse = event.position
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if _handle_click(event.position):
			get_viewport().set_input_as_handled()


func _handle_click(mouse_pos: Vector2) -> bool:
	var local = _raycast_to_local(mouse_pos)
	if local == null:
		return false
	var peg := _board.nearest_peg_index_to_local(
		local, _board.space_between_pegs * PICK_RADIUS_FACTOR)
	if peg == -1:
		return false
	match _board.resolve_click_action(peg):
		PlinkoBoard.ClickAction.REMOVE:
			deflector_change_requested.emit(peg, 0)
			return true
		PlinkoBoard.ClickAction.PLACE:
			deflector_change_requested.emit(peg, _side_dir(local, peg))
			return true
		_:
			return false


# ── Hover ──

func _update_hover(mouse_pos: Vector2) -> void:
	if not is_instance_valid(_ghost_arrow):
		return
	var local = _raycast_to_local(mouse_pos)
	if local == null:
		_hide_hover()
		return
	var peg := _board.nearest_peg_index_to_local(
		local, _board.space_between_pegs * PICK_RADIUS_FACTOR)
	if peg == -1:
		_hide_hover()
		return
	_hovered_peg = peg
	var peg_pos: Vector3 = _board.get_peg_local_position(peg)
	if _board.has_deflector(peg):
		# Already placed — show the remove-X above it, hide the ghost.
		_ghost_arrow.visible = false
		_show_remove_x(peg)
	elif _board.resolve_click_action(peg) == PlinkoBoard.ClickAction.PLACE:
		# Empty + a free slot — preview an arrow on the cursor's side.
		_hide_remove_x()
		_orient_arrow(_ghost_arrow, peg_pos, _side_dir(local, peg))
		_ghost_arrow.visible = true
	else:
		_hide_hover()


## Position the screen-space remove-X over a placed-deflector peg.
func _show_remove_x(peg: int) -> void:
	if not is_instance_valid(_x_icon):
		return
	var cam := _board.get_active_camera()
	if cam == null:
		_hide_remove_x()
		return
	var world: Vector3 = _board.to_global(_board.get_peg_local_position(peg))
	var screen: Vector2 = cam.unproject_position(world)
	_x_peg = peg
	_x_icon.position = screen - _x_icon.size * 0.5 - Vector2(0, X_SCREEN_OFFSET_Y)
	_x_icon.visible = true


func _hide_remove_x() -> void:
	_x_peg = -1
	if is_instance_valid(_x_icon):
		_x_icon.visible = false


func _hide_hover() -> void:
	_hovered_peg = -1
	if is_instance_valid(_ghost_arrow):
		_ghost_arrow.visible = false
	_hide_remove_x()


## Which side of the peg the cursor is on → the direction to deflect.
func _side_dir(local: Vector3, peg_idx: int) -> int:
	var peg_x: float = _board.get_peg_local_position(peg_idx).x
	return Enums.Direction.RIGHT if local.x >= peg_x else Enums.Direction.LEFT


# ── Raycast ──

func _raycast_to_local(mouse_pos: Vector2):
	var cam := _board.get_active_camera()
	if cam == null:
		return null
	var from := cam.project_ray_origin(mouse_pos)
	var dir := cam.project_ray_normal(mouse_pos)
	# Board pegs live on its local z = 0 plane; build it in world space
	# (boards are translated apart by BoardManager).
	var n := _board.global_transform.basis.z.normalized()
	var plane := Plane(n, n.dot(_board.global_position))
	var hit = plane.intersects_ray(from, dir)
	if hit == null:
		return null
	return _board.to_local(hit)


# ── Enable gate ──

func _update_input_enabled() -> void:
	var on: bool = _input_allowed and _is_active and _capacity > 0 \
		and not ModeManager.is_challenges()
	set_process_unhandled_input(on)
	if not on:
		_hide_hover()


# ── Mesh / theme construction ──

func _build_visuals() -> void:
	_ghost_arrow = MeshInstance3D.new()
	_ghost_arrow.mesh = _make_arrow_mesh()
	_ghost_arrow.visible = false
	add_child(_ghost_arrow)

	# Remove-marker: a screen-space TintedIcon (same component every other icon
	# uses — themed glyph, hover tint + pulse). On its own CanvasLayer so it
	# renders above the 3D scene; tracks the hovered peg's projected position.
	_x_canvas = CanvasLayer.new()
	add_child(_x_canvas)
	_x_icon = IconScene.instantiate()
	_x_icon.icon_texture = CloseIcon
	_x_icon.color_source = _board.get_peg_palette_source()
	# Standalone (no container) — set explicitly. custom_minimum_size too, or the
	# scene's 32px minimum would clamp size back up.
	_x_icon.custom_minimum_size = Vector2(30, 30)
	_x_icon.size = Vector2(30, 30)
	_x_icon.visible = false
	_x_canvas.add_child(_x_icon)
	_x_icon.pressed.connect(_on_remove_x_pressed)


func _on_remove_x_pressed() -> void:
	if _x_peg >= 0:
		deflector_change_requested.emit(_x_peg, 0)


## Quad sized to the arrow's real dimensions: base = peg diameter (so the flat
## side lines up with the peg top/bottom), length = 2x the base (long isosceles).
## Apex is along local +Y; _orient_arrow rotates it ±90° to point left/right.
func _arrow_base() -> float:
	return ThemeProvider.theme.peg_radius * 2.0


func _make_arrow_mesh() -> Mesh:
	var base := _arrow_base()
	var quad := QuadMesh.new()
	quad.size = Vector2(base, base * 2.0)
	return quad


## Unshaded rounded-triangle material. tri_size/corner_radius are in world
## units so the shape and rounding stay correct independent of quad aspect.
func _arrow_mat(color: Color) -> ShaderMaterial:
	var base := _arrow_base()
	var mat := ShaderMaterial.new()
	mat.shader = ArrowShader
	mat.set_shader_parameter("tint_color", color)
	mat.set_shader_parameter("tri_size", Vector2(base, base * 2.0))
	mat.set_shader_parameter("corner_radius", ThemeProvider.theme.peg_radius * 0.3)
	return mat


## The arrow's local position for a peg + dir — the single source of truth for
## arrow placement, used by _orient_arrow (placed arrows and the MISS ghost).
func _arrow_rest_position(peg_pos: Vector3, dir: int) -> Vector3:
	var off: float = _board.space_between_pegs * ARROW_SIDE_FACTOR
	return Vector3(peg_pos.x + dir * off, peg_pos.y, peg_pos.z - Z_LIFT)


## Position an arrow on the dir side of a peg, apex pointing that way.
func _orient_arrow(arrow: MeshInstance3D, peg_pos: Vector3, dir: int) -> void:
	arrow.position = _arrow_rest_position(peg_pos, dir)
	# Shader draws the apex at +Y; rotate so it points +x (right) or -x (left).
	arrow.rotation = Vector3(0, 0, -PI / 2.0 if dir == Enums.Direction.RIGHT else PI / 2.0)


func _apply_theme() -> void:
	if not is_instance_valid(_ghost_arrow):
		return
	var t: VisualTheme = ThemeProvider.theme

	# Pegs render via their own always-unshaded shader, so deflector visuals
	# must be unshaded too (unconditionally) to match them under any theme.

	# Stop active glows BEFORE swapping materials, so _process can't keep
	# writing tint to a now-detached material and pop the arrow.
	_clear_glows()
	# Placed arrows read as structural board elements → peg color.
	for arrow in _placed:
		arrow.material_override = _arrow_mat(t.peg_color)
	# Remove-X: TintedIcon owns its own themed tint + hover behavior; just
	# refresh its resting tint to the (possibly swapped) peg palette color.
	if is_instance_valid(_x_icon) and _x_icon.material is ShaderMaterial:
		_x_icon.color_source = _board.get_peg_palette_source()
		_x_icon.material.set_shader_parameter("tint_color", t.peg_color)

	_ghost_arrow.material_override = _arrow_mat(_ghost_color())
	# The hint is a peg-shaped node — keep it the NEUTRAL peg color so the
	# center peg never looks recolored; the pulse alone draws the eye.
	if is_instance_valid(_hint) and _hint.material_override is StandardMaterial3D:
		_hint.material_override.albedo_color = t.peg_color


func _flat_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Placement-preview ("ghost") arrow colour: the neutral peg colour at 50%
## opacity — a subtle hint, never a vivid tier colour, and distinct from the
## opaque peg-coloured placed arrow.
func _ghost_color() -> Color:
	var c: Color = ThemeProvider.theme.peg_color
	c.a = 0.5
	return c


## A looping subtle scale pulse (same cadence as the UI attention blink).
func _loop_pulse(node: Node3D) -> Tween:
	var half: float = ThemeProvider.theme.attention_blink_duration / 2.0
	var tw := node.create_tween().set_loops()
	tw.tween_property(node, "scale", Vector3.ONE * 1.18, half) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "scale", Vector3.ONE, half) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	return tw


## Spawn a pulsing peg-shaped highlight at the center peg (driven by the intro
## animator). No-op once the player has already placed a deflector.
func start_center_peg_hint(peg_idx: int) -> void:
	if OnboardingProgress.has_placed_deflector() or is_instance_valid(_hint):
		return
	var t: VisualTheme = ThemeProvider.theme
	_hint = MeshInstance3D.new()
	_hint.mesh = t.make_peg_mesh()
	# Start exactly peg-sized so _loop_pulse grows/shrinks it gently from rest
	# (like the arrow pulse) — no sudden jump to a large scale on the first beat.
	# Neutral peg color — it mimics a peg; the pulse is the attention cue.
	_hint.material_override = _flat_mat(t.peg_color)
	var p: Vector3 = _board.get_peg_local_position(peg_idx)
	_hint.position = Vector3(p.x, p.y, p.z - Z_LIFT)
	add_child(_hint)
	_hint_tween = _loop_pulse(_hint)


func _stop_pulses() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = null
	if is_instance_valid(_ghost_arrow):
		_ghost_arrow.scale = Vector3.ONE
	if is_instance_valid(_hint):
		_hint.queue_free()
		_hint = null


func _get_or_make_arrow(i: int) -> MeshInstance3D:
	while i >= _placed.size():
		var mi := MeshInstance3D.new()
		mi.mesh = _make_arrow_mesh()
		mi.material_override = _arrow_mat(ThemeProvider.theme.peg_color)
		mi.visible = false
		add_child(mi)
		_placed.append(mi)
	return _placed[i]


# ── Reaction VFX ───────────────────────────────────────────────────────
# Both HIT and MISS briefly tint the real pooled arrow, then _process eases it
# back to the peg colour — the same allocation-free fade
# PlinkoBoard.flash_nearest_peg uses for peg flashes (no tween, no spawned
# nodes). HIT also adds a soft grow→shrink scale pulse. Colours are palette
# assignments on the theme. Pure view, driven DOWN by
# PlinkoBoard.notify_deflector_resolved.


## HIT: the coin FOLLOWED the placed deflector at peg_idx. Tints its arrow one
## neutral shade darker (theme.deflector_hit_color) and gives it a soft
## grow→shrink pulse; both ease back over deflector_hit_glow_duration.
func play_deflector_hit(peg_idx: int) -> void:
	var t: VisualTheme = ThemeProvider.theme
	_start_reaction(peg_idx, t.deflector_hit_color, true, t.deflector_hit_glow_duration)


## MISS: the coin escaped AGAINST the placed deflector at peg_idx. Flashes that
## same arrow red (theme.deflector_miss_color), easing back over
## deflector_miss_fade_duration. No pulse, no opposite-side ghost.
func play_deflector_miss(peg_idx: int) -> void:
	var t: VisualTheme = ThemeProvider.theme
	_start_reaction(peg_idx, t.deflector_miss_color, false, t.deflector_miss_fade_duration)


## Begin a reaction on peg_idx's placed arrow: snap it to `color` (and reset
## scale), record it, and let _process ease the colour back to the peg colour
## — and, when `pulse`, the scale up then back to 1.0 — over `duration`.
func _start_reaction(peg_idx: int, color: Color, pulse: bool, duration: float) -> void:
	if not ThemeProvider.theme.deflector_reaction_enabled or not is_instance_valid(_board):
		return
	var i: int = _board.get_deflector_keys().find(peg_idx)
	if i < 0 or i >= _placed.size():
		return
	var arrow: MeshInstance3D = _placed[i]
	if not is_instance_valid(arrow) or not arrow.visible:
		return
	var mat: Material = arrow.material_override
	if not (mat is ShaderMaterial):
		return
	arrow.scale = Vector3.ONE  # clean start (a prior pulse may have left it scaled)
	mat.set_shader_parameter("tint_color", color)
	_active_glows[peg_idx] = {
		"elapsed": 0.0,
		"color": color,
		"pulse": pulse,
		"duration": maxf(duration, 0.001),
	}
	set_process(true)


## Eases every active reaction back toward the peg colour (and scale 1.0), then
## stops itself once none remain. peg_idx → _placed slot is resolved each frame
## (the pool is re-bound by index on refresh, but refresh also _clear_glows()).
func _process(delta: float) -> void:
	if _active_glows.is_empty() or not is_instance_valid(_board):
		set_process(false)
		return
	var peg: Color = ThemeProvider.theme.peg_color
	var peak: float = ThemeProvider.theme.deflector_hit_pulse_scale
	var keys: Array = _board.get_deflector_keys()
	var done: Array = []
	for peg_idx in _active_glows:
		var g: Dictionary = _active_glows[peg_idx]
		g["elapsed"] += delta
		var k: float = clampf(g["elapsed"] / g["duration"], 0.0, 1.0)
		var i: int = keys.find(peg_idx)
		if i >= 0 and i < _placed.size() and is_instance_valid(_placed[i]):
			var arrow: MeshInstance3D = _placed[i]
			var m: Material = arrow.material_override
			if m is ShaderMaterial:
				m.set_shader_parameter("tint_color", (g["color"] as Color).lerp(peg, k))
			if g["pulse"]:
				# sin(k·π): 0 at start/end, 1 at the midpoint — grow then shrink.
				arrow.scale = Vector3.ONE * (1.0 + (peak - 1.0) * sin(k * PI))
		if k >= 1.0:
			done.append(peg_idx)
	for peg_idx in done:
		_active_glows.erase(peg_idx)
	if _active_glows.is_empty():
		set_process(false)


## Stop every active reaction and snap those arrows back to the peg colour and
## scale 1.0. Called wherever the pooled arrows are about to be re-bound or
## re-materialised (refresh / theme / deactivate / exit), so a half-finished
## reaction can't leave the wrong arrow stuck coloured or scaled. Deterministic.
func _clear_glows() -> void:
	for peg_idx in _active_glows.keys():
		if not is_instance_valid(_board):
			break
		var i: int = _board.get_deflector_keys().find(peg_idx)
		if i < 0 or i >= _placed.size() or not is_instance_valid(_placed[i]):
			continue
		var arrow: MeshInstance3D = _placed[i]
		arrow.scale = Vector3.ONE
		if arrow.material_override is ShaderMaterial:
			arrow.material_override.set_shader_parameter(
				"tint_color", ThemeProvider.theme.peg_color)
	_active_glows.clear()
	set_process(false)
