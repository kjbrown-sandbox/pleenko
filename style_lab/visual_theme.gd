@tool
class_name VisualTheme
extends Resource

## A bundled "look" for the Plinko game.  Swap a single .tres to change
## every colour, size, and VFX parameter at once.

# Mirror Enums.CurrencyType values so this works in @tool context
# without requiring Enums to be @tool.
const GOLD_COIN := 0
const RAW_ORANGE := 1
const ORANGE_COIN := 2
const RAW_RED := 3
const RED_COIN := 4
const RAW_VIOLET := 5
const VIOLET_COIN := 6
const RAW_BLUE := 7
const BLUE_COIN := 8
const RAW_GREEN := 9
const GREEN_COIN := 10

# ── Palette enum ─────────────────────────────────────────────────────
enum Palette {
	BG_1 = 0, BG_2 = 1, BG_3 = 2, BG_4 = 3, BG_5 = 4, BG_6 = 5,
	GOLD_FADED = 6, GOLD_MAIN = 7,
	ORANGE_FADED = 9, ORANGE_MAIN = 10,
	RED_FADED = 12, RED_MAIN = 13,
	BG_7 = 15,
	VIOLET_FADED = 16, VIOLET_MAIN = 17,
	BLUE_FADED = 18, BLUE_MAIN = 19,
	GREEN_FADED = 20, GREEN_MAIN = 21,
}

# ── Colors (master palette) ──────────────────────────────────────────
# Background shades: seven steps from darkest to lightest
@export_group("Colors – Background")
@export var bg_shade_7 := Color(0.06, 0.05, 0.04)                # darkest
@export var bg_shade_1 := Color(0.12, 0.11, 0.10)
@export var bg_shade_2 := Color(0.25, 0.24, 0.22)
@export var bg_shade_3 := Color(0.45, 0.43, 0.40)
@export var bg_shade_4 := Color(0.65, 0.63, 0.60)
@export var bg_shade_5 := Color(0.85, 0.83, 0.80)
@export var bg_shade_6 := Color(0.96, 0.95, 0.92)                # lightest

# Per-currency colors: main (prominent) and faded (muted/disabled)
@export_group("Colors – Gold")
@export var gold_main := Color(0.85, 0.75, 0.25)
@export var gold_faded := Color(0.55, 0.45, 0.10)

@export_group("Colors – Orange")
@export var orange_main := Color(0.85, 0.45, 0.3)
@export var orange_faded := Color(0.55, 0.25, 0.12)

@export_group("Colors – Red")
@export var red_main := Color(0.7, 0.2, 0.25)
@export var red_faded := Color(0.4, 0.08, 0.1)

@export_group("Colors – Violet")
@export var violet_main := Color(0.50, 0.30, 0.55)
@export var violet_faded := Color(0.35, 0.18, 0.38)

@export_group("Colors – Blue")
@export var blue_main := Color(0.30, 0.42, 0.58)
@export var blue_faded := Color(0.18, 0.28, 0.40)

@export_group("Colors – Green")
@export var green_main := Color(0.35, 0.52, 0.30)
@export var green_faded := Color(0.20, 0.35, 0.18)

# ── Color assignments (pick from palette via dropdown) ───────────────
@export_group("Color Assignments")
@export var background_source: Palette = Palette.BG_7
@export var ambient_light_source: Palette = Palette.BG_5
@export var directional_light_source: Palette = Palette.BG_6
@export var peg_color_source: Palette = Palette.BG_4
@export var high_multiplier_source: Palette = Palette.RED_MAIN
@export var hit_bucket_source: Palette = Palette.BG_6            # color for hit/target/forbidden buckets
@export var normal_text_source: Palette = Palette.BG_6
@export var body_text_source: Palette = Palette.BG_4
@export var at_cap_text_source: Palette = Palette.RED_MAIN
@export var overlay_source: Palette = Palette.BG_7
@export var overlay_opacity := 0.6
@export var prestige_flash_source: Palette = Palette.BG_6  # color coin/bucket lerp toward during prestige

