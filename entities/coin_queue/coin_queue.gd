class_name CoinQueue
extends Node3D

## FIFO coin queue. Coins can be FULL (ready to drop) or FILLING (autodrop pie
## animation). FULL coins sit before FILLING coins, but within each group the
## order is strictly insertion order — no advanced-before-normal priority.

const CoinScene: PackedScene = preload("res://entities/coin/coin.tscn")

signal coin_enqueued(index: int, coin_type: Enums.CurrencyType)
signal coin_dequeued()
signal capacity_changed(cap: int)

## Where the first coin in the queue sits (local to this node).
@export var start_position: Vector3 = Vector3(-1, sqrt(3)/2 + 0.2, 0)
## Spacing between coins along the X axis.
@export var coin_spacing: float = 0.20
## How long it takes a coin to tween to its new slot.
@export var slide_time: float = 0.15
## Tilt coins so their face is visible.
@export var coin_rotation: Vector3 = Vector3(0, 0, 0)

var _capacity: int = 0
var _coins: Array[Coin] = []

# 3D visual indicators for empty slots
var _empty_slot_meshes: Array[MeshInstance3D] = []
var _empty_slot_shader: Shader = preload("res://entities/coin/coin_empty_slot.gdshader")

## Returns the number of coins currently in the queue (FULL + FILLING).
var count: int:
	get: return _coins.size()

var capacity: int:
	get: return _capacity


func setup(_start_position: Vector3) -> void:
	start_position = _start_position


func set_capacity(new_capacity: int) -> void:
	_capacity = new_capacity
	_refresh_empty_slots()
	capacity_changed.emit(_capacity)


func is_full() -> bool:
	return _coins.size() >= _capacity


func is_empty() -> bool:
	return _coins.is_empty()


func has_queue() -> bool:
	return _capacity > 0


func enqueue(coin: Coin, is_advanced: bool = false) -> void:
	if is_full():
		return

	coin.is_advanced = is_advanced

	# FULL coins go before FILLING coins (FIFO within each group).
	var insert_idx: int
	if coin.fill_state == Coin.FillState.FULL:
		insert_idx = _find_first_filling_index()
	else:
		insert_idx = _coins.size()

	coin.position = _slot_position(insert_idx)
	coin.rotation = coin_rotation
	add_child(coin)
	coin._apply_visuals()
	_coins.insert(insert_idx, coin)
	_slide_coins_from(insert_idx + 1)
	coin_enqueued.emit(insert_idx, coin.coin_type)


## Find the index of the first FILLING coin. Returns _coins.size() if none.
func _find_first_filling_index() -> int:
	for i in _coins.size():
		if _coins[i].fill_state == Coin.FillState.FILLING:
			return i
	return _coins.size()


func dequeue() -> Coin:
	if is_empty():
		return null

	var coin: Coin = _coins.pop_front()
	remove_child(coin)
	_slide_all_forward()
	coin_dequeued.emit()
	return coin


## Dequeue only FULL coins (skip FILLING). Returns null if no FULL coin is ready.
func dequeue_full() -> Coin:
	for i in _coins.size():
		if _coins[i].fill_state == Coin.FillState.FULL:
			var coin: Coin = _coins[i]
			_coins.remove_at(i)
			remove_child(coin)
			_slide_all_forward()
			coin_dequeued.emit()
			return coin
	return null


## Complete the first FILLING coin of the given type: transition it to FULL,
## remove it from the queue, and return it. Returns null if none found.
func complete_first_filling(is_advanced: bool) -> Coin:
	for i in _coins.size():
		var c: Coin = _coins[i]
		if c.fill_state == Coin.FillState.FILLING and c.is_advanced == is_advanced:
			c.complete_fill()
			_coins.remove_at(i)
			remove_child(c)
			_slide_all_forward()
			coin_dequeued.emit()
			return c
	return null


