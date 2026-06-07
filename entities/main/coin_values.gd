extends VBoxContainer

const BarScene := preload("res://entities/refined_baseline_button/refined_baseline_button.tscn")
const UpgradeRowScene := preload("res://entities/upgrade_row/upgrade_row.tscn")
const TooltipScene := preload("res://entities/tooltip/tooltip.tscn")

var _bars: Dictionary = {}  # CurrencyType -> RefinedBaselineButton node
var _visible_currencies: Array[Enums.CurrencyType] = [Enums.CurrencyType.GOLD_COIN]
var _hover_tooltip: Tooltip

var _board_manager: BoardManager

# Autodropper upgrade rows shown in the HUD (keyed by UpgradeType)
var _upgrade_rows: Dictionary = {}  # UpgradeType -> UpgradeRow node
var _initial_setup_complete := false

# Cap-raise reveal cinematic (CapRaiseRevealAnimator): while active, cap "+"
# buttons for the reveal board are wired but kept hidden so the animator can
# reveal them one at a time. See begin/get_pending/end_cap_raise_reveal.
var _cap_raise_reveal_active := false
var _cap_raise_reveal_board: Enums.BoardType = Enums.BoardType.GOLD
# The raw-currency bar that appears mid-reveal (e.g. raw orange): created hidden
# during the reveal so the animator can fade it in after the currency cap
# explodes, instead of it popping in the instant the coin lands. -1 = none.
var _cap_raise_delayed_currency: int = -1

# Debounce: collapse multiple currency_changed signals into one deferred update
var _dirty := false
var _dirty_types: Array[Enums.CurrencyType] = []

func setup(board_manager: BoardManager) -> void:
	_board_manager = board_manager

	for currency_type in Enums.CurrencyType.values():
		if not _visible_currencies.has(currency_type) and _is_board_for_coin_type_unlocked(currency_type):
			_visible_currencies.append(currency_type)

	_visible_currencies.sort()
	_update_currencies()

	# A board unlock flips _currency_bars_revealed and adds the new board's
	# currency bar. The cap-beat coin earns the PREVIOUS board's currency, so the
	# currency-change path alone won't reveal the bars — rebuild on unlock.
	_board_manager.board_unlocked.connect(_on_board_unlocked)

	# Listen for autodropper unlocks to trigger layout rebuild
	UpgradeManager.upgrade_unlocked.connect(_on_upgrade_unlocked)
	# Defer so save loading finishes first — unlocks from save skip animation
	_mark_setup_complete.call_deferred()


func _mark_setup_complete() -> void:
	_initial_setup_complete = true

func _ready() -> void:
	CurrencyManager.currency_changed.connect(_on_currency_changed)
	UpgradeManager.cap_raise_unlocked.connect(_on_cap_raise_unlocked)
	_update_all_bars()


func _on_currency_changed(type: Enums.CurrencyType, _new_balance: int, _cap: int) -> void:
	if not _dirty_types.has(type):
		_dirty_types.append(type)
	if not _dirty:
		_dirty = true
		_flush.call_deferred()


func _flush() -> void:
	_dirty = false

	# Check if any new currencies need to become visible
	var layout_changed := false
	for type in _dirty_types:
		if not _visible_currencies.has(type) and _is_board_for_coin_type_unlocked(type):
			_visible_currencies.append(type)
			layout_changed = true

	if layout_changed:
		_visible_currencies.sort()
		_dirty_types.clear()
		_update_currencies()
		return

	# Update only the bars that changed
	for type in _dirty_types:
		var bar = _bars.get(type)
		if bar:
			var amount := CurrencyManager.get_balance(type)
			var cap := CurrencyManager.get_cap(type)
			_update_bar(bar, type, amount, cap)

	_dirty_types.clear()
	_update_cap_button_affordability()


## Currency bars stay hidden until the next board (orange) is actually unlocked —
## until then the level bar IS the currency display. After a prestige wipe the
## boards respawn during the climb-back (the 2nd-500 cap beat), so this naturally
## hides the bars again early in each climb and reveals them when orange returns.
func _currency_bars_revealed() -> bool:
	return is_instance_valid(_board_manager) and _board_manager.is_board_unlocked(Enums.BoardType.ORANGE)


