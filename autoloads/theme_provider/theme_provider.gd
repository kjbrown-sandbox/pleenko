extends Node

signal theme_changed

enum Kind { NORMAL, CHALLENGE }

const NORMAL_THEME: VisualTheme = preload("res://style_lab/presets/nier_parchment.tres")
const CHALLENGE_THEME: VisualTheme = preload("res://style_lab/presets/glow_dark.tres")

var theme: VisualTheme

var _world_environment: WorldEnvironment
var _directional_light: DirectionalLight3D


func _ready() -> void:
	_world_environment = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_world_environment.environment = env
	add_child(_world_environment)
	set_theme(Kind.NORMAL)


func set_theme(kind: Kind) -> void:
	var new_theme: VisualTheme
	match kind:
		Kind.NORMAL:
			new_theme = NORMAL_THEME
		Kind.CHALLENGE:
			new_theme = CHALLENGE_THEME
	if new_theme == theme:
		return
	theme = new_theme

	RenderingServer.set_default_clear_color(theme.background_color)

	var env := _world_environment.environment
	env.background_color = theme.background_color
	env.ambient_light_color = theme.ambient_light_color
	env.ambient_light_energy = theme.ambient_light_energy

	if theme.unshaded:
		if _directional_light:
			_directional_light.queue_free()
			_directional_light = null
	else:
		if not _directional_light:
			_directional_light = DirectionalLight3D.new()
			add_child(_directional_light)
		_directional_light.light_color = theme.directional_light_color
		_directional_light.light_energy = theme.directional_light_energy
		_directional_light.rotation_degrees = theme.directional_light_angle

	theme_changed.emit()