# ── Environment ──────────────────────────────────────────────────────
@export_group("Environment")
@export var unshaded := true                                      # flat color, no lighting
@export var ambient_light_energy := 0.4
@export var directional_light_energy := 0.8
@export var directional_light_angle := Vector3(-35, -20, 0)      # euler degrees

# ── Pegs ─────────────────────────────────────────────────────────────
@export_group("Pegs")
enum PegShape { SPHERE, CYLINDER }
@export var peg_shape: PegShape = PegShape.SPHERE
@export var peg_radius := 0.08
@export var peg_height := 0.05                                    # cylinder only
@export var peg_roughness := 0.9
@export var peg_metallic := 0.0

# ── Buckets ──────────────────────────────────────────────────────────
@export_group("Buckets")
@export var bucket_width := 0.75
@export var bucket_height := 0.08
@export var bucket_depth := 0.08
@export var bucket_roughness := 0.8
@export var bucket_metallic := 0.0
@export var bucket_label_font_size := 48
@export var bucket_label_offset := -0.3                           # vertical distance below bucket

# ── Text ─────────────────────────────────────────────────────────────
@export_group("Text")
@export var label_font: Font
@export var label_outline_size := 0                               # 0 = no outline
@export var floating_text_font_size := 40
@export var multi_drop_font_size := 48

# ── Coins ────────────────────────────────────────────────────────────
@export_group("Coins")
enum CoinShape { SPHERE, CYLINDER }  # keeping enum for _apply_visuals reference
const coin_shape := CoinShape.CYLINDER
@export var coin_radius := 0.15
@export var coin_height := 0.05                                   # cylinder only
@export var coin_roughness := 0.3
@export var coin_metallic := 0.4
@export var coin_emission_strength := 0.15                        # subtle glow
@export var coin_fall_time := 0.4                                 # seconds per row bounce
@export var coin_bounce_height := 0.2                             # upward arc between rows
@export var coin_halo_enabled := false                            # colored glow quad behind coin
@export var coin_halo_radius := 2.0                               # size relative to coin radius
@export var coin_halo_opacity := 0.15                             # glow intensity
@export var coin_silhouette := false                              # near-black coin with glow behind
@export var coin_silhouette_color := Color(0.06, 0.06, 0.06)

# Impact squash — coins flatten briefly when they hit a peg, then snap back
# to round. Pure cartoon punch, not velocity-driven.
@export_subgroup("Impact Squash")
@export var coin_impact_squash_enabled := true
## Peak deformation at the moment of contact. The default flattens vertically
## (Y < 1) and bulges horizontally (X/Z > 1) for a "splat" feel.
@export var coin_impact_squash_scale: Vector3 = Vector3(1.25, 0.75, 1.4)
## Seconds to recover from peak squash back to identity scale.
@export var coin_impact_squash_duration: float = 0.12

# ── Buttons ──────────────────────────────────────────────────────────
@export_group("Buttons")
@export var button_enabled_source: Palette = Palette.BG_4
@export var button_disabled_source: Palette = Palette.BG_3
@export var button_hovered_source: Palette = Palette.BG_6
@export var button_text_source: Palette = Palette.BG_6
@export var button_font: Font
@export var button_font_size := 20 
@export var button_padding := Vector2(16, 5)                      # horizontal, vertical
@export var button_border_radius := 4
@export var button_border_width := 3
@export var button_bg_source: Palette = Palette.BG_1
@export var button_fill_text_source: Palette = Palette.BG_7
@export var button_disabled_text_source: Palette = Palette.BG_3
@export var button_border_source: Palette = Palette.BG_4
@export var button_pulse_scale := 1.03
@export var button_pulse_duration := 0.12

