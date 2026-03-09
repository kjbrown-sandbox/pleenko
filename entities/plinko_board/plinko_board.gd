extends Node3D

@export var num_rows: int = 2
@export var space_between_pegs: float = 1.0

const PegScene := preload("res://entities/peg/peg.tscn")
const BucketScene: PackedScene = preload("res://entities/bucket/bucket.tscn")

@onready var pegs_container: Node3D = $Pegs
@onready var buckets_container: Node3D = $Buckets

func _ready() -> void:
	build_board()

func build_board() -> void:
	for child in pegs_container.get_children():
		child.queue_free()

	for child in buckets_container.get_children():
		child.queue_free()

	for i in range(num_rows):
		var x_offset = -i * space_between_pegs / 2
		var y = -space_between_pegs * (i - 1) * sqrt(3) / 2 # sqrt because of the 30/60/90 triangle babyyyy
		for j in range(i + 1):
			var peg = PegScene.instantiate()
			peg.position = Vector3(x_offset + (j * space_between_pegs), y, 0)
			pegs_container.add_child(peg)

	var num_buckets = num_rows + 1
	for i in range(num_buckets):
		var x_offset = -space_between_pegs * (num_buckets - 1) / 2
		var bucket = BucketScene.instantiate()
		bucket.position = Vector3(x_offset + (i * space_between_pegs), -space_between_pegs * (num_rows - 1) + space_between_pegs * 0.2, 0)
		buckets_container.add_child(bucket)
