class_name TierData
extends Resource

@export var board_type: Enums.BoardType
@export var display_name: String

@export_group("Currencies")
@export var primary_currency: Enums.CurrencyType
## Set to -1 for gold (no raw currency).
@export var raw_currency: int = -1

@export_group("Economy")
## Cost in previous tier's raw currency (or primary if no raw exists) per drop.
@export var previous_currency_cost: int = 100
## Starting cap for the primary currency.
@export var primary_cap: int = 500
## Starting cap for the raw currency (0 if none).
@export var raw_cap: int = 100

@export_group("Colors")
@export var color_dark: Color
@export var color_normal: Color
@export var color_light: Color