## Atomically: complete first FILLING coin → move it to the FULL section →
## add a replacement FILLING coin. Single slide pass at the end so no
## overlapping tweens. Returns the completed coin, or null if none found.
func complete_and_requeue_filling(is_advanced: bool) -> Coin:
	var fill_idx: int = -1
	for i in _coins.size():
		var c: Coin = _coins[i]
		if c.fill_state == Coin.FillState.FILLING and c.is_advanced == is_advanced:
			fill_idx = i
			break
	if fill_idx < 0:
		return null

	var coin: Coin = _coins[fill_idx]
	coin.complete_fill()

	# Remove from current position (no slide yet)
	_coins.remove_at(fill_idx)

	# Insert at the end of the FULL section (FIFO)
	var insert_idx: int = _find_first_filling_index()
	_coins.insert(insert_idx, coin)

	# Add a replacement FILLING coin at the end (no slide yet)
	if not is_full():
		var replacement: Coin = CoinScene.instantiate()
		replacement.coin_type = coin.coin_type
		replacement.multiplier = coin.multiplier
		replacement.is_advanced = is_advanced
		replacement.fill_state = Coin.FillState.FILLING
		replacement.fill_progress = 0.0
		var rep_idx: int = _coins.size()
		replacement.position = _slot_position(rep_idx)
		replacement.rotation = coin_rotation
		add_child(replacement)
		replacement._apply_visuals()
		_coins.append(replacement)

	# Single slide pass for all coins
	_slide_all_forward()
	return coin


## Get the world-space position for a given slot index.
func get_overflow_position() -> Vector3:
	return start_position + Vector3(-_capacity * coin_spacing - 0.05, 0, 0.02)


## Create and enqueue a FILLING coin for autodrop visual.
func add_filling_coin(coin_type: Enums.CurrencyType, is_advanced: bool, coin_multiplier: float = 1.0) -> Coin:
	if is_full():
		return null
	var coin: Coin = CoinScene.instantiate()
	coin.coin_type = coin_type
	coin.multiplier = coin_multiplier
	coin.fill_state = Coin.FillState.FILLING
	coin.fill_progress = 0.0
	enqueue(coin, is_advanced)
	return coin


## Remove FILLING coins of the given type. If max_remove <= 0, removes all.
func remove_filling_coins_of_type(is_advanced: bool, max_remove: int = 0) -> void:
	var removed: int = 0
	var i: int = _coins.size() - 1
	while i >= 0:
		if max_remove > 0 and removed >= max_remove:
			break
		var coin: Coin = _coins[i]
		if coin.fill_state == Coin.FillState.FILLING and coin.is_advanced == is_advanced:
			_coins.remove_at(i)
			remove_child(coin)
			coin.queue_free()
			removed += 1
		i -= 1
	_slide_all_forward()


## Count FILLING coins of a given type.
func get_filling_count(is_advanced: bool) -> int:
	var n: int = 0
	for coin in _coins:
		if coin.fill_state == Coin.FillState.FILLING and coin.is_advanced == is_advanced:
			n += 1
	return n


## Update fill_progress on all FILLING coins.
func update_filling_progress(progress: float) -> void:
	for coin in _coins:
		if coin.fill_state == Coin.FillState.FILLING:
			coin.set_fill(progress)


func _slot_position(index: int) -> Vector3:
	return start_position + Vector3(-index * coin_spacing, 0, 0)


## Tween all coins to their correct positions.
func _slide_all_forward() -> void:
	_slide_coins_from(0)


## Tween coins from start_index onward to their correct slot positions.
func _slide_coins_from(start_index: int) -> void:
	for i in range(start_index, _coins.size()):
		var target: Vector3 = _slot_position(i)
		if _coins[i].position.distance_to(target) > 0.001:
			var tween: Tween = create_tween()
			tween.tween_property(_coins[i], "position", target, slide_time) \
				.set_trans(Tween.TRANS_LINEAR)


## Rebuild empty-slot ring meshes to match capacity. These are static backdrops
## at fixed positions — coins render in front of them, so no dynamic show/hide.
func _refresh_empty_slots() -> void:
	# Ensure we have exactly _capacity slot meshes
	while _empty_slot_meshes.size() > _capacity:
		var mesh_inst: MeshInstance3D = _empty_slot_meshes.pop_back()
		mesh_inst.queue_free()
	while _empty_slot_meshes.size() < _capacity:
		var mesh_inst: MeshInstance3D = _make_empty_slot_mesh()
		add_child(mesh_inst)
		_empty_slot_meshes.append(mesh_inst)
	# Position each at its fixed slot, slightly behind coins on Z
	for i in _empty_slot_meshes.size():
		_empty_slot_meshes[i].position = _slot_position(i) + Vector3(0, 0, -0.01)


func _make_empty_slot_mesh() -> MeshInstance3D:
	var t: VisualTheme = ThemeProvider.theme
	var mesh_inst := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var slot_size: float = t.coin_radius * 2.0
	quad.size = Vector2(slot_size, slot_size)
	mesh_inst.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = _empty_slot_shader
	mat.set_shader_parameter("ring_color", Color(t.normal_text_color, 0.25))
	mesh_inst.material_override = mat
	return mesh_inst
