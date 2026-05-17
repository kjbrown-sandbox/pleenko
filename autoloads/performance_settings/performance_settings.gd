extends Node

## Owns the player's display/performance preferences. Currently a single
## setting: the frame-rate cap. Applied at startup and on every change, then
## persisted by SaveManager. Treated as a device preference (like audio), so it
## survives prestige and full resets.

const FPS_OPTIONS: Array[int] = [30, 60, 120, 144]
const DEFAULT_MAX_FPS: int = 120

var _max_fps: int = DEFAULT_MAX_FPS


func _ready() -> void:
	_apply()


## Sets the frame-rate cap. `fps` is snapped to a known option (falling back to
## the default) so a stale or hand-edited save can never leave the game with an
## invalid or uncapped frame rate.
func set_max_fps(fps: int) -> void:
	_max_fps = fps if fps in FPS_OPTIONS else DEFAULT_MAX_FPS
	_apply()


func get_max_fps() -> int:
	return _max_fps


## Disabling V-Sync makes the cap authoritative on every display — with V-Sync
## on, the monitor's refresh rate would re-pin the frame rate and a sub-refresh
## cap (e.g. 30) would not take effect. Skipped under the headless display
## driver (tests) where there is no window to configure.
func _apply() -> void:
	Engine.max_fps = _max_fps
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
