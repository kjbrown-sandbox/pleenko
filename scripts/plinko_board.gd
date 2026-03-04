class_name PlinkoBoard
extends Node3D

enum BoardType { GOLD, ORANGE, RED }
enum BucketType { GOLD, ORANGE, RED }

signal coin_landed(value: int, bucket_type: BucketType)
signal drop_requested
signal board_rebuilt

@export var board_type: BoardType = BoardType.GOLD

# Board layout constants
const PEG_SPACING_X := 1.0
const ROW_SPACING_Y := 0.8
const TOP_Y := 3.0
const BUCKET_OFFSET_Y := 0.6
const LABEL_OFFSET_Y := 0.35
const ORANGE_THRESHOLD := 4
const RED_THRESHOLD := 7
const ORANGE_ROW_GATE := 6
const RED_ROW_GATE := 12

var num_rows: int = 0
var value_bonus: int = 0
var holding_drop: bool = false

var coin_scene: PackedScene = preload("res://scenes/coin.tscn")

# Shared mesh resources (created once, reused for every peg/bucket)
var peg_mesh: CylinderMesh
var bucket_mesh: BoxMesh
var orange_material: StandardMaterial3D
var red_material: StandardMaterial3D

@onready var board: Node3D = $Board
@onready var click_area: StaticBody3D = $ClickArea
@onready var click_collision: CollisionShape3D = $ClickArea/CollisionShape3D


func _ready() -> void:
	peg_mesh = CylinderMesh.new()
	peg_mesh.top_radius = 0.15
	peg_mesh.bottom_radius = 0.15
	peg_mesh.height = 0.3

	bucket_mesh = BoxMesh.new()
	bucket_mesh.size = Vector3(PEG_SPACING_X * 0.9, 0.3, 0.5)

	orange_material = StandardMaterial3D.new()
	orange_material.albedo_color = Color.ORANGE

	red_material = StandardMaterial3D.new()
	red_material.albedo_color = Color.RED

	click_area.input_event.connect(_on_click_area_input_event)


func _process(_delta: float) -> void:
	if holding_drop:
		drop_requested.emit()


func _on_click_area_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		holding_drop = event.pressed


func drop_coin() -> bool:
	if num_rows == 0:
		return false

	# Simulate coin path through the rows
	var waypoints: Array[Vector3] = []
	var col_index := 0

	for r in range(num_rows):
		if randf() < 0.5:
			col_index += 1
		waypoints.append(_peg_position(r, col_index))

	# Final waypoint: the bucket the coin lands in
	var b_type := _bucket_type(col_index)
	var reward := _reward_value(col_index)
	waypoints.append(_bucket_position(col_index))

	# Convert waypoints from board-local to global coordinates
	for i in range(waypoints.size()):
		waypoints[i] = to_global(waypoints[i])

	# Spawn coin above the first peg
	var coin: Node3D = coin_scene.instantiate()
	coin.position = to_global(Vector3(0.0, TOP_Y + 0.8, 0.0))

	# Tint coin based on board type
	match board_type:
		BoardType.ORANGE:
			var mesh := coin.get_node("Mesh") as MeshInstance3D
			mesh.material_override = orange_material
		BoardType.RED:
			var mesh := coin.get_node("Mesh") as MeshInstance3D
			mesh.material_override = red_material

	# Add coin to the scene tree (parent will be the scene root)
	get_tree().root.add_child(coin)

	coin.landed.connect(func(_value: int): coin_landed.emit(reward, b_type))
	coin.animate(waypoints, reward)

	return true


func add_row() -> void:
	num_rows += 1
	_build_board()


