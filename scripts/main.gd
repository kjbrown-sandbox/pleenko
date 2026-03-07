extends Node3D

@onready var ui: CanvasLayer = $UI
@onready var camera: Camera3D = $Camera3D

var board_scene: PackedScene = preload("res://scenes/plinko_board.tscn")

# --- Currency ---
var coin_total: int = 1
var coin_max: int = 500
var coin_max_up_cost: int = 1
var unrefined_orange: int = 0
var orange_coin_total: int = 0
var red_coin_total: int = 0

# --- Unlock state ---
var orange_board_unlocked: bool = false
var red_board_unlocked: bool = false

# --- Leveling ---
var player_level: int = 0
const LEVEL_THRESHOLDS: Array[int] = [10, 20, 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1500, 2000, 3000, 5000, 10000]

# --- Row upgrade costs (delta formula: cost += delta, delta += 20) ---
var regular_upgrade_cost: int = 6
var orange_upgrade_cost: int = 6
var red_upgrade_cost: int = 5
var red_upgrade_delta: int = 5

# --- Gold panel upgrades ---
var bucket_value_cost: int = 10
var bucket_value_delta: int = 5
var bucket_value_level: int = 0
var drop_rate_cost: int = 10
var drop_rate_delta: int = 20
var drop_rate_level: int = 0
var autodropper_cost: int = 10

# --- Gold upgrade caps (raised by orange) ---
var gold_row_cap: int = 8
var bucket_value_cap: int = 10
var drop_rate_cap: int = 5
var autodropper_cap: int = 10

# --- Orange panel upgrades (same costs as gold) ---
var orange_drop_rate_cost: int = 10
var orange_drop_rate_delta: int = 20
var orange_drop_rate_level: int = 0
var orange_drop_rate_cap: int = 5
var orange_queue_up_cost: int = 10
var orange_queue_up_delta: int = 10
var orange_bucket_value_cost: int = 10
var orange_bucket_value_delta: int = 5
var orange_bucket_value_level: int = 0
var orange_bucket_value_cap: int = 10

# --- Orange cap-raise costs (flat +2 increment: 1, 3, 5, 7...) ---
var row_cap_cost: int = 1
var value_cap_cost: int = 1
var rate_cap_cost: int = 1
var auto_cap_cost: int = 1

# --- Currency caps ---
var unrefined_orange_max: int = 100
var orange_coin_max: int = 500

# --- Row caps (orange/red boards) ---
var orange_row_cap: int = 8
var red_row_cap: int = 5

# --- Autodropper (gold board auto-drop) ---
var autodropper_level: int = 0
var autodropper_timer: Timer

# --- Gold queue (each entry is a multiplier: 1=normal, 3=unrefined, 5=level-up) ---
var gold_queue: Array[int] = []
var gold_queue_max: int = 0
var gold_queue_up_cost: int = 10
var gold_queue_up_delta: int = 10
var gold_drain_timer: Timer
var orange_drain_timer: Timer

# --- Orange/Red queue credits ---
var orange_queue: int = 0
var orange_queue_max: int = 0
var red_queue: int = 0
var red_queue_max: int = 1

# --- Board selection ---
var selected_board: PlinkoBoard
var camera_tween: Tween

# --- Game timer ---
var elapsed_time: float = 0.0

# --- Level-up dialog queue ---
var level_up_queue: Array[Dictionary] = []  # {level, message, action}

# --- Per-board drop cooldowns ---
var board_drop_cooldowns: Dictionary = {}   # PlinkoBoard → Timer
var board_drop_labels: Dictionary = {}      # PlinkoBoard → Label3D
var gold_cooldown_time := 2.0
var orange_cooldown_time := 10.0

# --- Drop costs ---
var orange_drop_cost := 100   # gold cost to drop on orange
var red_drop_cost := 1        # orange cost to drop on red

# --- Visual queue ---
var queue_visual_container: Node3D
var queue_coin_mesh: SphereMesh

# --- Boards ---
const BOARD_GAP := 3.0
var regular_board: PlinkoBoard
var orange_board: PlinkoBoard
var red_board: PlinkoBoard


func _ready() -> void:
	# Create regular (gold) board with 2 rows
	regular_board = board_scene.instantiate() as PlinkoBoard
	add_child(regular_board)

	regular_board.board_clicked.connect(func(): select_board(regular_board))
	regular_board.coin_landed.connect(_on_regular_coin_landed)
	regular_board.board_rebuilt.connect(_adjust_camera)

	# Select gold board before building so _adjust_camera has a valid target
	selected_board = regular_board
	regular_board.set_selected(true)

	regular_board.num_rows = 2
	regular_board._build_board()

	# Visual queue container (3D coins above drop point)
	queue_visual_container = Node3D.new()
	regular_board.add_child(queue_visual_container)
	queue_coin_mesh = SphereMesh.new()
	queue_coin_mesh.radius = 0.15
	queue_coin_mesh.height = 0.3

	# Autodropper timer (gold board auto-drops, independent of manual cooldown)
	autodropper_timer = Timer.new()
	autodropper_timer.one_shot = false
	autodropper_timer.autostart = false
	autodropper_timer.timeout.connect(_on_autodropper_timeout)
	add_child(autodropper_timer)

	# Gold drain timer (drains gold queue at drop rate)
	gold_drain_timer = Timer.new()
	gold_drain_timer.one_shot = false
	gold_drain_timer.autostart = false
	gold_drain_timer.wait_time = gold_cooldown_time
	gold_drain_timer.timeout.connect(_on_gold_drain_timeout)
	add_child(gold_drain_timer)

	# Orange drain timer (drains orange queue at drop rate)
	orange_drain_timer = Timer.new()
	orange_drain_timer.one_shot = false
	orange_drain_timer.autostart = false
	orange_drain_timer.wait_time = orange_cooldown_time
	orange_drain_timer.timeout.connect(_on_orange_drain_timeout)
	add_child(orange_drain_timer)

	# Setup gold board drop cooldown + label (after gold_drain_timer so _drop_status_text works)
	_setup_board_drop(regular_board, gold_cooldown_time)

	# Auto-save timer (every 30 seconds)
	var save_timer := Timer.new()
	save_timer.wait_time = 30.0
	save_timer.one_shot = false
	save_timer.autostart = true
	save_timer.timeout.connect(_save_game)
	add_child(save_timer)

	# UI init
	ui.update_coins(coin_total, coin_max)
	_update_level_label()
	_refresh_upgrade_panel()

	# Connect UI signals
	ui.upgrade_action.connect(_on_upgrade_action)
	ui.board_tab_selected.connect(_on_board_tab_selected)
	ui.reset_pressed.connect(_reset_game)
	ui.reset_dev_pressed.connect(_reset_game_dev)
	ui.level_up_dismissed.connect(_on_level_up_dismissed)
	ui.drop_unrefined_pressed.connect(_drop_unrefined_on_gold)
	ui.drop_coin_pressed.connect(_drop_on_selected_board)
	ui.speed_toggle_pressed.connect(_toggle_speed)
	ui.quicksave_pressed.connect(_quicksave)
	ui.quickload_pressed.connect(_quickload)

	# Load saved progress (must be after all setup)
	_load_game()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("drop_coin"):
		_drop_on_selected_board()
	if event.is_action_pressed("drop_unrefined"):
		_drop_unrefined_on_gold()
	if event.is_action_pressed("quicksave"):
		_quicksave()


