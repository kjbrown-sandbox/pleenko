class_name ChallengeInfoPanel
extends CanvasLayer

var _name_label: Label
var _difficulty_container: HBoxContainer
var _objective_label: Label
var _time_limit_label: Label
var _restrictions_label: Label
var _rewards_label: Label


func _ready() -> void:
	var t: VisualTheme = ThemeProvider.theme
	var margin := t.hud_margin

	var margin_container := MarginContainer.new()
	margin_container.anchor_bottom = 1.0
	margin_container.offset_right = 300
	margin_container.add_theme_constant_override("margin_left", margin)
	margin_container.add_theme_constant_override("margin_top", margin)
	margin_container.add_theme_constant_override("margin_bottom", margin)
	add_child(margin_container)

	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	margin_container.add_child(vbox)

	# Challenge name
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 28)
	_name_label.add_theme_color_override("font_color", t.normal_text_color)
	_apply_font(_name_label, t)
	vbox.add_child(_name_label)

	# Difficulty tabs (display only for now)
	_difficulty_container = HBoxContainer.new()
	_difficulty_container.add_theme_constant_override("separation", 4)
	for diff_name in ["EASY", "MED", "HARD"]:
		var tab := Label.new()
		tab.text = diff_name
		tab.add_theme_font_size_override("font_size", int(t.button_font_size))
		tab.add_theme_color_override("font_color", t.button_disabled_text_color)
		_apply_font(tab, t)
		_difficulty_container.add_child(tab)
	vbox.add_child(_difficulty_container)

	vbox.add_child(_make_separator(t))

	# Objective
	vbox.add_child(_make_section_header("Objective", t))
	_objective_label = _make_body_label(t)
	vbox.add_child(_objective_label)

	vbox.add_child(_make_separator(t))

	# Time limit
	vbox.add_child(_make_section_header("Time limit", t))
	_time_limit_label = _make_body_label(t)
	vbox.add_child(_time_limit_label)

	vbox.add_child(_make_separator(t))

	# Restrictions
	vbox.add_child(_make_section_header("Restrictions", t))
	_restrictions_label = _make_body_label(t)
	vbox.add_child(_restrictions_label)

	vbox.add_child(_make_separator(t))

	# Rewards
	vbox.add_child(_make_section_header("Rewards", t))
	_rewards_label = _make_body_label(t)
	vbox.add_child(_rewards_label)


func show_challenge(data: ChallengeData) -> void:
	if not data:
		return
	_name_label.text = data.display_name

	_objective_label.text = ChallengeManager.get_objective_text_for(data)

	var mins := int(data.time_limit_seconds) / 60
	var secs := int(data.time_limit_seconds) % 60
	_time_limit_label.text = "%d:%02d" % [mins, secs]

	_restrictions_label.text = ChallengeManager.get_constraint_text(data)

	if data.rewards.is_empty():
		_rewards_label.text = "None"
	else:
		var parts: PackedStringArray = []
		for reward in data.rewards:
			if reward.description != "":
				parts.append("- %s" % reward.description)
			else:
				parts.append("- Reward")
		_rewards_label.text = "\n".join(parts)


func show_default(buttons: Array[ChallengeButton]) -> void:
	var btn := ChallengeProgressManager.get_earliest_incomplete(buttons)
	if btn and btn.challenge:
		show_challenge(btn.challenge)


func _make_section_header(text: String, t: VisualTheme) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", int(t.button_font_size))
	label.add_theme_color_override("font_color", t.body_text_color)
	_apply_font(label, t)
	return label


func _make_body_label(t: VisualTheme) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", int(t.button_font_size))
	label.add_theme_color_override("font_color", t.normal_text_color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_apply_font(label, t)
	return label


func _make_separator(t: VisualTheme) -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	(sep.get_theme_stylebox("separator") as StyleBoxLine).color = t.resolve(VisualTheme.Palette.BG_3)
	return sep


func _apply_font(label: Label, t: VisualTheme) -> void:
	var font: Font = t.button_font if t.button_font else t.label_font
	if font:
		label.add_theme_font_override("font", font)
