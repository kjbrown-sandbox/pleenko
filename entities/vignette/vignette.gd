extends CanvasLayer

## Full-screen vignette overlay. Reads parameters from the active VisualTheme.

var _rect: ColorRect


func _ready() -> void:
	layer = 99
	var t: VisualTheme = ThemeProvider.theme
	if not t.vignette_enabled:
		queue_free()
		return

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://entities/vignette/vignette.gdshader")
	mat.set_shader_parameter("intensity", t.vignette_intensity)
	mat.set_shader_parameter("radius", t.vignette_radius)
	mat.set_shader_parameter("softness", t.vignette_softness)
	mat.set_shader_parameter("vignette_color", t.resolve(t.vignette_color_source))
	_rect.material = mat

	add_child(_rect)
