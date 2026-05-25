class_name ChallengeHazard
extends Resource

## Authored data for a board hazard in a challenge. A ChallengeHazard is the
## sibling of objective / constraint / starting-condition: it describes a piece
## of dangerous board state (a forbidden bucket, a bomb, etc.) that operates
## independently of the main objective.
##
## Subclasses are Resources holding @export fields. The live behavior lives on
## ChallengeHazardRuntime — created via create_runtime() and parented to the
## ChallengeTracker so it gets _process + lifecycle for free.


## Returns a fresh ChallengeHazardRuntime instance configured to drive this
## hazard. Subclasses must override.
func create_runtime() -> ChallengeHazardRuntime:
	push_error("ChallengeHazard subclass %s must override create_runtime()" % get_class())
	return null


## Player-facing description, shown in the challenge info panel alongside
## constraint text.
func get_text() -> String:
	return ""
