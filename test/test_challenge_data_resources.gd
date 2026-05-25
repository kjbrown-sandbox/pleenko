extends "res://test/test_base.gd"

## Loads every challenge .tres file and asserts the typed sub-resource arrays
## deserialized cleanly. Guards against silent corruption when class names /
## paths shift (e.g. the NeverTouchBucket → ForbiddenBucketHazard migration).
## Run with: godot --headless --scene res://test/test_challenge_data_resources.tscn


const CHALLENGES_DIR := "res://data/challenges/"


func _run_tests() -> void:
	print("\n=== Challenge .tres Integrity ===\n")

	var dir := DirAccess.open(CHALLENGES_DIR)
	if not dir:
		printerr("  FAIL: could not open %s" % CHALLENGES_DIR)
		_fail_count += 1
		return

	dir.list_dir_begin()
	var file: String = dir.get_next()
	while file != "":
		# Godot import sidecars (.import) live next to .tres but aren't resources.
		if file.ends_with(".tres"):
			_check_file(CHALLENGES_DIR + file)
		file = dir.get_next()
	dir.list_dir_end()


func _check_file(path: String) -> void:
	print("checking %s" % path)
	var res: Resource = load(path)
	assert_true(res is ChallengeData, "%s loaded as ChallengeData" % path)
	if not res is ChallengeData:
		return
	var data: ChallengeData = res
	# Every entry in every typed array must be non-null. A silent drop (e.g.
	# class rename without .tres migration) shows up as a null sub-resource.
	for i in data.objectives.size():
		assert_true(data.objectives[i] != null, "%s objectives[%d] non-null" % [path, i])
	for i in data.constraints.size():
		assert_true(data.constraints[i] != null, "%s constraints[%d] non-null" % [path, i])
	for i in data.starting_conditions.size():
		assert_true(data.starting_conditions[i] != null, "%s starting_conditions[%d] non-null" % [path, i])
	for i in data.hazards.size():
		assert_true(data.hazards[i] != null, "%s hazards[%d] non-null" % [path, i])
	for i in data.rewards.size():
		assert_true(data.rewards[i] != null, "%s rewards[%d] non-null" % [path, i])
