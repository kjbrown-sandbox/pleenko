extends Node3D

@onready var ui: CanvasLayer = $UI
@onready var board: Node3D = $Board
@onready var camera: Camera3D = $Camera3D

var coin_scene: PackedScene = preload("res://scenes/coin.tscn")
var coin_total: int = 0
var num_rows: int = 0

# Board layout constants
const PEG_SPACING_X := 1.0
const ROW_SPACING_Y := 0.8
const TOP_Y := 3.0
const BUCKET_OFFSET_Y := 0.6  # how far below last peg row the buckets sit
const LABEL_OFFSET_Y := 0.35  # how far below bucket center the value label sits

# Shared mesh resources (created once, reused for every peg/bucket)
var peg_mesh: CylinderMesh
var bucket_mesh: BoxMesh


func _ready() -> void:
	peg_mesh = CylinderMesh.new()
	peg_mesh.top_radius = 0.15
	peg_mesh.bottom_radius = 0.15
	peg_mesh.height = 0.3

	bucket_mesh = BoxMesh.new()
	bucket_mesh.size = Vector3(PEG_SPACING_X * 0.9, 0.3, 0.5)

	# Build the initial board with 1 row so there's something to see
	num_rows = 1
	_build_board()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("drop_coin"):
		_drop_coin()
	elif event.is_action_pressed("expand_board"):
		_expand_board()


func _expand_board() -> void:
	num_rows += 1
	_build_board()


func _drop_coin() -> void:
	if num_rows == 0:
		return

	# Simulate coin path through the rows
	var waypoints: Array[Vector3] = []
	var col_index := 0

	for r in range(num_rows):
		if randf() < 0.5:
			col_index += 1
		waypoints.append(_peg_position(r, col_index))

	# Final waypoint: the bucket the coin lands in
	var value := _bucket_value(col_index)
	waypoints.append(_bucket_position(col_index))

	# Spawn coin above the first peg
	var coin: Node3D = coin_scene.instantiate()
	coin.position = Vector3(0.0, TOP_Y + 0.8, 0.0)
	add_child(coin)

	coin.landed.connect(_on_coin_landed)
	coin.animate(waypoints, value)


func _build_board() -> void:
	# Clear previous board
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
		board.add_child(bucket)

		var label := Label3D.new()
		label.text = str(_bucket_value(i))
		label.font_size = 48
		label.position = _bucket_position(i) + Vector3(0.0, -LABEL_OFFSET_Y, 0.01)
		board.add_child(label)

	_adjust_camera()


func _peg_position(row: int, index: int) -> Vector3:
	# Row r has (r+1) pegs, centered around x=0
	var x := (index - row / 2.0) * PEG_SPACING_X
	var y := TOP_Y - row * ROW_SPACING_Y
	return Vector3(x, y, 0.0)


func _bucket_position(index: int) -> Vector3:
	# Buckets sit below the last peg row, same spacing logic as a row with num_rows pegs
	var x := (index - num_rows / 2.0) * PEG_SPACING_X
	var y := TOP_Y - num_rows * ROW_SPACING_Y - BUCKET_OFFSET_Y
	return Vector3(x, y, 0.0)


func _bucket_value(index: int) -> int:
	# Edge buckets are worth more (harder to reach), center is worth 1
	var center := num_rows / 2.0
	return int(absf(index - center)) + 1


func _adjust_camera() -> void:
	var top := TOP_Y + 0.8
	var bottom := TOP_Y - num_rows * ROW_SPACING_Y - BUCKET_OFFSET_Y
	var center_y := (top + bottom) / 2.0
	var board_height := top - bottom
	var z_distance := maxf(6.0, board_height * 0.9)
	camera.position = Vector3(0.0, center_y, z_distance)


func _on_coin_landed(bucket_value: int) -> void:
	coin_total += bucket_value
	ui.update_coins(coin_total)