# ── Spacing / Layout ────────────────────────────────────────────────
@export_group("Spacing")
@export var hud_margin := 20                                       # margin for HUD panels
@export var space_between_pegs := 1.0
@export var board_rows := 6                                       # demo row count
@export var board_spacing := 20.0											# space between boards in multi-board setups
@export var camera_tween_duration := 0.4                            # seconds for camera movement

# ── VFX ──────────────────────────────────────────────────────────────
@export_group("VFX")
@export var peg_glow_duration := 1.0                              # how long peg glows after coin touch
@export var peg_glow_intensity := 0.8                             # starting emission strength
@export var coin_land_particle_count := 8                         # scatter particles on landing
@export var coin_land_particle_speed := 2.0                       # how fast particles fly outward
@export var coin_land_particle_duration := 0.6                    # how long particles live
@export var bucket_pulse_scale := 1.15                            # scale on receive
@export var bucket_pulse_duration := 0.15
@export var floating_text_rise := 1.5                             # units upward
@export var floating_text_duration := 1.2
@export var coin_spawn_scale_from := 0.0                          # fade-in start scale
@export var coin_spawn_scale_duration := 0.15
@export var board_glow_enabled := true
@export var board_glow_radius := 6.0                              # size of the soft glow behind each board
@export var board_glow_opacity := 0.04                            # very subtle
@export var peg_glow_halo_enabled := false                        # soft radial halo around pegs when they light up
@export var peg_glow_halo_radius := 1.5
@export var peg_glow_halo_opacity := 0.06
@export var peg_flash_enabled := true                             # peg briefly takes coin color on contact
@export var peg_pulse_enabled := true                             # peg scale-pulse on coin contact
@export var bucket_pulse_enabled := true                          # bucket scale-pulse on receive
@export var drop_burst_enabled := true                            # particle burst at drop point

# Peg rings — expanding ripple at each peg hit, alternative/complement to the glow halo.
@export var peg_ring_enabled := false
@export var peg_ring_max_radius := 0.5                            # world units — how far the ring reaches
@export var peg_ring_duration := 0.9                              # seconds
@export var peg_ring_max_opacity := 0.35                          # peak alpha at sine apex
@export var peg_ring_thickness := 0.06                            # UV-space ring half-width

# ── Vignette ─────────────────────────────────────────────────────────
@export_group("Vignette")
@export var vignette_enabled := false
@export var vignette_intensity := 0.15                             # overall opacity of the darkened edges
@export var vignette_radius := 0.75                                # how far from center the effect starts
@export var vignette_softness := 0.45                              # how gradually the edge fades in
@export var vignette_color_source: Palette = Palette.BG_7          # tint color for the vignette

# ── Prestige Animation ──────────────────────────────────────────────
@export_group("Prestige Animation")
@export var prestige_slow_mo_scale := 0.15
@export var prestige_freeze_scale := 0.001
@export var prestige_slow_mo_duration := 1.5        ## Real-time seconds in slow-mo before freeze
@export var prestige_freeze_duration := 1.5          ## Real-time seconds frozen before expand
@export var prestige_expand_duration := 2.5          ## Real-time seconds for white flash to fill screen
@export var prestige_camera_zoom_size := 2.0         ## Orthographic size when zoomed on coin

# ── Prestige VFX ────────────────────────────────────────────────────
@export_group("Prestige VFX")
@export var prestige_shake_intensity := 0.008         ## Max camera offset in world units
@export var prestige_shake_duration := 1.5           ## Real-time seconds for shake to decay
@export var prestige_particle_count := 8             ## Number of burst particles
@export var prestige_particle_speed := 3.0           ## Outward velocity in units/sec
@export var prestige_particle_duration := 0.6        ## Real-time seconds before particles fade
@export var prestige_particle_radius := 0.04         ## Size of each particle sphere
@export var prestige_ring_duration := 5.0            ## Real-time seconds for ring to expand
@export var prestige_ring_count := 1                 ## Number of staggered shockwave rings
@export var prestige_ring_stagger := 0.25             ## Real-time seconds between each ring
@export var prestige_ring_max_scale := 8.0           ## Final ring scale multiplier
@export var prestige_desaturation_amount := 0.7           ## How much pegs/buckets fade toward background (0-1)