func _is_board_for_coin_type_unlocked(coin_type: Enums.CurrencyType) -> bool:
	var tier := TierRegistry.get_tier_for_currency(coin_type)
	if not tier:
		return true
	# Starting tier currencies are always visible
	if TierRegistry.is_starting_tier(tier.board_type):
		return true
	# Raw currencies show up as soon as you have any (earned before board unlocks)
	if TierRegistry.is_raw_currency(coin_type) and CurrencyManager.get_balance(coin_type) > 0:
		return true
	# Otherwise, the tier's board must be unlocked
	return _board_manager.is_board_unlocked(tier.board_type)


func _update_currencies() -> void:
	for child in get_children():
		child.queue_free()
	_bars.clear()
	_hover_tooltip = null
	_upgrade_rows.clear()

	var t: VisualTheme = ThemeProvider.theme
	var has_upgrades: bool = _has_any_universal_upgrade()

	# Currency bars stay hidden until the player first completes the gold board
	# (the first prestige). Early play is driven by the level bar alone so the
	# objective reads clearly. The universal-upgrades section is independent
	# (autodropper unlocks at gold L5, before any prestige).
	if _currency_bars_revealed():
		add_child(_create_section_label("Currencies"))

		for currency_type in _visible_currencies:
			var bar = BarScene.instantiate()
			# Tint set before add_child so _ready's apply uses it for the initial render.
			bar.bar_color = t.get_coin_color(currency_type)
			add_child(bar)

			var fill_color: Color = t.get_coin_color(currency_type)
			var disabled_color: Color = t.get_coin_color_faded(currency_type)
			bar.setup(fill_color, disabled_color)

			var amount := CurrencyManager.get_balance(currency_type)
			var cap := CurrencyManager.get_cap(currency_type)
			_update_bar(bar, currency_type, amount, cap)

			# Main bar is not clickable
			bar.main_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

			bar.plus_pressed.connect(_on_cap_raise_pressed.bind(currency_type))
			bar.plus_mouse_entered.connect(_on_cap_hover.bind(currency_type))
			bar.plus_mouse_exited.connect(_on_cap_unhover)

			_bars[currency_type] = bar

			# During a reveal, the freshly-earned currency bar starts hidden —
			# CapRaiseRevealAnimator fades it in mid-sequence (reveal_delayed_currency_bar).
			if _cap_raise_reveal_active and currency_type == _cap_raise_delayed_currency:
				bar.visible = false

	# Universal upgrades section
	if has_upgrades:
		var spacer := Control.new()
		spacer.custom_minimum_size.y = ThemeProvider.theme.section_spacer_height
		add_child(spacer)

		add_child(_create_section_label("Universal upgrades"))

		_try_spawn_upgrade_row(Enums.UpgradeType.AUTODROPPER, Enums.BoardType.GOLD)
		_try_spawn_upgrade_row(Enums.UpgradeType.ADVANCED_AUTODROPPER, Enums.BoardType.ORANGE)
		_try_spawn_upgrade_row(Enums.UpgradeType.PEG_DEFLECTOR, Enums.BoardType.ORANGE)

	# Hover tooltip — must be last child so it renders below everything
	_hover_tooltip = TooltipScene.instantiate()
	_hover_tooltip.use_parent_signals = false
	_hover_tooltip.position_side = Tooltip.Placement.INLINE
	_hover_tooltip.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_hover_tooltip)

	_update_all_cap_buttons()


func _has_any_universal_upgrade() -> bool:
	return UpgradeManager.is_unlocked(Enums.BoardType.GOLD, Enums.UpgradeType.AUTODROPPER) \
		or UpgradeManager.is_unlocked(Enums.BoardType.ORANGE, Enums.UpgradeType.ADVANCED_AUTODROPPER) \
		or UpgradeManager.is_unlocked(Enums.BoardType.ORANGE, Enums.UpgradeType.PEG_DEFLECTOR)


