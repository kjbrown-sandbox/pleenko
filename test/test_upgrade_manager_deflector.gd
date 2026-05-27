extends "res://test/test_base.gd"

## UpgradeManager × PEG_DEFLECTOR registration tests — run with:
##   godot --headless --scene res://test/test_upgrade_manager_deflector.tscn
##
## Regression coverage for adding PEG_DEFLECTOR to Enums.UpgradeType: it must be
## registered as a BaseUpgradeData .tres so _init_state creates state for it on
## every board (otherwise get_level KeyErrors on the coin/save paths), and it
## must round-trip through serialize/deserialize including old saves with no key.


func _run_tests() -> void:
	print("\n=== UpgradeManager Deflector Tests ===\n")
	test_state_exists_for_every_board()
	test_upgrade_data_registered()
	test_serialize_deserialize_round_trip()
	test_old_save_without_key_defaults_zero()


func test_state_exists_for_every_board() -> void:
	print("test_state_exists_for_every_board")
	UpgradeManager.reset()
	for board_type in Enums.BoardType.values():
		# These all index _state[board][PEG_DEFLECTOR]; a missing .tres would
		# leave that entry uncreated and KeyError here.
		assert_equal(UpgradeManager.get_level(board_type, Enums.UpgradeType.PEG_DEFLECTOR), 0,
			"level 0 on %s" % Enums.BoardType.keys()[board_type])
		assert_true(UpgradeManager.get_state(board_type, Enums.UpgradeType.PEG_DEFLECTOR) != null,
			"state exists on %s" % Enums.BoardType.keys()[board_type])
		assert_false(UpgradeManager.is_unlocked(board_type, Enums.UpgradeType.PEG_DEFLECTOR),
			"locked by default on %s" % Enums.BoardType.keys()[board_type])


func test_upgrade_data_registered() -> void:
	print("test_upgrade_data_registered")
	var data: BaseUpgradeData = UpgradeManager.get_upgrade(Enums.UpgradeType.PEG_DEFLECTOR)
	assert_true(data != null, "peg_deflector.tres is registered in the upgrades array")
	if data != null:
		assert_equal(data.type, Enums.UpgradeType.PEG_DEFLECTOR, "type matches enum")
		assert_equal(data.display_name, "Peg deflector", "display name")
		assert_true(data.max_level > 0, "has a slot cap")


func test_serialize_deserialize_round_trip() -> void:
	print("test_serialize_deserialize_round_trip")
	UpgradeManager.reset()
	UpgradeManager.get_state(Enums.BoardType.ORANGE, Enums.UpgradeType.PEG_DEFLECTOR).level = 4
	var blob := UpgradeManager.serialize()
	UpgradeManager.reset()
	assert_equal(UpgradeManager.get_level(Enums.BoardType.ORANGE, Enums.UpgradeType.PEG_DEFLECTOR), 0,
		"reset clears level")
	UpgradeManager.deserialize(blob)
	assert_equal(UpgradeManager.get_level(Enums.BoardType.ORANGE, Enums.UpgradeType.PEG_DEFLECTOR), 4,
		"level restored from save")


func test_old_save_without_key_defaults_zero() -> void:
	print("test_old_save_without_key_defaults_zero")
	UpgradeManager.reset()
	# A pre-deflector save: state dict has only ADD_ROW for GOLD.
	var legacy := {
		"state": {
			"GOLD": {
				"ADD_ROW": {"level": 2, "cost": 60, "delta": 0, "current_cap": 6, "cap_level": 0},
			}
		},
		"unlocked": {},
		"cap_raise_available": {},
	}
	UpgradeManager.deserialize(legacy)  # must not error on the missing key
	assert_equal(UpgradeManager.get_level(Enums.BoardType.GOLD, Enums.UpgradeType.PEG_DEFLECTOR), 0,
		"PEG_DEFLECTOR defaults to 0 on a legacy save")
	assert_equal(UpgradeManager.get_level(Enums.BoardType.GOLD, Enums.UpgradeType.ADD_ROW), 2,
		"existing upgrades still restore")
