extends "res://test/test_base.gd"

## VisualTheme.resolve() palette lookup — run with:
##   godot --headless --scene res://test/test_visual_theme_palette.tscn
##
## Covers the BG_TRIANGLE_LIGHT slot, which the gameplay parallax backdrop
## uses as its triangle light endpoint. Lives on its own slot so dark themes
## (glow_dark) can keep BG_6 light for text contrast while still producing
## cloud-soft triangles close to their own background.


func _run_tests() -> void:
	print("\n=== VisualTheme Palette Tests ===\n")
	test_bg_triangle_light_resolves_to_export()
	test_bg_triangle_light_default_matches_nier_zen_tone()
	test_glow_dark_overrides_bg_triangle_light_dark()
	test_nier_zen_uses_default_bg_triangle_light()


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