# ── Level Up VFX ────────────────────────────────────────────────────
@export_group("Level Up VFX")
@export var level_bar_shake_threshold := 0.85             ## Progress fraction to start shaking
@export var level_bar_shake_max_intensity := 2.0          ## Max pixel offset at 100%
@export var level_bar_shake_min_pct := 0.5                ## Starting intensity as fraction of max (0-1)
@export var level_up_particle_count := 30                 ## Number of burst particles from bar
@export var level_up_particle_burst_duration := 0.8       ## Seconds for initial burst phase
@export var level_up_particle_swoop_duration := 0.6       ## Seconds for particles to fly to target
@export var upgrade_materialize_duration := 0.8           ## Seconds for left-to-right reveal
@export var attention_blink_duration := 3.5               ## Seconds for one full on-off blink cycle

# ── Drop Burst VFX ───────────────────────────────────────────────────
@export_group("Drop Burst VFX")
@export var drop_burst_particle_count := 6               ## Particles per drop burst
@export var drop_burst_particle_size := 0.06               ## World-unit edge length of each square particle
@export var drop_burst_duration := 0.8                    ## Seconds for particles to fade out
@export var drop_burst_spread := 0.8                      ## Max world-unit distance particles travel
@export var drop_burst_max_per_second := 6                ## Rate limit per board


# ── Palette resolver ─────────────────────────────────────────────────

func resolve(source: Palette) -> Color:
	match source:
		Palette.BG_1: return bg_shade_1
		Palette.BG_2: return bg_shade_2
		Palette.BG_3: return bg_shade_3
		Palette.BG_4: return bg_shade_4
		Palette.BG_5: return bg_shade_5
		Palette.BG_6: return bg_shade_6
		Palette.BG_7: return bg_shade_7
		Palette.GOLD_MAIN: return gold_main
		Palette.GOLD_FADED: return gold_faded
		Palette.ORANGE_MAIN: return orange_main
		Palette.ORANGE_FADED: return orange_faded
		Palette.RED_MAIN: return red_main
		Palette.RED_FADED: return red_faded
		Palette.VIOLET_MAIN: return violet_main
		Palette.VIOLET_FADED: return violet_faded
		Palette.BLUE_MAIN: return blue_main
		Palette.BLUE_FADED: return blue_faded
		Palette.GREEN_MAIN: return green_main
		Palette.GREEN_FADED: return green_faded
		_: return bg_shade_6


# ── Derived colors (resolved from palette assignments) ───────────────

var background_color: Color:
	get: return resolve(background_source)
var ambient_light_color: Color:
	get: return resolve(ambient_light_source)
var directional_light_color: Color:
	get: return resolve(directional_light_source)
var peg_color: Color:
	get: return resolve(peg_color_source)
var high_multiplier_color: Color:
	get: return resolve(high_multiplier_source)
var hit_bucket_color: Color:
	get: return resolve(hit_bucket_source)
var normal_text_color: Color:
	get: return resolve(normal_text_source)
var body_text_color: Color:
	get: return resolve(body_text_source)
var at_cap_text_color: Color:
	get: return resolve(at_cap_text_source)
var overlay_color: Color:
	get:
		var c := resolve(overlay_source)
		return Color(c.r, c.g, c.b, overlay_opacity)
var button_enabled_color: Color:
	get: return resolve(button_enabled_source)
var button_disabled_color: Color:
	get: return resolve(button_disabled_source)
var button_hovered_color: Color:
	get: return resolve(button_hovered_source)
var button_text_color: Color:
	get: return resolve(button_text_source)
var button_bg_color: Color:
	get: return resolve(button_bg_source)
