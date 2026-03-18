extends Node3D

const MainScene := preload("res://entities/main/main.tscn")
const ChallengesMenuScene := preload("res://entities/challenges_menu/challenges_menu.tscn")

@onready var play_button: Button = $CanvasLayer/HBoxContainer/PlayButton
@onready var challenges_button: Button = $CanvasLayer/HBoxContainer/ChallengesButton

func _ready() -> void:
   play_button.pressed.connect(_on_play_pressed)
   challenges_button.pressed.connect(_on_challenges_pressed)

func _on_play_pressed() -> void:
   SceneManager.set_new_scene(MainScene)

func _on_challenges_pressed() -> void:
   SceneManager.set_new_scene(ChallengesMenuScene)
