extends Node3D

const MainScene := preload("res://entities/main/main.tscn")
const ChallengesMenuScene := preload("res://entities/challenges_menu/challenges_menu.tscn")

@onready var play_button: Button = $CanvasLayer/HBoxContainer/PlayButton
@onready var challenges_button: Button = $CanvasLayer/HBoxContainer/ChallengesButton

func _ready() -> void:
	_setup_environment()
	var t: VisualTheme = ThemeProvider.theme
	t.apply_button_theme(play_button)
	t.apply_button_theme(challenges_button)
	play_button.pressed.connect(_on_play_pressed)
	challenges_button.pressed.connect(_on_challenges_pressed)
	print("Main menu ready")

func _setup_environment() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = t.background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = t.ambient_light_color
	env.ambient_light_energy = t.ambient_light_energy
	var env_node := WorldEnvironment.new()
	env_node.environment = env
	add_child(env_node)


func _on_play_pressed() -> void:
	SceneManager.set_new_scene(MainScene)

func _on_challenges_pressed() -> void:
	SceneManager.set_new_scene(ChallengesMenuScene)