func _build_board() -> void:
	# Clear previous board contents
	for child in board.get_children():
		child.queue_free()

	# Create pegs: row r has (r + 1) pegs
	for r in range(num_rows):
		for i in range(r + 1):
			var peg := MeshInstance3D.new()
			peg.mesh = peg_mesh
			peg.position = _peg_position(r, i)
			board.add_child(peg)

	# Create buckets and value labels: num_rows + 1 buckets below the last row
	for i in range(num_rows + 1):
		var bucket := MeshInstance3D.new()
		bucket.mesh = bucket_mesh
		bucket.position = _bucket_position(i)

		var b_type := _bucket_type(i)
		match b_type:
			BucketType.ORANGE:
				bucket.material_override = orange_material
			BucketType.RED:
				bucket.material_override = red_material

		board.add_child(bucket)

		var label := Label3D.new()
		label.font_size = 48
		label.position = _bucket_position(i) + Vector3(0.0, -LABEL_OFFSET_Y, 0.01)

		# On the gold board, orange/red buckets show letters; otherwise show numeric value
		if board_type == BoardType.GOLD:
			match b_type:
				BucketType.RED:
					label.text = "R"
				BucketType.ORANGE:
					label.text = "O"
				_:
					label.text = str(_display_value(i))
		else:
			label.text = str(_display_value(i))

		board.add_child(label)

	_update_click_area()
	board_rebuilt.emit()


func _update_click_area() -> void:
	var shape := BoxShape3D.new()
	var top := TOP_Y + 1.0
	var bottom := TOP_Y - num_rows * ROW_SPACING_Y - BUCKET_OFFSET_Y - 0.5
	var half_width := (num_rows / 2.0) * PEG_SPACING_X + 0.5
	var height := top - bottom
	shape.size = Vector3(half_width * 2.0, height, 1.0)

	click_collision.shape = shape
	click_collision.position = Vector3(0.0, (top + bottom) / 2.0, 0.0)


func get_bounds() -> Rect2:
	var top := TOP_Y + 1.0
	var bottom := TOP_Y - num_rows * ROW_SPACING_Y - BUCKET_OFFSET_Y - 0.5
	var half_width := (num_rows / 2.0) * PEG_SPACING_X + 0.5
	# Rect2(x, y, width, height) — use global position offset
	var gp := global_position
	return Rect2(gp.x - half_width, gp.y + bottom, half_width * 2.0, top - bottom)


func _peg_position(row: int, index: int) -> Vector3:
	var x := (index - row / 2.0) * PEG_SPACING_X
	var y := TOP_Y - row * ROW_SPACING_Y
	return Vector3(x, y, 0.0)


func _bucket_position(index: int) -> Vector3:
	var x := (index - num_rows / 2.0) * PEG_SPACING_X
	var y := TOP_Y - num_rows * ROW_SPACING_Y - BUCKET_OFFSET_Y
	return Vector3(x, y, 0.0)


func _bucket_value(index: int) -> int:
	var center := num_rows / 2.0
	return int(absf(index - center)) + 1


func _bucket_type(index: int) -> BucketType:
	# Non-gold boards always return their own type
	if board_type == BoardType.ORANGE:
		return BucketType.ORANGE
	if board_type == BoardType.RED:
		return BucketType.RED
	# Gold board: check thresholds AND row gates (red first since it's higher)
	var base := _bucket_value(index)
	if num_rows >= RED_ROW_GATE and base >= RED_THRESHOLD:
		return BucketType.RED
	if num_rows >= ORANGE_ROW_GATE and base >= ORANGE_THRESHOLD:
		return BucketType.ORANGE
	return BucketType.GOLD


func _display_value(index: int) -> int:
	# value_bonus only applies to gold-type buckets on the gold board
	if board_type == BoardType.GOLD and _bucket_type(index) == BucketType.GOLD:
		return _bucket_value(index) + value_bonus
	return _bucket_value(index)


func _reward_value(index: int) -> int:
	# Orange/red buckets on gold board always reward 1 (of their currency)
	if board_type == BoardType.GOLD and _bucket_type(index) != BucketType.GOLD:
		return 1
	return _display_value(index)
