class_name DropSection
extends Control

@onready var _queue_bonus_label: Label = $QueueBonusLabel


func _ready() -> void:
	if _queue_bonus_label:
		var t: VisualTheme = ThemeProvider.theme
		_queue_bonus_label.add_theme_color_override("font_color", t.normal_text_color)
		var btn_font: Font = t.button_font if t.button_font else preload("res://style_lab/VendSans-Bold.ttf")
		_queue_bonus_label.add_theme_font_override("font", btn_font)
		_queue_bonus_label.add_theme_font_size_override("font_size", maxi(t.button_font_size - 2, 10))


## Show "Queue bonus: Drop rate +X%" when full_count > 0; hide otherwise.
## bonus_per_coin is the additive rate fraction per FULL coin (e.g. 0.50 = +50%).
func set_queue_bonus(full_count: int, bonus_per_coin: float) -> void:
	if not _queue_bonus_label:
		return
	if full_count <= 0:
		_queue_bonus_label.visible = false
		return
	var pct: int = int(round(bonus_per_coin * float(full_count) * 100.0))
	_queue_bonus_label.text = "Queue bonus:\nDrop rate +%d%%" % pct
	_queue_bonus_label.visible = true


## Anchor the bonus label to a screen-space point (typically the projected
## spawn point of the active board). Caller is responsible for any offset.
func set_queue_bonus_position(viewport_pos: Vector2) -> void:
	if _queue_bonus_label:
		_queue_bonus_label.global_position = viewport_pos