func _process(delta: float) -> void:
	elapsed_time += delta
	ui.update_game_timer(elapsed_time)
	_update_level_label()

	# Update drop labels for all boards with cooldowns
	for board: PlinkoBoard in board_drop_cooldowns:
		var timer: Timer = board_drop_cooldowns[board]
		var label: Label3D = board_drop_labels[board]
		if not timer.is_stopped():
			label.text = "reloading..."
		else:
			label.text = _drop_status_text(board)


# === Board selection ===

func _on_board_tab_selected(board_type: int) -> void:
	match board_type:
		PlinkoBoard.BoardType.GOLD:
			select_board(regular_board)
		PlinkoBoard.BoardType.ORANGE:
			if orange_board_unlocked and orange_board:
				select_board(orange_board)
		PlinkoBoard.BoardType.RED:
			if red_board_unlocked and red_board:
				select_board(red_board)


func select_board(board: PlinkoBoard) -> void:
	if selected_board == board:
		return

	if selected_board:
		selected_board.set_selected(false)

	selected_board = board
	selected_board.set_selected(true)

	_tween_camera_to_board(board)
	_refresh_upgrade_panel()


func _drop_status_text(board: PlinkoBoard) -> String:
	match board.board_type:
		PlinkoBoard.BoardType.GOLD:
			if gold_queue_max == 0:
				# No queue — simple cooldown 	
				if not gold_drain_timer.is_stopped():
					return "reloading..."
				if coin_total < 1:
					return "need gold"
				return "ready (1g)"
			else:
				# Queue mode
				var qs := "[" + str(gold_queue.size()) + "/" + str(gold_queue_max) + "] "
				if coin_total < 1 and gold_queue.is_empty():
					return qs + "need gold"
				if gold_queue.size() >= gold_queue_max:
					return qs + "full"
				return qs + "ready (1g)"
		PlinkoBoard.BoardType.ORANGE:
			if orange_queue_max == 0:
				if not orange_drain_timer.is_stopped():
					return "reloading..."
				if unrefined_orange <= 0:
					return "need unrefined"
				if coin_total < orange_drop_cost:
					return "need gold"
				return "ready (" + str(orange_drop_cost) + "g + 1 unrefined)"
			else:
				var qs := "[" + str(orange_queue) + "/" + str(orange_queue_max) + "] "
				if unrefined_orange <= 0 and orange_queue <= 0:
					return qs + "need unrefined"
				if coin_total < orange_drop_cost and orange_queue <= 0:
					return qs + "need gold"
				if orange_queue >= orange_queue_max:
					return qs + "full"
				return qs + "ready (" + str(orange_drop_cost) + "g + 1 unrefined)"
		PlinkoBoard.BoardType.RED:
			if red_queue <= 0:
				return "need credits"
			if orange_coin_total < red_drop_cost:
				return "need orange"
			return "ready (" + str(red_drop_cost) + "o + 1 credit)"
	return ""


