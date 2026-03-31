extends Node

enum ChallengeState { LOCKED, UNLOCKED, COMPLETED }

signal challenge_state_changed(challenge_id: String, new_state: ChallengeState)
signal unlock_granted(unlock_type: ChallengeRewardData.UnlockType)

var _states: Dictionary = {}                          # challenge_id -> ChallengeState
var _rewards_claimed: Dictionary = {}                 # challenge_id -> bool
var _unlocks: Dictionary = {}                         # UnlockType -> bool
var _starting_modifiers: Array[ChallengeRewardData] = []


func initialize(buttons: Array[ChallengeButton]) -> void:
	# Find root challenges (not referenced in any next_challenges)
	var all_next_ids: Dictionary = {}
	for btn in buttons:
		for next_id in btn.next_challenges:
			all_next_ids[next_id] = true

	for btn in buttons:
		var id := btn.challenge_ui_name
		if _states.has(id):
			# Already loaded from save — just update the button visual
			btn.set_state(_states[id])
			continue
		if all_next_ids.has(id):
			_states[id] = ChallengeState.LOCKED
		else:
			_states[id] = ChallengeState.UNLOCKED
		btn.set_state(_states[id])

	# Propagate unlocks from completed challenges to their next challenges.
	# This handles new challenges added after a save was created.
	for btn in buttons:
		if _states.get(btn.challenge_ui_name, ChallengeState.LOCKED) == ChallengeState.COMPLETED:
			for next_id in btn.next_challenges:
				if _states.get(next_id, ChallengeState.LOCKED) == ChallengeState.LOCKED:
					_states[next_id] = ChallengeState.UNLOCKED
	for btn in buttons:
		btn.set_state(_states.get(btn.challenge_ui_name, ChallengeState.LOCKED))


func get_state(challenge_id: String) -> ChallengeState:
	return _states.get(challenge_id, ChallengeState.LOCKED)


func is_unlocked(unlock_type: ChallengeRewardData.UnlockType) -> bool:
	return _unlocks.get(unlock_type, false)


func get_starting_modifiers() -> Array[ChallengeRewardData]:
	return _starting_modifiers


func get_bonus_multi_drop(board_type: Enums.BoardType) -> int:
	var bonus := 0
	for mod in _starting_modifiers:
		if mod.modifier_type == ChallengeRewardData.ModifierType.MULTI_DROP and mod.board_type == board_type:
			bonus += mod.modifier_amount
	return bonus


func get_advanced_coin_multiplier_bonus(board_type: Enums.BoardType) -> float:
	var bonus := 0.0
	for mod in _starting_modifiers:
		if mod.modifier_type == ChallengeRewardData.ModifierType.ADVANCED_COIN_MULTIPLIER and mod.board_type == board_type:
			bonus += mod.modifier_amount
	return bonus


func get_earliest_incomplete(buttons: Array[ChallengeButton]) -> ChallengeButton:
	for btn in buttons:
		var state := get_state(btn.challenge_ui_name)
		if state == ChallengeState.UNLOCKED:
			return btn
	# All completed or all locked — return first completed, or first button
	for btn in buttons:
		if get_state(btn.challenge_ui_name) == ChallengeState.COMPLETED:
			return btn
	if not buttons.is_empty():
		return buttons[0]
	return null


func complete_challenge(challenge_id: String, next_ids: Array[String], rewards: Array[ChallengeRewardData]) -> void:
	_states[challenge_id] = ChallengeState.COMPLETED
	challenge_state_changed.emit(challenge_id, ChallengeState.COMPLETED)

	# Unlock next challenges
	for next_id in next_ids:
		if _states.get(next_id, ChallengeState.LOCKED) == ChallengeState.LOCKED:
			_states[next_id] = ChallengeState.UNLOCKED
			challenge_state_changed.emit(next_id, ChallengeState.UNLOCKED)

	# Grant rewards (one-time only)
	if _rewards_claimed.get(challenge_id, false):
		return
	_rewards_claimed[challenge_id] = true

	for reward in rewards:
		match reward.type:
			ChallengeRewardData.RewardType.UNLOCK:
				_unlocks[reward.unlock_type] = true
				unlock_granted.emit(reward.unlock_type)
			ChallengeRewardData.RewardType.STARTING_MODIFIER:
				_starting_modifiers.append(reward)


func serialize() -> Dictionary:
	var states_data := {}
	for id in _states:
		states_data[id] = _states[id]

	var claimed_data := {}
	for id in _rewards_claimed:
		claimed_data[id] = _rewards_claimed[id]

	var unlocks_data: Array[int] = []
	for unlock_type in _unlocks:
		if _unlocks[unlock_type]:
			unlocks_data.append(unlock_type)

	var modifiers_data: Array[Dictionary] = []
	for mod in _starting_modifiers:
		modifiers_data.append({
			"type": mod.type,
			"modifier_type": mod.modifier_type,
			"modifier_amount": float(mod.modifier_amount),
			"currency_type": mod.currency_type,
			"board_type": mod.board_type,
		})

	return {
		"states": states_data,
		"rewards_claimed": claimed_data,
		"unlocks": unlocks_data,
		"modifiers": modifiers_data,
	}


func deserialize(data: Dictionary) -> void:
	_states.clear()
	_rewards_claimed.clear()
	_unlocks.clear()
	_starting_modifiers.clear()

	var states_data: Dictionary = data.get("states", {})
	for id in states_data:
		_states[id] = states_data[id] as ChallengeState

	var claimed_data: Dictionary = data.get("rewards_claimed", {})
	for id in claimed_data:
		_rewards_claimed[id] = claimed_data[id]

	var unlocks_data: Array = data.get("unlocks", [])
	for unlock_int in unlocks_data:
		_unlocks[unlock_int as ChallengeRewardData.UnlockType] = true

	var modifiers_data: Array = data.get("modifiers", [])
	for mod_dict in modifiers_data:
		var mod := ChallengeRewardData.new()
		mod.type = mod_dict.get("type", 0)
		mod.modifier_type = mod_dict.get("modifier_type", 0)
		mod.modifier_amount = mod_dict.get("modifier_amount", 1)
		mod.currency_type = mod_dict.get("currency_type", 0)
		mod.board_type = mod_dict.get("board_type", 0)
		_starting_modifiers.append(mod)
