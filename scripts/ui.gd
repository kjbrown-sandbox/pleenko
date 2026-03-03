extends CanvasLayer

@onready var coin_label: Label = $CoinLabel


func update_coins(total: int) -> void:
	coin_label.text = "Coins: " + str(total)