func _tween_camera_to_board(board: PlinkoBoard) -> void:
	if camera_tween:
		camera_tween.kill()

	var bounds := board.get_bounds()
	var center_x := bounds.position.x + bounds.size.x / 2.0
	var center_y := bounds.position.y + bounds.size.y / 2.0
	var board_height := bounds.size.y
	var board_width := bounds.size.x

	var z_for_height := board_height * 0.9
	var z_for_width := board_width * 0.7
	var z_distance := maxf(6.0, maxf(z_for_height, z_for_width))

	var target := Vector3(center_x, center_y, z_distance)

	camera_tween = create_tween()
	camera_tween.tween_property(camera, "position", target, 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _setup_board_drop(board: PlinkoBoard, cooldown_time: float) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = cooldown_time
	add_child(timer)
	board_drop_cooldowns[board] = timer

	var label := Label3D.new()
	label.font_size = 48
	label.text = _drop_status_text(board)
	label.position = Vector3(0.0, PlinkoBoard.TOP_Y + 1.8, 0.0)
	board.add_child(label)
	board_drop_labels[board] = label


# === Unified drop handler ===

func _drop_on_selected_board() -> void:
	if not selected_board:
		return
	if ui.is_level_up_visible():
		return

	match selected_board.board_type:
		PlinkoBoard.BoardType.GOLD:
			if coin_total < 1:
				return
			if gold_queue_max == 0:
				# No queue — simple cooldown
				if not gold_drain_timer.is_stopped():
					return
				if regular_board.drop_coin():
					coin_total -= 1
					ui.update_coins(coin_total, coin_max)
					_update_level_label()
					gold_drain_timer.start()
			else:
				# Queue mode
				if gold_queue.size() < gold_queue_max:
					coin_total -= 1
					ui.update_coins(coin_total, coin_max)
					_update_level_label()
					if gold_drain_timer.is_stopped():
						# Timer ready — drop immediately
						regular_board.drop_coin()
						gold_drain_timer.start()
					else:
						# Timer running — add to queue for later
						gold_queue.append(1)
					_update_queue_visual()
					_refresh_upgrade_header()

		PlinkoBoard.BoardType.ORANGE:
			if coin_total < orange_drop_cost:
				return
			if unrefined_orange <= 0:
				return
			if orange_queue_max == 0:
				# No queue — simple cooldown
				if not orange_drain_timer.is_stopped():
					return
				if selected_board.drop_coin():
					coin_total -= orange_drop_cost
					unrefined_orange -= 1
					ui.update_coins(coin_total, coin_max)
					ui.update_unrefined_orange(unrefined_orange)
					_update_level_label()
					_refresh_upgrade_header()
					orange_drain_timer.start()
			else:
				# Queue mode
				if orange_queue >= orange_queue_max:
					return
				coin_total -= orange_drop_cost
				unrefined_orange -= 1
				ui.update_coins(coin_total, coin_max)
				ui.update_unrefined_orange(unrefined_orange)
				_update_level_label()
				if orange_drain_timer.is_stopped():
					selected_board.drop_coin()
					orange_drain_timer.start()
				else:
					orange_queue += 1
				_refresh_upgrade_header()

		PlinkoBoard.BoardType.RED:
			var timer: Timer = board_drop_cooldowns.get(selected_board)
			if timer and not timer.is_stopped():
				return
			if orange_coin_total < red_drop_cost:
				return
			if red_queue <= 0:
				return
			if selected_board.drop_coin():
				orange_coin_total -= red_drop_cost
				red_queue -= 1
				ui.update_orange_coins(orange_coin_total)
				_refresh_upgrade_header()
				if timer:
					timer.start()


# === Autodropper (gold board only) ===

func _on_autodropper_timeout() -> void:
	if coin_total >= 1 and gold_queue.size() < gold_queue_max:
		coin_total -= 1
		gold_queue.append(1)
		ui.update_coins(coin_total, coin_max)
		if gold_drain_timer.is_stopped():
			gold_drain_timer.start()
		_update_queue_visual()
		_refresh_upgrade_header()


func _on_gold_drain_timeout() -> void:
	if gold_queue.size() > 0:
		var multiplier: int = gold_queue.pop_front()
		regular_board.drop_coin(multiplier)
		_update_queue_visual()
		_refresh_upgrade_header()
	else:
		# Queue empty — stop timer (enforces one cooldown cycle after last drop)
		gold_drain_timer.stop()


func _on_orange_drain_timeout() -> void:
	if orange_queue > 0:
		orange_queue -= 1
		if orange_board:
			orange_board.drop_coin()
		_refresh_upgrade_header()
	else:
		orange_drain_timer.stop()


# === Drop unrefined orange on gold board ===

func _drop_unrefined_on_gold() -> void:
	if ui.is_level_up_visible():
		return
	if unrefined_orange <= 0:
		return

	if gold_queue_max == 0:
		# No queue — simple cooldown, drop immediately
		if not gold_drain_timer.is_stopped():
			return
		if regular_board.drop_coin(3):
			unrefined_orange -= 1
			ui.update_unrefined_orange(unrefined_orange)
			gold_drain_timer.start()
	else:
		# Queue mode — add to queue if not full
		if gold_queue.size() < gold_queue_max:
			unrefined_orange -= 1
			ui.update_unrefined_orange(unrefined_orange)
			if gold_drain_timer.is_stopped():
				regular_board.drop_coin(3)
				gold_drain_timer.start()
			else:
				gold_queue.append(3)
			_update_queue_visual()
			_refresh_upgrade_header()


# === Add to gold queue (allows overfill for level-up rewards) ===

func _add_to_gold_queue(multiplier: int) -> void:
	if gold_queue_max == 0:
		# No queue bought yet — drop immediately
		regular_board.drop_coin(multiplier)
		if gold_drain_timer.is_stopped():
			gold_drain_timer.start()
		return

	# Queue mode — can overfill (level-up only calls this)
	if gold_drain_timer.is_stopped():
		regular_board.drop_coin(multiplier)
		gold_drain_timer.start()
	else:
		gold_queue.append(multiplier)
	_update_queue_visual()
	_refresh_upgrade_header()


# === Visual queue (3D coins stacked above drop point) ===

func _update_queue_visual() -> void:
	# Clear existing visuals
	for child in queue_visual_container.get_children():
		child.queue_free()

	if gold_queue_max == 0:
		return

	for i in range(gold_queue.size()):
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = queue_coin_mesh

		# Stack vertically above drop point, overlapping slightly
		var y := PlinkoBoard.TOP_Y + 1.2 + i * 0.25
		# Bottom coin in front (higher z)
		var z := 0.05 * (gold_queue.size() - i)
		mesh_inst.position = Vector3(0.0, y, z)

		# Color based on multiplier
		var multiplier: int = gold_queue[i]
		if multiplier >= 3:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color.ORANGE
			mesh_inst.material_override = mat

		queue_visual_container.add_child(mesh_inst)


# === Coin landed handlers ===

func _on_regular_coin_landed(value: int, bucket_type: PlinkoBoard.BucketType) -> void:
	match bucket_type:
		PlinkoBoard.BucketType.GOLD:
			coin_total = mini(coin_total + value, coin_max)
			ui.update_coins(coin_total, coin_max)
			_check_level_up()
		PlinkoBoard.BucketType.ORANGE:
			unrefined_orange = mini(unrefined_orange + value, unrefined_orange_max)
			ui.update_unrefined_orange(unrefined_orange)
			_check_unlock_orange_board()
		PlinkoBoard.BucketType.RED:
			_add_to_red_queue(value)
			_check_unlock_red_board()
	_refresh_upgrade_states()


func _on_orange_coin_landed(value: int, bucket_type: PlinkoBoard.BucketType) -> void:
	match bucket_type:
		PlinkoBoard.BucketType.ORANGE:
			orange_coin_total = mini(orange_coin_total + value, orange_coin_max)
			ui.update_orange_coins(orange_coin_total)
		PlinkoBoard.BucketType.RED:
			_add_to_red_queue(value)
			_check_unlock_red_board()
		_:
			orange_coin_total = mini(orange_coin_total + value, orange_coin_max)
			ui.update_orange_coins(orange_coin_total)
	_refresh_upgrade_states()


func _on_red_coin_landed(value: int, _bucket_type: PlinkoBoard.BucketType) -> void:
	red_coin_total += value
	ui.update_red_coins(red_coin_total)
	_refresh_upgrade_states()


# === Queue credits ===

func _add_to_red_queue(count: int) -> void:
	red_queue = mini(red_queue + count, red_queue_max)
	if selected_board and selected_board.board_type == PlinkoBoard.BoardType.RED:
		_refresh_upgrade_header()


# === Board unlock ===

func _check_unlock_orange_board() -> void:
	if orange_board_unlocked:
		return

	orange_board_unlocked = true

	orange_board = board_scene.instantiate() as PlinkoBoard
	orange_board.board_type = PlinkoBoard.BoardType.ORANGE
	add_child(orange_board)

	orange_board.board_clicked.connect(func(): select_board(orange_board))
	orange_board.coin_landed.connect(_on_orange_coin_landed)
	orange_board.board_rebuilt.connect(_adjust_camera)

	orange_board.num_rows = 2
	orange_board._build_board()

	_setup_board_drop(orange_board, orange_cooldown_time)

	ui.show_orange_currency()
	ui.update_orange_coins(orange_coin_total)

	# Refresh gold panel to show "+" buttons if level is high enough
	if selected_board == regular_board:
		_refresh_upgrade_panel()


func _check_unlock_red_board() -> void:
	if red_board_unlocked:
		return

	red_board_unlocked = true

	red_board = board_scene.instantiate() as PlinkoBoard
	red_board.board_type = PlinkoBoard.BoardType.RED
	add_child(red_board)

	red_board.board_clicked.connect(func(): select_board(red_board))
	red_board.coin_landed.connect(_on_red_coin_landed)
	red_board.board_rebuilt.connect(_adjust_camera)

	red_board.num_rows = 2
	red_board._build_board()

	_setup_board_drop(red_board, 1.0)

	ui.show_red_currency()
	ui.update_red_coins(red_coin_total)


# === Upgrade panel ===

func _refresh_upgrade_panel() -> void:
	if not selected_board:
		return

	match selected_board.board_type:
		PlinkoBoard.BoardType.GOLD:
			var header := "Gold Upgrades"
			if gold_queue_max > 0:
				header += " [queue: " + str(gold_queue.size()) + "/" + str(gold_queue_max) + "]"
			ui.show_upgrades_for_board(header, _gold_upgrades())
		PlinkoBoard.BoardType.ORANGE:
			var header := "Orange Upgrades [unrefined: " + str(unrefined_orange) + "/" + str(unrefined_orange_max) + "]"
			if orange_queue_max > 0:
				header += " [queue: " + str(orange_queue) + "/" + str(orange_queue_max) + "]"
			ui.show_upgrades_for_board(header, _orange_upgrades())
		PlinkoBoard.BoardType.RED:
			var header := "Red Upgrades [" + str(red_queue) + "/" + str(red_queue_max) + "]"
			ui.show_upgrades_for_board(header, _red_upgrades())


func _refresh_upgrade_header() -> void:
	if not selected_board:
		return
	match selected_board.board_type:
		PlinkoBoard.BoardType.GOLD:
			var header := "Gold Upgrades"
			if gold_queue_max > 0:
				header += " [queue: " + str(gold_queue.size()) + "/" + str(gold_queue_max) + "]"
			ui.update_header(header)
		PlinkoBoard.BoardType.ORANGE:
			var header := "Orange Upgrades [unrefined: " + str(unrefined_orange) + "/" + str(unrefined_orange_max) + "]"
			if orange_queue_max > 0:
				header += " [queue: " + str(orange_queue) + "/" + str(orange_queue_max) + "]"
			ui.update_header(header)
		PlinkoBoard.BoardType.RED:
			ui.update_header("Red Upgrades [" + str(red_queue) + "/" + str(red_queue_max) + "]")


func _refresh_upgrade_states() -> void:
	if not selected_board:
		return
	match selected_board.board_type:
		PlinkoBoard.BoardType.GOLD:
			_update_state("add_row", regular_board.num_rows >= gold_row_cap, coin_total >= regular_upgrade_cost)
			_update_state("bucket_value", bucket_value_level >= bucket_value_cap, coin_total >= bucket_value_cost)
			_update_state("drop_rate", drop_rate_level >= drop_rate_cap, coin_total >= drop_rate_cost)
			_update_state("gold_queue_up", false, coin_total >= gold_queue_up_cost)
			_update_state("autodropper", autodropper_level >= autodropper_cap, coin_total >= autodropper_cost)
		PlinkoBoard.BoardType.ORANGE:
			_update_state("coin_max_up", false, orange_coin_total >= coin_max_up_cost)
			var orange_rows := orange_board.num_rows if orange_board else 0
			_update_state("orange_add_row", orange_rows >= orange_row_cap, orange_coin_total >= orange_upgrade_cost)
			_update_state("orange_bucket_value", orange_bucket_value_level >= orange_bucket_value_cap, orange_coin_total >= orange_bucket_value_cost)
			_update_state("orange_drop_rate", orange_drop_rate_level >= orange_drop_rate_cap, orange_coin_total >= orange_drop_rate_cost)
			_update_state("orange_queue_up", false, orange_coin_total >= orange_queue_up_cost)
		PlinkoBoard.BoardType.RED:
			_update_state("red_add_row", false, red_coin_total >= red_upgrade_cost)


func _update_state(action: String, is_maxed: bool, can_afford: bool) -> void:
	if is_maxed:
		ui.update_entry_state(action, "maxed")
	elif can_afford:
		ui.update_entry_state(action, "available")
	else:
		ui.update_entry_state(action, "too_expensive")


func _gold_upgrades() -> Array[Dictionary]:
	var upgrades: Array[Dictionary] = []

	# Add 2 Rows (level 1)
	if player_level >= 1:
		var row_state := "available"
		if regular_board.num_rows >= gold_row_cap:
			row_state = "maxed"
		elif coin_total < regular_upgrade_cost:
			row_state = "too_expensive"
		var entry: Dictionary = {
			"action": "add_row",
			"label": "Add 2 Rows",
			"cost_text": "Cost: " + str(regular_upgrade_cost) + " | Rows: " + str(regular_board.num_rows) + "/" + str(gold_row_cap),
			"state": row_state,
		}
		if orange_board_unlocked:
			entry["cap_action"] = "row_cap"
			entry["cap_hover"] = "Row Cap +2: " + str(row_cap_cost) + " orange"
		upgrades.append(entry)

	# Bucket Value +2 (level 2)
	if player_level >= 2:
		var bv_state := "available"
		if bucket_value_level >= bucket_value_cap:
			bv_state = "maxed"
		elif coin_total < bucket_value_cost:
			bv_state = "too_expensive"
		var entry: Dictionary = {
			"action": "bucket_value",
			"label": "Bucket Value +2",
			"cost_text": "Cost: " + str(bucket_value_cost) + " | Lvl: " + str(bucket_value_level) + "/" + str(bucket_value_cap),
			"state": bv_state,
		}
		if orange_board_unlocked:
			entry["cap_action"] = "value_cap"
			entry["cap_hover"] = "Value Cap +1: " + str(value_cap_cost) + " orange"
		upgrades.append(entry)

	# Drop Rate (level 3)
	if player_level >= 3:
		var dr_state := "available"
		if drop_rate_level >= drop_rate_cap:
			dr_state = "maxed"
		elif coin_total < drop_rate_cost:
			dr_state = "too_expensive"
		var entry: Dictionary = {
			"action": "drop_rate",
			"label": "Drop Rate",
			"cost_text": "Cost: " + str(drop_rate_cost) + " | Rate: " + str(snapped(gold_cooldown_time, 0.01)) + "s | Lvl: " + str(drop_rate_level) + "/" + str(drop_rate_cap),
			"state": dr_state,
		}
		if orange_board_unlocked:
			entry["cap_action"] = "rate_cap"
			entry["cap_hover"] = "Rate Cap +1: " + str(rate_cap_cost) + " orange"
		upgrades.append(entry)

	# Queue +1 (level 4)
	if player_level >= 4:
		var q_state := "available" if coin_total >= gold_queue_up_cost else "too_expensive"
		upgrades.append({
			"action": "gold_queue_up",
			"label": "Queue +1",
			"cost_text": "Cost: " + str(gold_queue_up_cost) + " | Queue: " + str(gold_queue_max),
			"state": q_state,
		})

	# Autodropper (level 6)
	if player_level >= 6:
		var ad_state := "available"
		if autodropper_level >= autodropper_cap:
			ad_state = "maxed"
		elif coin_total < autodropper_cost:
			ad_state = "too_expensive"
		var cost_text := "Cost: " + str(autodropper_cost) + " | Lvl: " + str(autodropper_level) + "/" + str(autodropper_cap)
		if autodropper_level > 0:
			cost_text += " | avg. coins/sec: " + str(snapped(autodropper_level / 10.0, 0.01))
		var entry: Dictionary = {
			"action": "autodropper",
			"label": "Autodropper",
			"cost_text": cost_text,
			"state": ad_state,
		}
		if orange_board_unlocked:
			entry["cap_action"] = "auto_cap"
			entry["cap_hover"] = "Auto Cap +1: " + str(auto_cap_cost) + " orange"
		upgrades.append(entry)

	return upgrades


func _orange_upgrades() -> Array[Dictionary]:
	var upgrades: Array[Dictionary] = []

	upgrades.append({
		"action": "coin_max_up",
		"label": "Gold Cap +500",
		"cost_text": "Cost: " + str(coin_max_up_cost) + " orange | Cap: " + str(coin_max),
		"state": "available" if orange_coin_total >= coin_max_up_cost else "too_expensive",
	})

	# Add 2 Rows (level 9)
	if player_level >= 9:
		var row_state := "available"
		if orange_board and orange_board.num_rows >= orange_row_cap:
			row_state = "maxed"
		elif orange_coin_total < orange_upgrade_cost:
			row_state = "too_expensive"
		var rows_text := str(orange_board.num_rows) if orange_board else "0"
		upgrades.append({
			"action": "orange_add_row",
			"label": "Add 2 Rows",
			"cost_text": "Cost: " + str(orange_upgrade_cost) + " | Rows: " + rows_text + "/" + str(orange_row_cap),
			"state": row_state,
		})

	# Bucket Value +2 (level 10)
	if player_level >= 10:
		var bv_state := "available"
		if orange_bucket_value_level >= orange_bucket_value_cap:
			bv_state = "maxed"
		elif orange_coin_total < orange_bucket_value_cost:
			bv_state = "too_expensive"
		upgrades.append({
			"action": "orange_bucket_value",
			"label": "Bucket Value +2",
			"cost_text": "Cost: " + str(orange_bucket_value_cost) + " | Lvl: " + str(orange_bucket_value_level) + "/" + str(orange_bucket_value_cap),
			"state": bv_state,
		})

	# Drop Rate (level 11)
	if player_level >= 11:
		var dr_state := "available"
		if orange_drop_rate_level >= orange_drop_rate_cap:
			dr_state = "maxed"
		elif orange_coin_total < orange_drop_rate_cost:
			dr_state = "too_expensive"
		upgrades.append({
			"action": "orange_drop_rate",
			"label": "Drop Rate",
			"cost_text": "Cost: " + str(orange_drop_rate_cost) + " | Rate: " + str(snapped(orange_cooldown_time, 0.01)) + "s | Lvl: " + str(orange_drop_rate_level) + "/" + str(orange_drop_rate_cap),
			"state": dr_state,
		})

	# Queue +1 (level 12)
	if player_level >= 12:
		var q_state := "available" if orange_coin_total >= orange_queue_up_cost else "too_expensive"
		upgrades.append({
			"action": "orange_queue_up",
			"label": "Queue +1",
			"cost_text": "Cost: " + str(orange_queue_up_cost) + " | Queue: " + str(orange_queue_max),
			"state": q_state,
		})

	return upgrades


func _red_upgrades() -> Array[Dictionary]:
	var upgrades: Array[Dictionary] = []

	upgrades.append({
		"action": "red_add_row",
		"label": "Add Row",
		"cost_text": "Cost: " + str(red_upgrade_cost),
		"state": "available" if red_coin_total >= red_upgrade_cost else "too_expensive",
	})

	return upgrades


# === Upgrade action dispatcher ===

func _on_upgrade_action(action_name: String) -> void:
	match action_name:
		"bucket_value":
			_buy_bucket_value()
		"add_row":
			_buy_regular_upgrade()
		"drop_rate":
			_buy_drop_rate()
		"autodropper":
			_buy_autodropper()
		"gold_queue_up":
			_buy_gold_queue_up()
		"value_cap":
			_buy_value_cap()
		"row_cap":
			_buy_row_cap()
		"rate_cap":
			_buy_rate_cap()
		"auto_cap":
			_buy_auto_cap()
		"coin_max_up":
			_buy_coin_max_up()
		"orange_bucket_value":
			_buy_orange_bucket_value()
		"orange_drop_rate":
			_buy_orange_drop_rate()
		"orange_queue_up":
			_buy_orange_queue_up()
		"orange_add_row":
			_buy_orange_upgrade()
		"red_add_row":
			_buy_red_upgrade()

	_refresh_upgrade_panel()


# === Gold board upgrade (Add Row) ===

func _buy_regular_upgrade() -> void:
	if coin_total < regular_upgrade_cost:
		return
	if regular_board.num_rows >= gold_row_cap:
		return

	coin_total -= regular_upgrade_cost
	regular_board.add_row()
	regular_board.add_row()

	regular_upgrade_cost *= 10
	ui.update_coins(coin_total, coin_max)


# === Bucket Value +2 (gold currency, gold panel, capped) ===

func _buy_bucket_value() -> void:
	if coin_total < bucket_value_cost:
		return
	if bucket_value_level >= bucket_value_cap:
		return

	coin_total -= bucket_value_cost
	bucket_value_level += 2

	regular_board.value_bonus = bucket_value_level
	regular_board._build_board()

	bucket_value_cost += bucket_value_delta
	bucket_value_delta += 10
	ui.update_coins(coin_total, coin_max)


# === Drop Rate (gold currency, gold panel, capped) ===

func _buy_drop_rate() -> void:
	if coin_total < drop_rate_cost:
		return
	if drop_rate_level >= drop_rate_cap:
		return

	coin_total -= drop_rate_cost
	drop_rate_level += 1

	gold_cooldown_time *= 0.8
	gold_drain_timer.wait_time = gold_cooldown_time

	drop_rate_cost += drop_rate_delta
	drop_rate_delta += 20
	ui.update_coins(coin_total, coin_max)


# === Autodropper (gold currency, gold panel, capped) ===

func _buy_autodropper() -> void:
	if coin_total < autodropper_cost:
		return
	if autodropper_level >= autodropper_cap:
		return

	coin_total -= autodropper_cost
	autodropper_level += 1

	autodropper_cost += 10
	autodropper_timer.wait_time = 10.0 / autodropper_level
	autodropper_timer.start()

	ui.update_coins(coin_total, coin_max)


# === Gold Queue +1 (gold currency, gold panel, uncapped) ===

func _buy_gold_queue_up() -> void:
	if coin_total < gold_queue_up_cost:
		return

	coin_total -= gold_queue_up_cost
	gold_queue_max += 1

	gold_queue_up_cost += gold_queue_up_delta
	ui.update_coins(coin_total, coin_max)


# === Orange cap-raise upgrades (orange currency, raise gold caps) ===

func _buy_row_cap() -> void:
	if orange_coin_total < row_cap_cost:
		return

	orange_coin_total -= row_cap_cost
	gold_row_cap += 2
	row_cap_cost += 2
	ui.update_orange_coins(orange_coin_total)


func _buy_value_cap() -> void:
	if orange_coin_total < value_cap_cost:
		return

	orange_coin_total -= value_cap_cost
	bucket_value_cap += 1
	value_cap_cost += 2
	ui.update_orange_coins(orange_coin_total)


func _buy_rate_cap() -> void:
	if orange_coin_total < rate_cap_cost:
		return

	orange_coin_total -= rate_cap_cost
	drop_rate_cap += 1
	rate_cap_cost += 2
	ui.update_orange_coins(orange_coin_total)


func _buy_auto_cap() -> void:
	if orange_coin_total < auto_cap_cost:
		return

	orange_coin_total -= auto_cap_cost
	autodropper_cap += 1
	auto_cap_cost += 2
	ui.update_orange_coins(orange_coin_total)


# === Gold Cap upgrade (orange currency) ===

func _buy_coin_max_up() -> void:
	if orange_coin_total < coin_max_up_cost:
		return

	orange_coin_total -= coin_max_up_cost
	coin_max += 500
	coin_max_up_cost += 1
	ui.update_orange_coins(orange_coin_total)


# === Orange board upgrades ===

func _buy_orange_upgrade() -> void:
	if orange_coin_total < orange_upgrade_cost:
		return
	if not orange_board or orange_board.num_rows >= orange_row_cap:
		return

	orange_coin_total -= orange_upgrade_cost
	orange_board.add_row()
	orange_board.add_row()

	orange_upgrade_cost *= 10
	ui.update_orange_coins(orange_coin_total)


func _buy_orange_drop_rate() -> void:
	if orange_coin_total < orange_drop_rate_cost:
		return
	if orange_drop_rate_level >= orange_drop_rate_cap:
		return

	orange_coin_total -= orange_drop_rate_cost
	orange_drop_rate_level += 1

	orange_cooldown_time *= 0.8
	orange_drain_timer.wait_time = orange_cooldown_time

	orange_drop_rate_cost += orange_drop_rate_delta
	orange_drop_rate_delta += 20
	ui.update_orange_coins(orange_coin_total)


func _buy_orange_queue_up() -> void:
	if orange_coin_total < orange_queue_up_cost:
		return

	orange_coin_total -= orange_queue_up_cost
	orange_queue_max += 1

	orange_queue_up_cost += orange_queue_up_delta
	orange_queue_up_delta += 10
	ui.update_orange_coins(orange_coin_total)


func _buy_orange_bucket_value() -> void:
	if orange_coin_total < orange_bucket_value_cost:
		return
	if orange_bucket_value_level >= orange_bucket_value_cap:
		return

	orange_coin_total -= orange_bucket_value_cost
	orange_bucket_value_level += 2

	if orange_board:
		orange_board.value_bonus = orange_bucket_value_level
		orange_board._build_board()

	orange_bucket_value_cost += orange_bucket_value_delta
	orange_bucket_value_delta += 10
	ui.update_orange_coins(orange_coin_total)


# === Red board upgrade (Add Row) ===

func _buy_red_upgrade() -> void:
	if red_coin_total < red_upgrade_cost:
		return

	red_coin_total -= red_upgrade_cost
	red_board.add_row()

	red_upgrade_cost += red_upgrade_delta
	red_upgrade_delta += 5
	ui.update_red_coins(red_coin_total)


# === Leveling system ===

func _check_level_up() -> void:
	while player_level < LEVEL_THRESHOLDS.size() and coin_total >= LEVEL_THRESHOLDS[player_level]:
		player_level += 1
		_on_level_up(player_level)
	_update_level_label()


func _on_level_up(level: int) -> void:
	var message := ""
	var action := ""

	match level:
		1:
			message = "You have unlocked the shop."
			action = "shop"
		2:
			message = "You have unlocked Bucket Value in the shop."
		3:
			message = "You have unlocked Drop Rate in the shop."
		4:
			message = "You have unlocked Queue in the shop."
		5:
			message = "An ORANGE ball will be dropped!"
			action = "orange_ball"
		6:
			message = "You have unlocked Autodropper in the shop."
		7:
			message = "An ORANGE ball will be dropped!"
			action = "orange_ball"
		8:
			message = "You have unlocked Orange Buckets!"
			action = "orange_buckets"
		9:
			message = "You have unlocked Add 2 Rows for Orange."
		10:
			message = "You have unlocked Bucket Value for Orange."
		11:
			message = "You have unlocked Drop Rate for Orange."
		12:
			message = "You have unlocked Queue for Orange."
		13:
			message = "You have unlocked Red Buckets on the Orange board!"
			action = "red_buckets"
		_:
			message = "Keep going!"

	level_up_queue.append({"level": level, "message": message, "action": action})
	if not ui.is_level_up_visible():
		_show_next_level_up()


func _show_next_level_up() -> void:
	if level_up_queue.is_empty():
		return
	var entry: Dictionary = level_up_queue[0]
	ui.show_level_up_dialog(entry["level"], entry["message"])


func _on_level_up_dismissed() -> void:
	if level_up_queue.is_empty():
		return

	var entry: Dictionary = level_up_queue.pop_front()

	# Perform the action for this level
	match entry["action"]:
		"orange_ball":
			_add_to_gold_queue(3)
		"orange_buckets":
			regular_board.orange_buckets_enabled = true
			regular_board._build_board()
			ui.show_unrefined_orange()
			ui.show_drop_unrefined_button()
			ui.update_unrefined_orange(unrefined_orange)
			ui.show_coin_max = true
			ui.update_coins(coin_total, coin_max)
		"red_buckets":
			if orange_board:
				orange_board.red_buckets_enabled = true
				orange_board._build_board()

	# Every level-up may unlock new upgrades, so refresh the panel
	_refresh_upgrade_panel()

	# Show next queued dialog if any
	if not level_up_queue.is_empty():
		_show_next_level_up()


func _update_level_label() -> void:
	if player_level < LEVEL_THRESHOLDS.size():
		var next_threshold := LEVEL_THRESHOLDS[player_level]
		ui.update_level(player_level, next_threshold)
		ui.update_level_progress(coin_total, next_threshold)
	else:
		ui.update_level(player_level, 0)
		ui.update_level_progress(coin_total, 0)


# === Board positioning and camera ===

func _position_boards() -> void:
	var boards: Array[PlinkoBoard] = [regular_board]
	if orange_board_unlocked and orange_board:
		boards.append(orange_board)
	if red_board_unlocked and red_board:
		boards.append(red_board)

	if boards.size() == 1:
		boards[0].position = Vector3.ZERO
		return

	# Calculate total width
	var widths: Array[float] = []
	var total_width := 0.0
	for b in boards:
		var w := b.get_bounds().size.x
		widths.append(w)
		total_width += w
	total_width += BOARD_GAP * (boards.size() - 1)

	# Position left-to-right, centered around x=0
	var x := -total_width / 2.0
	for i in range(boards.size()):
		var half_w := widths[i] / 2.0
		boards[i].position.x = x + half_w
		x += widths[i] + BOARD_GAP


func _adjust_camera() -> void:
	_position_boards()
	_tween_camera_to_board(selected_board)

	# Update selection indicator size after board rebuild
	if selected_board:
		selected_board.set_selected(true)


# === Save / Load ===

const SAVE_PATH := "user://save.json"
const QUICKSAVE_PATH := "user://quicksave.json"


func _toggle_speed() -> void:
	if Engine.time_scale == 1.0:
		Engine.time_scale = 10.0
	else:
		Engine.time_scale = 1.0


func _reset_game() -> void:
	# Delete save file
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	# Reload the entire scene from scratch
	get_tree().reload_current_scene()


func _reset_game_dev() -> void:
	# Write a save with level-3 testing state, then reload
	var data := {
		"coin_total": 100,
		"player_level": 3,
		"regular_upgrade_cost": 5000,
		"bucket_value_cost": 55,
		"bucket_value_delta": 35,
		"bucket_value_level": 3,
		"regular_board_num_rows": 8,
		"regular_board_value_bonus": 3,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
	get_tree().reload_current_scene()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()
		get_tree().quit()


func _build_save_data() -> Dictionary:
	var data := {
		# Currencies
		"elapsed_time": elapsed_time,
		"coin_total": coin_total,
		"coin_max": coin_max,
		"coin_max_up_cost": coin_max_up_cost,
		"unrefined_orange": unrefined_orange,
		"orange_coin_total": orange_coin_total,
		"red_coin_total": red_coin_total,
		# Unlock flags
		"orange_board_unlocked": orange_board_unlocked,
		"red_board_unlocked": red_board_unlocked,
		# Level
		"player_level": player_level,
		# Row upgrade costs/deltas
		"regular_upgrade_cost": regular_upgrade_cost,
		"red_upgrade_cost": red_upgrade_cost,
		"red_upgrade_delta": red_upgrade_delta,
		# Gold upgrades
		"bucket_value_cost": bucket_value_cost,
		"bucket_value_delta": bucket_value_delta,
		"bucket_value_level": bucket_value_level,
		"drop_rate_cost": drop_rate_cost,
		"drop_rate_delta": drop_rate_delta,
		"drop_rate_level": drop_rate_level,
		"autodropper_cost": autodropper_cost,
		"autodropper_level": autodropper_level,
		# Gold upgrade caps
		"gold_row_cap": gold_row_cap,
		"bucket_value_cap": bucket_value_cap,
		"drop_rate_cap": drop_rate_cap,
		"autodropper_cap": autodropper_cap,
		# Orange panel upgrades
		"orange_upgrade_cost": orange_upgrade_cost,
		"orange_drop_rate_cost": orange_drop_rate_cost,
		"orange_drop_rate_delta": orange_drop_rate_delta,
		"orange_drop_rate_level": orange_drop_rate_level,
		"orange_drop_rate_cap": orange_drop_rate_cap,
		"orange_queue_up_cost": orange_queue_up_cost,
		"orange_queue_up_delta": orange_queue_up_delta,
		# Cap-raise costs
		"row_cap_cost": row_cap_cost,
		"value_cap_cost": value_cap_cost,
		"rate_cap_cost": rate_cap_cost,
		"auto_cap_cost": auto_cap_cost,
		# Orange bucket value
		"orange_bucket_value_cost": orange_bucket_value_cost,
		"orange_bucket_value_delta": orange_bucket_value_delta,
		"orange_bucket_value_level": orange_bucket_value_level,
		"orange_bucket_value_cap": orange_bucket_value_cap,
		# Row caps
		"orange_row_cap": orange_row_cap,
		"red_row_cap": red_row_cap,
		# Gold queue state
		"gold_queue": gold_queue,
		"gold_queue_max": gold_queue_max,
		"gold_queue_up_cost": gold_queue_up_cost,
		"gold_queue_up_delta": gold_queue_up_delta,
		# Queue state
		"orange_queue": orange_queue,
		"orange_queue_max": orange_queue_max,
		"red_queue": red_queue,
		"red_queue_max": red_queue_max,
		# Cooldown times
		"gold_cooldown_time": gold_cooldown_time,
		"orange_cooldown_time": orange_cooldown_time,
		# Gold board state
		"regular_board_num_rows": regular_board.num_rows,
		"regular_board_value_bonus": regular_board.value_bonus,
		"regular_board_orange_buckets_enabled": regular_board.orange_buckets_enabled,
	}

	# Orange board state (only if unlocked)
	if orange_board_unlocked and orange_board:
		data["orange_board_num_rows"] = orange_board.num_rows
		data["orange_board_value_bonus"] = orange_board.value_bonus
		data["orange_board_red_buckets_enabled"] = orange_board.red_buckets_enabled

	# Red board state (only if unlocked)
	if red_board_unlocked and red_board:
		data["red_board_num_rows"] = red_board.num_rows
		data["red_board_value_bonus"] = red_board.value_bonus

	return data


func _save_game() -> void:
	var json_string := JSON.stringify(_build_save_data())
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)


func _quicksave() -> void:
	var json_string := JSON.stringify(_build_save_data())
	var file := FileAccess.open(QUICKSAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		print("Quicksaved.")


func _quickload() -> void:
	if not FileAccess.file_exists(QUICKSAVE_PATH):
		print("No quicksave found.")
		return
	var file := FileAccess.open(QUICKSAVE_PATH, FileAccess.READ)
	if not file:
		return
	# Write quicksave contents to the main save path, then reload
	var save_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if save_file:
		save_file.store_string(file.get_as_text())
	get_tree().reload_current_scene()


func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return

	var json_string := file.get_as_text()
	var data = JSON.parse_string(json_string)
	if data == null or not data is Dictionary:
		return

	# --- Restore scalar state ---
	elapsed_time = float(data.get("elapsed_time", elapsed_time))
	coin_total = int(data.get("coin_total", coin_total))
	coin_max = int(data.get("coin_max", coin_max))
	coin_max_up_cost = int(data.get("coin_max_up_cost", coin_max_up_cost))
	unrefined_orange = int(data.get("unrefined_orange", unrefined_orange))
	orange_coin_total = int(data.get("orange_coin_total", orange_coin_total))
	red_coin_total = int(data.get("red_coin_total", red_coin_total))

	orange_board_unlocked = data.get("orange_board_unlocked", orange_board_unlocked)
	red_board_unlocked = data.get("red_board_unlocked", red_board_unlocked)

	player_level = int(data.get("player_level", player_level))

	regular_upgrade_cost = int(data.get("regular_upgrade_cost", regular_upgrade_cost))
	orange_upgrade_cost = int(data.get("orange_upgrade_cost", orange_upgrade_cost))
	red_upgrade_cost = int(data.get("red_upgrade_cost", red_upgrade_cost))
	red_upgrade_delta = int(data.get("red_upgrade_delta", red_upgrade_delta))

	bucket_value_cost = int(data.get("bucket_value_cost", bucket_value_cost))
	bucket_value_delta = int(data.get("bucket_value_delta", bucket_value_delta))
	bucket_value_level = int(data.get("bucket_value_level", bucket_value_level))
	drop_rate_cost = int(data.get("drop_rate_cost", drop_rate_cost))
	drop_rate_delta = int(data.get("drop_rate_delta", drop_rate_delta))
	drop_rate_level = int(data.get("drop_rate_level", drop_rate_level))
	autodropper_cost = int(data.get("autodropper_cost", autodropper_cost))
	autodropper_level = int(data.get("autodropper_level", autodropper_level))

	gold_row_cap = int(data.get("gold_row_cap", gold_row_cap))
	bucket_value_cap = int(data.get("bucket_value_cap", bucket_value_cap))
	drop_rate_cap = int(data.get("drop_rate_cap", drop_rate_cap))
	autodropper_cap = int(data.get("autodropper_cap", autodropper_cap))

	orange_drop_rate_cost = int(data.get("orange_drop_rate_cost", orange_drop_rate_cost))
	orange_drop_rate_delta = int(data.get("orange_drop_rate_delta", orange_drop_rate_delta))
	orange_drop_rate_level = int(data.get("orange_drop_rate_level", orange_drop_rate_level))
	orange_drop_rate_cap = int(data.get("orange_drop_rate_cap", orange_drop_rate_cap))
	orange_queue_up_cost = int(data.get("orange_queue_up_cost", orange_queue_up_cost))
	orange_queue_up_delta = int(data.get("orange_queue_up_delta", orange_queue_up_delta))

	row_cap_cost = int(data.get("row_cap_cost", row_cap_cost))
	value_cap_cost = int(data.get("value_cap_cost", value_cap_cost))
	rate_cap_cost = int(data.get("rate_cap_cost", rate_cap_cost))
	auto_cap_cost = int(data.get("auto_cap_cost", auto_cap_cost))

	orange_bucket_value_cost = int(data.get("orange_bucket_value_cost", orange_bucket_value_cost))
	orange_bucket_value_delta = int(data.get("orange_bucket_value_delta", orange_bucket_value_delta))
	orange_bucket_value_level = int(data.get("orange_bucket_value_level", orange_bucket_value_level))
	orange_bucket_value_cap = int(data.get("orange_bucket_value_cap", orange_bucket_value_cap))

	orange_row_cap = int(data.get("orange_row_cap", orange_row_cap))
	red_row_cap = int(data.get("red_row_cap", red_row_cap))

	# Gold queue — backwards compat: old saves have int, new saves have array
	var saved_queue = data.get("gold_queue", [])
	gold_queue = []
	if saved_queue is Array:
		for v in saved_queue:
			gold_queue.append(int(v))
	elif saved_queue is float or saved_queue is int:
		for i in range(int(saved_queue)):
			gold_queue.append(1)
	gold_queue_max = int(data.get("gold_queue_max", gold_queue_max))
	gold_queue_up_cost = int(data.get("gold_queue_up_cost", gold_queue_up_cost))
	gold_queue_up_delta = int(data.get("gold_queue_up_delta", gold_queue_up_delta))

	orange_queue = int(data.get("orange_queue", orange_queue))
	orange_queue_max = int(data.get("orange_queue_max", orange_queue_max))
	red_queue = int(data.get("red_queue", red_queue))
	red_queue_max = int(data.get("red_queue_max", red_queue_max))

	gold_cooldown_time = float(data.get("gold_cooldown_time", gold_cooldown_time))
	orange_cooldown_time = float(data.get("orange_cooldown_time", orange_cooldown_time))

	# --- Rebuild gold board with saved state ---
	regular_board.num_rows = int(data.get("regular_board_num_rows", regular_board.num_rows))
	regular_board.value_bonus = int(data.get("regular_board_value_bonus", regular_board.value_bonus))
	regular_board.orange_buckets_enabled = data.get("regular_board_orange_buckets_enabled", regular_board.orange_buckets_enabled)
	regular_board._build_board()

	# Update gold drain timer
	gold_drain_timer.wait_time = gold_cooldown_time
	if gold_queue.size() > 0:
		gold_drain_timer.start()

	# Restore autodropper if it was active
	if autodropper_level > 0:
		autodropper_timer.wait_time = 10.0 / autodropper_level
		autodropper_timer.start()

	# Update orange drain timer
	orange_drain_timer.wait_time = orange_cooldown_time
	if orange_queue > 0:
		orange_drain_timer.start()

	# --- Restore orange board if it was unlocked ---
	# Clear the flag so _check_unlock_orange_board() doesn't early-return
	if orange_board_unlocked:
		orange_board_unlocked = false
		_check_unlock_orange_board()
		if orange_board:
			orange_board.num_rows = int(data.get("orange_board_num_rows", orange_board.num_rows))
			orange_board.value_bonus = int(data.get("orange_board_value_bonus", orange_board.value_bonus))
			orange_board.red_buckets_enabled = data.get("orange_board_red_buckets_enabled", orange_board.red_buckets_enabled)
			orange_board._build_board()

	# --- Restore red board if it was unlocked ---
	if red_board_unlocked:
		red_board_unlocked = false
		_check_unlock_red_board()
		if red_board:
			red_board.num_rows = int(data.get("red_board_num_rows", red_board.num_rows))
			red_board.value_bonus = int(data.get("red_board_value_bonus", red_board.value_bonus))
			red_board._build_board()

	# --- Refresh all UI ---
	if player_level >= 8:
		ui.show_coin_max = true
	if regular_board.orange_buckets_enabled:
		ui.show_unrefined_orange()
		ui.show_drop_unrefined_button()
		ui.update_unrefined_orange(unrefined_orange)
	ui.update_coins(coin_total, coin_max)
	if orange_board_unlocked:
		ui.update_orange_coins(orange_coin_total)
	if red_board_unlocked:
		ui.update_red_coins(red_coin_total)
	_update_level_label()
	_refresh_upgrade_panel()
	_update_queue_visual()
