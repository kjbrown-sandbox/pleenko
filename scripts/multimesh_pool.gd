class_name MultiMeshPool
extends RefCounted

## Fixed-slot MultiMesh with a free-index stack — the shared mechanic behind
## every pooled particle/instance field (coins, drop bursts, …).
##
## Slots are handed out by `acquire()` and returned by `release()`. A released
## slot is parked off-screen at zero scale rather than removed, so instance
## count stays stable and no allocation happens per particle.

## Off-screen, zero-scale — where a free slot parks.
static func hidden() -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -9999, 0))

var instance: MultiMeshInstance3D
var _free: Array[int] = []


## Builds the MultiMeshInstance3D and parents it. All slots start free.
func create(parent: Node, mesh: Mesh, material: Material, capacity: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = capacity
	for i in capacity:
		mm.set_instance_transform(i, hidden())

	instance = MultiMeshInstance3D.new()
	instance.multimesh = mm
	instance.material_override = material
	parent.add_child(instance)

	# Reverse order so pop_back hands out the lowest index first.
	for i in range(capacity - 1, -1, -1):
		_free.append(i)


func multimesh() -> MultiMesh:
	return instance.multimesh


func is_exhausted() -> bool:
	return _free.is_empty()


## Returns a free slot index, or -1 when exhausted. With `grow_if_empty` the
## pool doubles instead of failing.
func acquire(grow_if_empty: bool = false) -> int:
	if _free.is_empty():
		if not grow_if_empty:
			return -1
		grow()
	return _free.pop_back()


func release(idx: int) -> void:
	multimesh().set_instance_transform(idx, hidden())
	_free.append(idx)


func set_slot(idx: int, xform: Transform3D, color: Color) -> void:
	var mm := multimesh()
	mm.set_instance_transform(idx, xform)
	mm.set_instance_color(idx, color)


## Doubles capacity, preserving live slots. Godot has no in-place resize that
## keeps data, so existing transforms/colors are copied across.
func grow() -> void:
	var mm := multimesh()
	var old_count: int = mm.instance_count
	var new_count: int = old_count * 2

	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in old_count:
		xforms.append(mm.get_instance_transform(i))
		colors.append(mm.get_instance_color(i))

	mm.instance_count = new_count

	for i in old_count:
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	for i in range(old_count, new_count):
		mm.set_instance_transform(i, hidden())
	for i in range(new_count - 1, old_count - 1, -1):
		_free.append(i)
