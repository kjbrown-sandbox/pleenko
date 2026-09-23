class_name TierData
extends Resource

@export var board_type: Enums.BoardType
@export var display_name: String

@export_group("Currencies")
@export var primary_currency: Enums.CurrencyType

@export_group("Economy")
## Cost in the previous tier's primary currency per drop.
@export var previous_currency_cost: int = 100
## Starting cap for the primary currency.
@export var primary_cap: int = 500