func _try_spawn_upgrade_row(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType) -> void:
	if not UpgradeManager.is_unlocked(board_type, upgrade_type):
		return
	var row: UpgradeRow = UpgradeRowScene.instantiate()
	row.setup(board_type, upgrade_type, _buy_upgrade.bind(board_type, upgrade_type))
	_install_hover_extra_provider(row, upgrade_type)
	row.hover_info_changed.connect(_on_upgrade_hover_changed)
	add_child(row)
	if _hover_tooltip:
		move_child(_hover_tooltip, get_child_count() - 1)
	_upgrade_rows[upgrade_type] = row
	_setup_cap_raise_if_needed(row, board_type, upgrade_type)


func _setup_cap_raise_if_needed(row: UpgradeRow, board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> void:
	var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(board_type, upgrade_type)
	if state.base_cap <= 0 or not UpgradeManager.is_cap_raise_available(board_type):
		return
	if row.bar.plus_button.visible:
		return

	var bt := board_type
	var ut := upgrade_type
	var r := row

	row.setup_plus(
		func():
			UpgradeManager.buy_cap_raise(bt, ut),
		func() -> String:
			var state2: UpgradeManager.UpgradeState = UpgradeManager.get_state(bt, ut)
			var cap_cost: int = UpgradeManager.get_cap_raise_cost(bt, ut)
			var cap_currency: int = TierRegistry.cap_raise_currency(bt)
			var currency_name: String = FormatUtils.currency_name(cap_currency, false)
			return "Increase max level %d → %d\n\nCost: %d %s" % [
				state2.current_cap, state2.current_cap + 1, cap_cost, currency_name],
		func():
			var can_raise: bool = UpgradeManager.can_buy_cap_raise(bt, ut)
			r.bar.set_plus_disabled(not can_raise)
			r.bar.set_plus_filled(can_raise),
	)

	if _is_cap_reveal_suppressed(board_type):
		# Wired but hidden — CapRaiseRevealAnimator reveals it on its own clock.
		row.bar.show_plus_button(false)


## Inject the tooltip middle-block provider for upgrade types that need one.
## Autodropper rows list per-board assignments; deflector shows current odds.
func _install_hover_extra_provider(row: UpgradeRow, upgrade_type: Enums.UpgradeType) -> void:
	match upgrade_type:
		Enums.UpgradeType.AUTODROPPER:
			row.set_hover_extra_provider(_autodropper_assignment_text.bind(false))
		Enums.UpgradeType.ADVANCED_AUTODROPPER:
			row.set_hover_extra_provider(_autodropper_assignment_text.bind(true))
		Enums.UpgradeType.PEG_DEFLECTOR:
			row.set_hover_extra_provider(_deflector_odds_text)


## One line per unlocked board (including zeros) of how many autodroppers of this
## pool (normal/advanced) are assigned there.
func _autodropper_assignment_text(advanced: bool) -> String:
	if not is_instance_valid(_board_manager):
		return ""
	var key := "advanced" if advanced else "normal"
	var lines: PackedStringArray = []
	for bt in Enums.BoardType.values():
		if not _board_manager.is_board_unlocked(bt):
			continue
		var counts: Dictionary = _board_manager.get_assigned_counts_for_board(bt)
		lines.append("%d assigned to %s board" % [counts[key], FormatUtils.board_name(bt, false)])
	return "\n".join(lines)


func _deflector_odds_text() -> String:
	var odds := roundi(PlinkoBoard.deflector_bias_for_strength(
		PlinkoBoard.DEFLECTOR_BASE_STRENGTH) * 100.0)
	return "Current odds: %d%%" % odds


func _buy_upgrade(board_type: Enums.BoardType, upgrade_type: Enums.UpgradeType) -> void:
	UpgradeManager.buy(board_type, upgrade_type)


func _on_upgrade_hover_changed(text: String) -> void:
	if not _hover_tooltip:
		return
	if text == "":
		_hover_tooltip.hide_tooltip()
	else:
		_hover_tooltip.update_and_show(text)


func _on_upgrade_unlocked(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType) -> void:
	# Only care about autodropper-type upgrades
	if upgrade_type != Enums.UpgradeType.AUTODROPPER \
			and upgrade_type != Enums.UpgradeType.ADVANCED_AUTODROPPER \
			and upgrade_type != Enums.UpgradeType.PEG_DEFLECTOR:
		return
	if upgrade_type in _upgrade_rows:
		return
	if not _initial_setup_complete:
		# Loading from save — just rebuild without animation
		_update_currencies()
		return
	# First unlock during gameplay — animate the section in
	_animate_universal_section(upgrade_type, board_type)


## Returns the UpgradeRow for the given upgrade type, or null if not present.
## Used by LevelSection to target sparkle animations.
func get_upgrade_row(upgrade_type: Enums.UpgradeType) -> UpgradeRow:
	return _upgrade_rows.get(upgrade_type)


func _update_bar(bar, type: Enums.CurrencyType, balance: int, cap: int) -> void:
	var at_cap := cap > 0 and balance >= cap
	var coin_name := _get_currency_name(type)

	var fmt_balance := FormatUtils.format_number(balance)
	var fmt_cap := FormatUtils.format_number(cap)
	bar.update_text(coin_name)
	bar.num_text = "%s/%s" % [fmt_balance, fmt_cap]
	# Full bar reads as MAX visually — no "(MAX)" suffix needed.
	if at_cap:
		bar.set_fill(1.0)
	else:
		var fill_pct := clampf(float(balance) / float(cap), 0.0, 1.0) if cap > 0 else 0.0
		bar.set_fill(fill_pct)
	# Currencies don't toggle disabled visual — color is the identity.


func _get_currency_name(type: int) -> String:
	return FormatUtils.currency_name(type)


func _on_cap_hover(type: Enums.CurrencyType) -> void:
	if not _hover_tooltip:
		return
	var cost := CurrencyManager.get_cap_raise_cost(type)
	var cap_currency: int = CurrencyManager.cap_raise_currency(type)
	var currency_name := _get_currency_name(cap_currency)
	var cur_cap := CurrencyManager.get_cap(type)
	var new_cap := cur_cap + CurrencyManager.cap_raise_amount(type)
	_hover_tooltip.update_and_show("Increase max %s from %s → %s\n\nCost: %s %s" % [
		_get_currency_name(type), FormatUtils.format_number(cur_cap),
		FormatUtils.format_number(new_cap), FormatUtils.format_number(cost), currency_name])


func _on_cap_unhover() -> void:
	if _hover_tooltip:
		_hover_tooltip.hide_tooltip()


func _on_board_unlocked(_type: Enums.BoardType) -> void:
	refresh_visible_currencies()


func refresh_visible_currencies() -> void:
	var changed := false
	for currency_type in Enums.CurrencyType.values():
		if not _visible_currencies.has(currency_type) and _is_board_for_coin_type_unlocked(currency_type):
			_visible_currencies.append(currency_type)
			changed = true
	if changed:
		_visible_currencies.sort()
		_update_currencies()
	else:
		_update_all_bars()


func _on_cap_raise_unlocked(board_type: Enums.BoardType) -> void:
	_update_all_cap_buttons()
	# Check if any universal upgrade rows need their + button wired up
	for upgrade_type in _upgrade_rows:
		var row: UpgradeRow = _upgrade_rows[upgrade_type]
		var row_board: Enums.BoardType = _get_board_for_upgrade(upgrade_type)
		if row_board == board_type:
			_setup_cap_raise_if_needed(row, row_board, upgrade_type)


func _get_board_for_upgrade(upgrade_type: Enums.UpgradeType) -> Enums.BoardType:
	if upgrade_type == Enums.UpgradeType.ADVANCED_AUTODROPPER \
			or upgrade_type == Enums.UpgradeType.PEG_DEFLECTOR:
		return Enums.BoardType.ORANGE
	return Enums.BoardType.GOLD


# ── Cap-raise reveal handshake (called down by CapRaiseRevealAnimator) ────────
# While a reveal is active, cap "+" buttons for the reveal board are wired but
# kept hidden (the normal reveal paths self-suppress via _is_cap_reveal_suppressed).
# The animator pulls them via get_pending_cap_raise_targets() and reveals them one
# at a time; end_cap_raise_reveal() force-shows whatever is left so a button can
# never be stranded if the cinematic is interrupted.

func begin_cap_raise_reveal(board_type: Enums.BoardType) -> void:
	_cap_raise_reveal_active = true
	_cap_raise_reveal_board = board_type
	# Single-currency model: the bar delayed for mid-reveal fade-in is the newly
	# unlocked board's PRIMARY currency (e.g. orange). No-ops gracefully if that
	# bar hasn't been built yet (no orange earned at reveal time).
	var next_tier: TierData = TierRegistry.get_next_tier(board_type)
	_cap_raise_delayed_currency = next_tier.primary_currency if next_tier else -1


## Cap "+" buttons on the CURRENCY bars (top of the HUD) that are wired but
## still hidden. Each entry:
## { node: Control (for explosion position), plus_button: Control, reveal: Callable }.
func get_pending_currency_cap_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if not _cap_raise_reveal_active:
		return targets
	for currency_type in _bars:
		var bar = _bars[currency_type]
		if bar.plus_button.visible:
			continue
		var board: int = CurrencyManager.cap_raise_board(currency_type)
		if board != _cap_raise_reveal_board or not UpgradeManager.is_cap_raise_available(board):
			continue
		var captured_bar = bar
		var captured_currency: Enums.CurrencyType = currency_type
		targets.append({
			"node": bar,
			"plus_button": bar.plus_button,
			"reveal": func() -> void: _reveal_currency_cap_button(captured_bar, captured_currency),
		})
	return targets


## Cap "+" buttons on the UNIVERSAL upgrade rows that are wired but still hidden.
## Same entry shape as get_pending_currency_cap_targets().
func get_pending_universal_cap_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if not _cap_raise_reveal_active:
		return targets
	for upgrade_type in _upgrade_rows:
		var row: UpgradeRow = _upgrade_rows[upgrade_type]
		if _get_board_for_upgrade(upgrade_type) != _cap_raise_reveal_board:
			continue
		if row.bar.plus_button.visible:
			continue
		var state: UpgradeManager.UpgradeState = UpgradeManager.get_state(_cap_raise_reveal_board, upgrade_type)
		if state.base_cap <= 0 or not UpgradeManager.is_cap_raise_available(_cap_raise_reveal_board):
			continue
		var captured_row := row
		targets.append({
			"node": row,
			"plus_button": row.bar.plus_button,
			"reveal": func() -> void: _reveal_row_cap_button(captured_row),
		})
	return targets


## Fades in the raw-currency bar that was created hidden for this reveal. Called
## by the animator after the currency cap explodes; idempotent and self-clearing
## so end_cap_raise_reveal() can also call it as an anti-stuck backstop.
func reveal_delayed_currency_bar() -> void:
	if _cap_raise_delayed_currency == -1:
		return
	var bar = _bars.get(_cap_raise_delayed_currency)
	_cap_raise_delayed_currency = -1
	if not is_instance_valid(bar) or bar.visible:
		return
	bar.visible = true
	bar.modulate.a = 0.0
	bar.create_tween().tween_property(bar, "modulate:a", 1.0,
		ThemeProvider.theme.cap_raise_currency_appear_duration).set_ease(Tween.EASE_OUT)


func end_cap_raise_reveal() -> void:
	var board := _cap_raise_reveal_board
	_cap_raise_reveal_active = false
	# Anti-stuck backstops: force-show the delayed bar and every cap button if
	# the cinematic was interrupted before reaching them.
	reveal_delayed_currency_bar()
	_on_cap_raise_unlocked(board)


func _is_cap_reveal_suppressed(board: int) -> bool:
	return _cap_raise_reveal_active and board == _cap_raise_reveal_board


func _reveal_currency_cap_button(bar, currency_type: Enums.CurrencyType) -> void:
	if not is_instance_valid(bar):
		return
	bar.show_plus_button(true)
	var can_afford := CurrencyManager.can_buy_cap_raise(currency_type)
	bar.set_plus_disabled(not can_afford)
	bar.set_plus_filled(can_afford)


func _reveal_row_cap_button(row: UpgradeRow) -> void:
	if not is_instance_valid(row):
		return
	row.bar.show_plus_button(true)
	row.bar.update_plus()


func _on_cap_raise_pressed(type: Enums.CurrencyType) -> void:
	CurrencyManager.buy_cap_raise(type)
	_update_all_cap_buttons()
	if _hover_tooltip and _hover_tooltip.visible:
		_on_cap_hover(type)


func _update_all_bars() -> void:
	for currency_type in _bars:
		var bar = _bars[currency_type]
		var amount := CurrencyManager.get_balance(currency_type)
		var cap := CurrencyManager.get_cap(currency_type)
		_update_bar(bar, currency_type, amount, cap)
	_update_all_cap_buttons()


func _update_all_cap_buttons() -> void:
	for currency_type in _bars:
		var bar = _bars[currency_type]
		var board: int = CurrencyManager.cap_raise_board(currency_type)
		var show := board != -1 and UpgradeManager.is_cap_raise_available(board)
		# Keep a not-yet-shown button hidden while its board's reveal runs; never
		# hide one that is already visible.
		if show and _is_cap_reveal_suppressed(board) and not bar.plus_button.visible:
			show = false
		bar.show_plus_button(show)
		if show:
			var can_afford := CurrencyManager.can_buy_cap_raise(currency_type)
			bar.set_plus_disabled(not can_afford)
			bar.set_plus_filled(can_afford)


func _update_cap_button_affordability() -> void:
	for currency_type in _bars:
		var bar = _bars[currency_type]
		if not bar.plus_button.visible:
			continue
		var can_afford := CurrencyManager.can_buy_cap_raise(currency_type)
		bar.set_plus_disabled(not can_afford)
		bar.set_plus_filled(can_afford)


func _create_section_label(text: String) -> Label:
	var t: VisualTheme = ThemeProvider.theme
	var bold_font: Font = preload("res://style_lab/VendSans-Bold.ttf")
	var btn_font: Font = t.button_font if t.button_font else bold_font
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_size_override("font_size", t.button_font_size)
	label.add_theme_color_override("font_color", t.normal_text_color)
	label.add_theme_font_override("font", btn_font)
	return label


func _animate_universal_section(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType) -> void:
	var needs_header: bool = _upgrade_rows.is_empty()

	if needs_header:
		var spacer := Control.new()
		spacer.custom_minimum_size.y = ThemeProvider.theme.section_spacer_height
		add_child(spacer)

		var label: Label = _create_section_label("")
		add_child(label)

		# Keep tooltip at the very end
		if _hover_tooltip:
			move_child(_hover_tooltip, get_child_count() - 1)

		# Typewriter animation — reveal one character at a time
		var full_text := "Universal upgrades"
		var char_delay: float = ThemeProvider.theme.typewriter_char_delay
		var tween := create_tween()
		for i in full_text.length():
			tween.tween_callback(func(): label.text = full_text.substr(0, i + 1))
			tween.tween_interval(char_delay)

		# After typewriter completes, spawn the upgrade row with clip reveal
		tween.tween_callback(_spawn_and_materialize_row.bind(upgrade_type, board_type))
	else:
		# Section header already exists — just add the row with clip reveal
		_spawn_and_materialize_row(upgrade_type, board_type)


func _spawn_and_materialize_row(upgrade_type: Enums.UpgradeType, board_type: Enums.BoardType) -> void:
	_try_spawn_upgrade_row(upgrade_type, board_type)
	var row: UpgradeRow = _upgrade_rows.get(upgrade_type)
	if row:
		row.materialize()