var button_fill_text_color: Color:
	get: return resolve(button_fill_text_source)
var button_disabled_text_color: Color:
	get: return resolve(button_disabled_text_source)
var button_border_color: Color:
	get: return resolve(button_border_source)


# ── Button style helpers ─────────────────────────────────────────────

func _make_stylebox(bg_color: Color, border_col: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg_color
	s.corner_radius_top_left = button_border_radius
	s.corner_radius_top_right = button_border_radius
	s.corner_radius_bottom_left = button_border_radius
	s.corner_radius_bottom_right = button_border_radius
	s.content_margin_left = button_padding.x
	s.content_margin_right = button_padding.x
	s.content_margin_top = button_padding.y
	s.content_margin_bottom = button_padding.y
	if button_border_width > 0:
		s.border_width_left = button_border_width
		s.border_width_right = button_border_width
		s.border_width_top = button_border_width
		s.border_width_bottom = button_border_width
		s.border_color = border_col if border_col.a > 0 else button_border_color
	return s


func apply_button_theme(button: Button, currency_type: int = -1) -> void:
	var enabled_col := get_coin_color(currency_type) if currency_type >= 0 else button_enabled_color
	var hovered_col := get_coin_color(currency_type).lightened(0.2) if currency_type >= 0 else button_hovered_color
	var disabled_col := get_coin_color_faded(currency_type) if currency_type >= 0 else button_disabled_color
	var border_col := get_coin_color(currency_type) if currency_type >= 0 else button_border_color
	button.add_theme_stylebox_override("normal", _make_stylebox(enabled_col, border_col))
	button.add_theme_stylebox_override("hover", _make_stylebox(hovered_col, border_col))
	# Pressed: solid flash matching normal text color for clear click feedback.
	button.add_theme_stylebox_override("pressed", _make_stylebox(normal_text_color, normal_text_color))
	button.add_theme_stylebox_override("disabled", _make_stylebox(disabled_col, border_col.darkened(0.3)))
	button.add_theme_font_size_override("font_size", button_font_size)
	var text_col := bg_shade_6 if currency_type >= 0 else button_text_color
	button.add_theme_color_override("font_color", text_col)
	button.add_theme_color_override("font_hover_color", text_col)
	button.add_theme_color_override("font_pressed_color", text_col)
	button.add_theme_color_override("font_disabled_color", text_col.darkened(0.4))
	var font: Font = button_font if button_font else label_font
	if font:
		button.add_theme_font_override("font", font)


# ── Color helpers ────────────────────────────────────────────────────

func get_coin_color(currency_type: int) -> Color:
	match currency_type:
		GOLD_COIN: return gold_main
		RAW_ORANGE, ORANGE_COIN: return orange_main
		RAW_RED, RED_COIN: return red_main
		RAW_VIOLET, VIOLET_COIN: return violet_main
		RAW_BLUE, BLUE_COIN: return blue_main
		RAW_GREEN, GREEN_COIN: return green_main
		_: return gold_main


func get_coin_color_faded(currency_type: int) -> Color:
	match currency_type:
		GOLD_COIN: return gold_faded
		RAW_ORANGE, ORANGE_COIN: return orange_faded
		RAW_RED, RED_COIN: return red_faded
		RAW_VIOLET, VIOLET_COIN: return violet_faded
		RAW_BLUE, BLUE_COIN: return blue_faded
		RAW_GREEN, GREEN_COIN: return green_faded
		_: return gold_faded


func get_bucket_color(currency_type: int) -> Color:
	return get_coin_color(currency_type)


# ── Material / mesh factories ────────────────────────────────────────

func make_coin_material(currency_type: int) -> ShaderMaterial:
	var coin_shader: Shader = preload("res://entities/coin/coin_clip.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = coin_shader
	var color: Color = coin_silhouette_color if coin_silhouette else get_coin_color(currency_type)
	mat.set_shader_parameter("albedo_color", color)
	return mat


func make_peg_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = peg_color
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mat.roughness = peg_roughness
		mat.metallic = peg_metallic
	return mat


func make_bucket_material(currency_type: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = get_bucket_color(currency_type)
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mat.roughness = bucket_roughness
		mat.metallic = bucket_metallic
	return mat


func make_peg_mesh() -> Mesh:
	match peg_shape:
		PegShape.SPHERE:
			var m := SphereMesh.new()
			m.radius = peg_radius
			m.height = peg_radius * 2
			return m
		PegShape.CYLINDER:
			var m := CylinderMesh.new()
			m.top_radius = peg_radius
			m.bottom_radius = peg_radius
			m.height = peg_height
			return m
		_:
			return SphereMesh.new()


func make_peg_shader_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://entities/peg/peg_multimesh.gdshader")
	return mat


func make_coin_mesh() -> Mesh:
	match coin_shape:
		CoinShape.SPHERE:
			var m := SphereMesh.new()
			m.radius = coin_radius
			m.height = coin_radius * 2
			return m
		CoinShape.CYLINDER:
			var m := CylinderMesh.new()
			m.top_radius = coin_radius
			m.bottom_radius = coin_radius
			m.height = coin_height
			return m
		_:
			return SphereMesh.new()


func make_bucket_mesh() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(bucket_width, bucket_height, bucket_depth)
	return m


func pulse_control(control: Control, scale_override: float = 0.0) -> void:
	var s: float = scale_override if scale_override > 0.0 else button_pulse_scale
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE * s, button_pulse_duration * 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(control, "scale", Vector2.ONE, button_pulse_duration * 0.6) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)


## Starts a looping blink on a Control by oscillating modulate.a.
## Returns the Tween so the caller can kill() it to stop blinking.
func blink_control(control: Control) -> Tween:
	var tween := control.create_tween().set_loops()
	var half := attention_blink_duration / 2.0
	tween.tween_property(control, "modulate:a", 0.3, half) \
		.set_trans(Tween.TRANS_SINE)
	tween.tween_property(control, "modulate:a", 1.0, half) \
		.set_trans(Tween.TRANS_SINE)
	return tween


## Starts a looping blink combining scale (up to max_scale) and fade (down to min_alpha).
## Returns the Tween so the caller can kill() it to stop.
func blink_scale_fade(control: Control, max_scale: float = 1.5, min_alpha: float = 0.75) -> Tween:
	control.pivot_offset = control.size / 2.0
	var half := attention_blink_duration / 2.0
	var tween := control.create_tween().set_loops()
	# Phase 1: scale up + fade out (parallel)
	tween.tween_property(control, "scale", Vector2.ONE * max_scale, half) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(control, "modulate:a", min_alpha, half) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	# Phase 2: scale down + fade in (parallel)
	tween.tween_property(control, "scale", Vector2.ONE, half) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(control, "modulate:a", 1.0, half) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	return tween


func pulse_node3d(node: Node3D, flash_white: bool = false,
		material: StandardMaterial3D = null,
		currency: Enums.CurrencyType = Enums.CurrencyType.GOLD_COIN,
		is_hit: bool = false) -> void:
	# Scale pop
	var scale_tween := node.create_tween()
	var target_scale := Vector3.ONE * bucket_pulse_scale
	scale_tween.tween_property(node, "scale", target_scale, bucket_pulse_duration * 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	scale_tween.tween_property(node, "scale", Vector3.ONE, bucket_pulse_duration * 0.6) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)

	# Color flash
	if flash_white and material:
		var flash_color := get_coin_color(currency).lightened(0.3)
		material.albedo_color = flash_color
		var rest_color: Color = hit_bucket_color if is_hit else get_bucket_color(currency)
		var color_tween := node.create_tween()
		color_tween.tween_property(material, "albedo_color", rest_color, bucket_pulse_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
