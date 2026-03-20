extends Node3D

@onready var challenge_one: Button = $CanvasLayer/HBoxContainer/Challenge1
@onready var challenge_two: Button = $CanvasLayer/HBoxContainer/Challenge2
@onready var challenge_three: Button = $CanvasLayer/HBoxContainer/Challenge3
@onready var challenge_four: Button = $CanvasLayer/HBoxContainer/Challenge4
@onready var challenge_five: Button = $CanvasLayer/HBoxContainer/Challenge5

const MainScene := preload("res://entities/main/main.tscn")

func _ready() -> void:
	# play_button.pressed.connect(_on_play_pressed)
	challenge_one.pressed.connect(_on_challenge_one_pressed)

func _on_challenge_one_pressed() -> void:
	# "Gold Rush" — earn 50 gold in 60 seconds, no upgrades allowed
	var challenge := ChallengeData.new()
	challenge.id = "gold_rush"
	challenge.display_name = "Gold Rush"
	challenge.time_limit_seconds = 60.0

	var goal := ChallengeObjective.CoinGoal.new()
	goal.currency_type = Enums.CurrencyType.GOLD_COIN
	goal.amount = 50
	challenge.objectives.append(goal)

	var no_upgrades := ChallengeConstraint.UpgradesLimited.new()
	no_upgrades.all_upgrades = true
	challenge.constraints.append(no_upgrades)

	ChallengeManager.set_challenge(challenge)
	SceneManager.set_new_scene(MainScene)
