extends "res://test/test_base.gd"

## Smoke tests for the two menu-audio instruments (MusicBox, PegTick) introduced
## alongside the menu peg-contact + chord-bed feature. Each verifies the
## instrument constructs, returns a non-null stream from resolve(), and is
## reachable via AudioManager's enum dispatch.
##
## Run with:
##   godot --headless --scene res://test/test_menu_instruments.tscn


func _run_tests() -> void:
	print("\n=== Menu Instruments Tests ===\n")
	test_music_box_resolve()
	test_peg_tick_resolve()
	test_audio_manager_dispatch_music_box()
	test_audio_manager_dispatch_peg_tick()


# --- Resolve smoke tests ---

func test_music_box_resolve() -> void:
	print("test_music_box_resolve")
	var m := MusicBox.new()
	var sp: Dictionary = m.resolve(1.0)
	assert_true(sp["stream"] != null, "MusicBox returns non-null stream at C4")
	assert_true(sp["pitch_scale"] > 0.0, "MusicBox returns positive pitch_scale")


func test_peg_tick_resolve() -> void:
	print("test_peg_tick_resolve")
	var pt := PegTick.new()
	var sp: Dictionary = pt.resolve(1.0)
	assert_true(sp["stream"] != null, "PegTick returns non-null stream")
	# PegTick is tone-less but should still pass pitch_mult through so MenuBoard
	# can vary the perceived "material size" per hit.
	assert_equal(sp["pitch_scale"], 1.0, "PegTick passes through pitch_mult = 1.0")
	var sp_hi: Dictionary = pt.resolve(1.5)
	assert_equal(sp_hi["pitch_scale"], 1.5, "PegTick passes through pitch_mult = 1.5")


# --- AudioManager dispatch — guards the enum → instance wiring ---

func test_audio_manager_dispatch_music_box() -> void:
	print("test_audio_manager_dispatch_music_box")
	var instr: Instrument = AudioManager._instrument_for(Instrument.Type.MUSIC_BOX)
	assert_true(instr != null, "MUSIC_BOX enum resolves to a non-null instrument")
	assert_true(instr is MusicBox, "MUSIC_BOX dispatches to a MusicBox")


func test_audio_manager_dispatch_peg_tick() -> void:
	print("test_audio_manager_dispatch_peg_tick")
	var instr: Instrument = AudioManager._instrument_for(Instrument.Type.PEG_TICK)
	assert_true(instr != null, "PEG_TICK enum resolves to a non-null instrument")
	assert_true(instr is PegTick, "PEG_TICK dispatches to a PegTick")
