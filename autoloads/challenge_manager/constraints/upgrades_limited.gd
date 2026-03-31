class_name UpgradesLimited
extends ChallengeConstraint

@export var all_upgrades: bool = false
@export var blocked_upgrades: Array[Enums.UpgradeType] = []

func get_text() -> String:
	if all_upgrades:
		return "No upgrades"
	var names: PackedStringArray = []
	for ut in blocked_upgrades:
		names.append(FormatUtils.upgrade_name(ut))
	return "No %s upgrades" % ", ".join(names)
