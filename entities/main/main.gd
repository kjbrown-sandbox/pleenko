extends Node3D

@onready var board_manager: BoardManager = $BoardManager
@onready var camera: Camera3D = $Camera3D
@onready var coin_values = $CanvasLayer/CoinValues


func _ready() -> void:
	board_manager.setup(camera)
	coin_values.setup(board_manager)
	SaveManager.setup(board_manager)

	# Load existing save if one exists
	if SaveManager.has_save():
		SaveManager.load_game()
		coin_values.refresh_visible_currencies()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("quicksave"):
		SaveManager.save_game()
	elif event.is_action_pressed("reset_game"):
		SaveManager.reset_game()