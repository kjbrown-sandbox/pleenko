extends Control

## Full-screen prestige reward scene. Shown after the cinematic prestige animation.
## Displays "Prestige Up!", the rewards earned, and a claim button that resets the game.

var _board_type: Enums.BoardType


func _ready() -> void:
	Engine.time_scale = 1.0
	_board_type = PrestigeManager.pending_board_type
	var t: VisualTheme = ThemeProvider.theme

	# Background matches the color the coin expanded into
	var flash_color: Color = t.resolve(t.prestige_flash_source)
	# Contrast color: if flash is dark (BG_7), text should be light (BG_6) and vice versa
	var contrast_source: VisualTheme.Palette = VisualTheme.Palette.BG_6 if t.prestige_flash_source == VisualTheme.Palette.BG_7 else VisualTheme.Palette.BG_7
	var contrast_color: Color = t.resolve(contrast_source)
	var bg := ColorRect.new()
	bg.color = flash_color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Centered content
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	# "Plinko Up!" title
	var title := Label.new()
	title.text = "Plinko Up!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", contrast_color)
	if t.label_font:
		title.add_theme_font_override("font", t.label_font)
	title.modulate.a = 0.0
	vbox.add_child(title)

	# Rewards description
	var rewards_text := _build_rewards_text()
	var rewards_label := Label.new()
	rewards_label.text = rewards_text
	rewards_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rewards_label.add_theme_font_size_override("font_size", 22)
	rewards_label.add_theme_color_override("font_color", contrast_color)
	if t.label_font:
		rewards_label.add_theme_font_override("font", t.label_font)
	rewards_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rewards_label.modulate.a = 0.0
	vbox.add_child(rewards_label)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	# Claim button — override theme colors for stark contrast against flash background
	var claim_button := Button.new()
	claim_button.text = "Claim Rewards"
	claim_button.focus_mode = Control.FOCUS_NONE
	t.apply_button_theme(claim_button)
	claim_button.add_theme_font_size_override("font_size", 28)
	claim_button.add_theme_color_override("font_color", flash_color)
	claim_button.add_theme_color_override("font_hover_color", flash_color)
	claim_button.add_theme_color_override("font_pressed_color", flash_color)
	var btn_style := t._make_stylebox(contrast_color, contrast_color)
	claim_button.add_theme_stylebox_override("normal", btn_style)
	claim_button.add_theme_stylebox_override("hover", btn_style)
	claim_button.add_theme_stylebox_override("pressed", btn_style)
	claim_button.pressed.connect(_on_claim_pressed)
	claim_button.modulate.a = 0.0
	vbox.add_child(claim_button)

	# Staggered fade-in: title first, then rewards, then button
	var tween := create_tween()
	tween.tween_property(title, "modulate:a", 1.0, 0.5)
	tween.tween_interval(1.0)
	tween.tween_property(rewards_label, "modulate:a", 1.0, 0.5)
	tween.tween_interval(1.0)
	tween.tween_property(claim_button, "modulate:a", 1.0, 0.5)


func _build_rewards_text() -> String:
	var tier := TierRegistry.get_tier(_board_type)
	var board_name: String = tier.display_name if tier else "Unknown"

	# Multi-drop bonus applies to all tiers below this one
	var idx := TierRegistry.get_tier_index(_board_type)
	var lower_names: Array[String] = []
	for i in range(0, idx):
		lower_names.append(TierRegistry.get_tier_by_index(i).display_name.to_lower())
	var multi_drop_target: String = " and ".join(lower_names) if lower_names.size() > 0 else "lower"

	return "+1 multi-drop for the %s board\nAccess to the %s board" % [multi_drop_target, board_name]


func _on_claim_pressed() -> void:
	PrestigeManager.claim_prestige(_board_type)
	PrestigeManager.reset_time_scale()
	# Can't use SaveManager.reset_game() because it reloads the current scene
	# (which is PrestigeScreen, not Main). Instead, do the reset manually
	# and transition back to Main via SceneManager.
	SaveManager.reset_game_without_reload()
	SceneManager.set_new_scene(load("res://entities/main/main.tscn"), true)
