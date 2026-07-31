extends Node
## Test helper — stands in for the outgoing gameplay scene during a
## SceneManager transition. Every _process frame it credits the shared
## CurrencyManager exactly the way a landing coin / autodropper does in the
## real board. Used by test_challenge_currency_leak to prove whether the
## outgoing scene keeps mutating currency across a set_new_scene() transition
## (the challenge-start currency leak) and that fix #1 freezes it.
##
## NOT a .tscn, so test/run_all.sh (which globs test/*.tscn) never runs it.

## Static so the count survives this node being queue_free'd by the transition.
static var total_process_frames: int = 0
static var total_gold_minted: int = 0

const MINT_PER_FRAME := 5

var minting: bool = false


func _process(_delta: float) -> void:
	if not minting:
		return
	total_process_frames += 1
	total_gold_minted += MINT_PER_FRAME
	CurrencyManager.add(Enums.CurrencyType.GOLD_COIN, MINT_PER_FRAME)
