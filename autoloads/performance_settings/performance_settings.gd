extends Node

## Owns the player's display/performance preferences (frame-rate cap, window
## mode). Each pref is applied at startup and on every change, then persisted by
## SaveManager. Treated as device preferences (like audio), so they survive
## prestige and full resets.

const FPS_OPTIONS: Array[int] = [30, 60, 120, 144]
const DEFAULT_MAX_FPS: int = 120

## Window-mode prefs are the Godot Window.MODE_* enum values stored directly —
## no translation layer. WINDOWED + borderless FULLSCREEN are the only options
## offered; exclusive-fullscreen is deliberately omitted (alt-tab and resolution
## flicker make it a worse fit for a casual idle game).
const WINDOW_MODE_OPTIONS: Array[int] = [Window.MODE_WINDOWED, Window.MODE_FULLSCREEN]
const DEFAULT_WINDOW_MODE: int = Window.MODE_FULLSCREEN

var _max_fps: int = DEFAULT_MAX_FPS
var _window_mode: int = DEFAULT_WINDOW_MODE


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


## Sets the window mode. `mode` is snapped to a known option (same defensive
## pattern as `set_max_fps`) so a stale save can never push the game into an
## unsupported / unintended window state.
func set_window_mode(mode: int) -> void:
	_window_mode = mode if mode in WINDOW_MODE_OPTIONS else DEFAULT_WINDOW_MODE
	_apply()


func get_window_mode() -> int:
	return _window_mode


## Disabling V-Sync makes the cap authoritative on every display — with V-Sync
## on, the monitor's refresh rate would re-pin the frame rate and a sub-refresh
## cap (e.g. 30) would not take effect. Skipped under the headless display
## driver (tests) where there is no window to configure.
##
## Window mode has an additional web guard: the browser Fullscreen API only
## honours requests issued from a real user gesture, so applying a saved
## fullscreen preference on startup would silently fail. The OptionsDialog row
## is hidden on web for the same reason — the saved value just sits dormant
## until the player returns to a desktop build.
func _apply() -> void:
	Engine.max_fps = _max_fps
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		if not OS.has_feature("web"):
			get_window().mode = _window_mode
