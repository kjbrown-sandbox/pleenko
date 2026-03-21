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

# ── Background / Environment ─────────────────────────────────────────
@export_group("Environment")
@export var background_color := Color(0.96, 0.95, 0.92)          # warm off-white
@export var unshaded := true                                      # flat color, no lighting
@export var ambient_light_color := Color(0.95, 0.93, 0.88)
@export var ambient_light_energy := 0.4
@export var directional_light_color := Color(1.0, 0.98, 0.94)
@export var directional_light_energy := 0.8
@export var directional_light_angle := Vector3(-35, -20, 0)      # euler degrees

# ── Pegs ─────────────────────────────────────────────────────────────
@export_group("Pegs")
enum PegShape { SPHERE, CYLINDER }
@export var peg_shape: PegShape = PegShape.SPHERE
@export var peg_radius := 0.08
@export var peg_height := 0.05                                    # cylinder only
@export var peg_color := Color(0.75, 0.73, 0.70)                 # subtle but visible
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
@export var bucket_label_offset := -0.15                          # vertical distance below bucket

# ── Text ─────────────────────────────────────────────────────────────
@export_group("Text")
@export var label_font: Font
@export var label_outline_size := 0                               # 0 = no outline
@export var floating_text_font_size := 40
@export var multi_drop_font_size := 48
@export var high_multiplier_color := Color(1.0, 0.3, 0.3, 1.0)   # red tint for big multipliers
@export var normal_text_color := Color(1.0, 1.0, 1.0, 1.0)
@export var at_cap_text_color := Color(1.0, 0.15, 0.15, 1.0)     # warning when currency is capped

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

# ── Accent Colors (the sharp contrast colors) ───────────────────────
@export_group("Accent Colors")
@export var gold_color := Color(0.85, 0.75, 0.25)                # dusty gold
@export var orange_color := Color(0.85, 0.45, 0.3)               # muted coral
@export var red_color := Color(0.7, 0.2, 0.25)                   # deep maroon

# Bucket colors default to the same as coin colors but can be overridden
@export var bucket_gold_color := Color(0.85, 0.75, 0.25)
@export var bucket_orange_color := Color(0.85, 0.45, 0.3)
@export var bucket_red_color := Color(0.7, 0.2, 0.25)

# ── Spacing / Layout ────────────────────────────────────────────────
@export_group("Spacing")
@export var space_between_pegs := 1.0
@export var board_rows := 6                                       # demo row count

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


# ── Helpers ──────────────────────────────────────────────────────────

func get_coin_color(currency_type: int) -> Color:
	match currency_type:
		GOLD_COIN:
			return gold_color
		RAW_ORANGE, ORANGE_COIN:
			return orange_color
		RAW_RED, RED_COIN:
			return red_color
		_:
			return gold_color


func get_bucket_color(currency_type: int) -> Color:
	match currency_type:
		GOLD_COIN:
			return bucket_gold_color
		RAW_ORANGE, ORANGE_COIN:
			return bucket_orange_color
		RAW_RED, RED_COIN:
			return bucket_red_color
		_:
			return bucket_gold_color


func make_coin_material(currency_type: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = get_coin_color(currency_type)
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mat.roughness = coin_roughness
		mat.metallic = coin_metallic
		if coin_emission_strength > 0:
			mat.emission_enabled = true
			mat.emission = get_coin_color(currency_type)
			mat.emission_energy_multiplier = coin_emission_strength
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
