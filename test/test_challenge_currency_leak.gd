extends "res://test/test_base.gd"

## Reproduction for the challenge-start currency leak.
##
## Root cause under test: SceneManager.set_new_scene() runs a 1s fade during
## which the OUTGOING gameplay scene is never paused, then swaps at the fade
## midpoint. So the outgoing scene keeps crediting the shared CurrencyManager
## autoload right up to (and, in the swap-frame overlap, past) the moment the
## incoming challenge scene resets currency and the tracker subscribes. That
## stray currency is what shows up as "weird starting currency", auto-wins
## CoinGoal challenges, and prematurely trips board-unlock thresholds.
##
## This drives the REAL SceneManager.set_new_scene() with a stand-in outgoing
## scene (currency_leak_source.gd) that mints gold every _process frame, the
## way a landing coin does. Fix #1 disables the outgoing scene's process at
## transition start, so it must mint nothing from the instant the transition
## begins.
##
## Run with: godot --headless --scene res://test/test_challenge_currency_leak.tscn

const LeakSource := preload("res://test/currency_leak_source.gd")


func _run_tests() -> void:
	print("\n=== Challenge Currency Leak Tests ===\n")
	await test_outgoing_scene_is_frozen_during_transition()


## Builds a throwaway empty scene to transition INTO (stands in for the incoming
## challenge scene). Packed at runtime so no stray .tscn lands in test/ for
## run_all.sh to execute.
func _make_empty_incoming_scene() -> PackedScene:
	var root := Node.new()
	root.name = "IncomingScene"
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps


func test_outgoing_scene_is_frozen_during_transition() -> void:
	print("test_outgoing_scene_is_frozen_during_transition")

	# Let the SceneTree finish setting up the launched scene before we start
	# reparenting — add_child on root fails while the tree is "busy" (still in
	# the initial _ready pass).
	await get_tree().process_frame

	# Stand-in outgoing gameplay scene: minting gold every process frame.
	var leaky := Node.new()
	leaky.set_script(LeakSource)
	get_tree().root.add_child(leaky)
	# set_new_scene() operates on get_tree().current_scene — make the leaky node
	# the outgoing scene it will fade out and free.
	var prior_scene := get_tree().current_scene
	get_tree().current_scene = leaky

	# Clean starting currency, then start minting (the "autodroppers running when
	# the player taps a challenge" state).
	CurrencyManager.reset()
	CurrencyManager.caps[Enums.CurrencyType.GOLD_COIN] = 1_000_000_000
	LeakSource.total_process_frames = 0
	LeakSource.total_gold_minted = 0
	leaky.minting = true
	var gold_before: int = CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN)

	# Kick off the real transition and let it run past the fade-out midpoint
	# (the swap happens at ~1.0s; the outgoing scene is queue_free'd there).
	SceneManager.set_new_scene(_make_empty_incoming_scene(), false)
	await get_tree().create_timer(1.5).timeout

	var frames: int = LeakSource.total_process_frames
	var gold_leaked: int = CurrencyManager.get_balance(Enums.CurrencyType.GOLD_COIN) - gold_before
	print("  [repro] outgoing scene processed %d frames and minted %d gold DURING the transition" \
		% [frames, gold_leaked])

	assert_equal(frames, 0, "outgoing scene must not process once the transition starts")
	assert_equal(gold_leaked, 0, "outgoing scene must not credit currency once the transition starts")

	# Cleanup: the leaky node was freed by the transition; drop the incoming scene
	# and restore whatever current_scene we displaced.
	var incoming := get_tree().current_scene
	if is_instance_valid(incoming) and incoming != prior_scene:
		incoming.queue_free()
	if is_instance_valid(prior_scene):
		get_tree().current_scene = prior_scene
