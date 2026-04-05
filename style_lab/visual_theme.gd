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

# ── Palette enum ─────────────────────────────────────────────────────
enum Palette {
	BG_1, BG_2, BG_3, BG_4, BG_5, BG_6,
	GOLD_DARK, GOLD_NORMAL, GOLD_LIGHT,
	ORANGE_DARK, ORANGE_NORMAL, ORANGE_LIGHT,
	RED_DARK, RED_NORMAL, RED_LIGHT,
	BG_7,
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

# Per-currency colors: dark, normal, light
@export_group("Colors – Gold")
@export var gold_dark := Color(0.55, 0.45, 0.10)
@export var gold_normal := Color(0.85, 0.75, 0.25)
@export var gold_light := Color(1.0, 0.94, 0.55)

@export_group("Colors – Orange")
@export var orange_dark := Color(0.55, 0.25, 0.12)
@export var orange_normal := Color(0.85, 0.45, 0.3)
@export var orange_light := Color(1.0, 0.7, 0.55)

@export_group("Colors – Red")
@export var red_dark := Color(0.4, 0.08, 0.1)
@export var red_normal := Color(0.7, 0.2, 0.25)
@export var red_light := Color(1.0, 0.45, 0.45)

# ── Color assignments (pick from palette via dropdown) ───────────────
@export_group("Color Assignments")
@export var background_source: Palette = Palette.BG_7
@export var ambient_light_source: Palette = Palette.BG_5
@export var directional_light_source: Palette = Palette.BG_6
@export var peg_color_source: Palette = Palette.BG_4
@export var high_multiplier_source: Palette = Palette.RED_LIGHT
@export var normal_text_source: Palette = Palette.BG_6
@export var body_text_source: Palette = Palette.BG_4
@export var at_cap_text_source: Palette = Palette.RED_LIGHT
@export var overlay_source: Palette = Palette.BG_7
@export var overlay_opacity := 0.6

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
enum CoinShape { SPHERE, CYLINDER }
@export var coin_shape: CoinShape = CoinShape.SPHERE
@export var coin_radius := 0.15
@export var coin_height := 0.05                                   # cylinder only
@export var coin_roughness := 0.3
@export var coin_metallic := 0.4
@export var coin_emission_strength := 0.15                        # subtle glow
@export var coin_fall_time := 0.4                                 # seconds per row bounce
@export var coin_bounce_height := 0.2                             # upward arc between rows

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
@export var bucket_pulse_scale := 1.08                            # scale on receive
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
		Palette.GOLD_DARK: return gold_dark
		Palette.GOLD_NORMAL: return gold_normal
		Palette.GOLD_LIGHT: return gold_light
		Palette.ORANGE_DARK: return orange_dark
		Palette.ORANGE_NORMAL: return orange_normal
		Palette.ORANGE_LIGHT: return orange_light
		Palette.RED_DARK: return red_dark
		Palette.RED_NORMAL: return red_normal
		Palette.RED_LIGHT: return red_light
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
	var hovered_col := get_coin_color_light(currency_type) if currency_type >= 0 else button_hovered_color
	var disabled_col := get_coin_color_dark(currency_type) if currency_type >= 0 else button_disabled_color
	var border_col := get_coin_color(currency_type) if currency_type >= 0 else button_border_color
	button.add_theme_stylebox_override("normal", _make_stylebox(enabled_col, border_col))
	button.add_theme_stylebox_override("hover", _make_stylebox(hovered_col, border_col))
	button.add_theme_stylebox_override("pressed", _make_stylebox(hovered_col, border_col))
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
		GOLD_COIN: return gold_normal
		RAW_ORANGE, ORANGE_COIN: return orange_normal
		RAW_RED, RED_COIN: return red_normal
		_: return gold_normal


func get_coin_color_light(currency_type: int) -> Color:
	match currency_type:
		GOLD_COIN: return gold_light
		RAW_ORANGE, ORANGE_COIN: return orange_light
		RAW_RED, RED_COIN: return red_light
		_: return gold_light


func get_coin_color_dark(currency_type: int) -> Color:
	match currency_type:
		GOLD_COIN: return gold_dark
		RAW_ORANGE, ORANGE_COIN: return orange_dark
		RAW_RED, RED_COIN: return red_dark
		_: return gold_dark


func get_bucket_color(currency_type: int) -> Color:
	return get_coin_color(currency_type)


# ── Material / mesh factories ────────────────────────────────────────

func make_coin_material(currency_type: int) -> ShaderMaterial:
	var coin_shader: Shader = preload("res://entities/coin/coin_clip.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = coin_shader
	mat.set_shader_parameter("albedo_color", get_coin_color(currency_type))
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
		var flash_color := get_coin_color_light(currency)
		material.albedo_color = flash_color
		var rest_color: Color = resolve(Palette.BG_6) if is_hit else get_bucket_color(currency)
		var color_tween := node.create_tween()
		color_tween.tween_property(material, "albedo_color", rest_color, bucket_pulse_duration) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
