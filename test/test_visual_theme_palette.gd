extends "res://test/test_base.gd"

## VisualTheme.resolve() palette lookup — run with:
##   godot --headless --scene res://test/test_visual_theme_palette.tscn
##
## Covers the BG_TRIANGLE_LIGHT slot, which the gameplay parallax backdrop
## uses as its triangle light endpoint. Lives on its own slot so dark themes
## (glow_dark) can keep BG_6 light for text contrast while still producing
## cloud-soft triangles close to their own background.


## Preset list kept hand-maintained — adding a new preset means adding a test
## case here too. Cheap insurance against forgetting the peg=baseline invariant.
const PRESET_PATHS := [
	"res://style_lab/presets/cool_slate.tres",
	"res://style_lab/presets/cosmic_burst.tres",
	"res://style_lab/presets/glow_dark.tres",
	"res://style_lab/presets/lavender_lofi.tres",
	"res://style_lab/presets/lavender_lofi_dark.tres",
	"res://style_lab/presets/nier_burnt_parchment.tres",
	"res://style_lab/presets/nier_lofi.tres",
	"res://style_lab/presets/nier_parchment.tres",
	"res://style_lab/presets/nier_zen.tres",
	"res://style_lab/presets/warm_dark_halo.tres",
	"res://style_lab/presets/warm_minimal.tres",
]


func _run_tests() -> void:
	print("\n=== VisualTheme Palette Tests ===\n")
	test_bg_triangle_light_resolves_to_export()
	test_bg_triangle_light_default_matches_nier_zen_tone()
	test_glow_dark_overrides_bg_triangle_light_dark()
	test_nier_zen_uses_default_bg_triangle_light()
	test_peg_color_matches_normal_text_across_presets()
	test_cosmic_burst_preset_loads()


func test_bg_triangle_light_resolves_to_export() -> void:
	print("test_bg_triangle_light_resolves_to_export")
	var t := VisualTheme.new()
	t.bg_triangle_light = Color(0.42, 0.13, 0.77, 1)
	var c: Color = t.resolve(VisualTheme.Palette.BG_TRIANGLE_LIGHT)
	assert_equal(c, Color(0.42, 0.13, 0.77, 1),
		"BG_TRIANGLE_LIGHT resolves to bg_triangle_light export")


func test_bg_triangle_light_default_matches_nier_zen_tone() -> void:
	print("test_bg_triangle_light_default_matches_nier_zen_tone")
	# Schema default deliberately matches the original light endpoint (nier_zen's
	# bg_shade_6) so themes that don't override get the pre-change look.
	var t := VisualTheme.new()
	var c: Color = t.resolve(VisualTheme.Palette.BG_TRIANGLE_LIGHT)
	assert_equal(c, Color(0.86, 0.83, 0.77),
		"default bg_triangle_light matches nier_zen bg_shade_6 tone")


func test_glow_dark_overrides_bg_triangle_light_dark() -> void:
	print("test_glow_dark_overrides_bg_triangle_light_dark")
	var t: VisualTheme = preload("res://style_lab/presets/glow_dark.tres")
	var c: Color = t.resolve(VisualTheme.Palette.BG_TRIANGLE_LIGHT)
	# Must be substantially darker than BG_6 (the old default) so triangles
	# don't blow out on glow_dark's near-black background.
	assert_true(c.r < 0.2 and c.g < 0.2 and c.b < 0.2,
		"glow_dark bg_triangle_light is dark (rgb each < 0.2), got %s" % c)


func test_nier_zen_uses_default_bg_triangle_light() -> void:
	print("test_nier_zen_uses_default_bg_triangle_light")
	# nier_zen doesn't override the slot — must inherit the schema default
	# (matching its bg_shade_6 so the parallax lerp range is unchanged).
	var t: VisualTheme = preload("res://style_lab/presets/nier_zen.tres")
	var c: Color = t.resolve(VisualTheme.Palette.BG_TRIANGLE_LIGHT)
	assert_equal(c, Color(0.86, 0.83, 0.77),
		"nier_zen BG_TRIANGLE_LIGHT == its bg_shade_6 tone")


## The "stark contrast" pattern: pegs share the baseline-button bar shade in
## every preset. `RefinedBaselineButton._bar_tint()` resolves to
## `normal_text_color`, and the convention is `peg_color_source ==
## normal_text_source` so the two visuals can't drift apart on a theme swap.
func test_peg_color_matches_normal_text_across_presets() -> void:
	print("test_peg_color_matches_normal_text_across_presets")
	for path in PRESET_PATHS:
		var t: VisualTheme = load(path)
		assert_equal(t.peg_color, t.normal_text_color,
			"%s: peg_color must match normal_text_color (got peg=%s text=%s)" % [path, t.peg_color, t.normal_text_color])


func test_cosmic_burst_preset_loads() -> void:
	print("test_cosmic_burst_preset_loads")
	# Cherry-picked from prototype/earrings — guard against UID/schema drift
	# silently breaking the load.
	var t: VisualTheme = load("res://style_lab/presets/cosmic_burst.tres")
	assert_true(t != null, "cosmic_burst.tres loads")
	# Dark theme: background is the darkest shade, text resolves to the
	# lightest. Cosmic deliberately doesn't override either source, so this
	# also guards the schema defaults.
	assert_true(t.background_color.get_luminance() < 0.3,
		"cosmic_burst background is dark (luminance < 0.3), got %.3f" % t.background_color.get_luminance())
	assert_true(t.normal_text_color.get_luminance() > 0.5,
		"cosmic_burst normal_text is light (luminance > 0.5), got %.3f" % t.normal_text_color.get_luminance())
