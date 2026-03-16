extends Node3D

const MainScene := preload("res://entities/main/main.tscn")

@onready var play_button: Button = $CanvasLayer/HBoxContainer/PlayButton

func _ready() -> void:
   play_button.pressed.connect(_on_play_pressed)

func _on_play_pressed() -> void:
   SceneManager.set_new_scene(MainScene)
