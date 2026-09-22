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
	_load_device_prefs()
	_apply()
	# The OS window is not fully realized while autoloads run, so the mode check
	# in _apply() can compare against a value the window has not settled into
	# yet — it then decides nothing needs writing and the engine's own startup
	# sizing wins. Re-apply once a frame has been processed, when get_window()
	# reports the real mode. Cheap, and a no-op when the first pass was correct.
	await get_tree().process_frame
	_apply()


## Read the persisted display prefs straight from the save file at startup.
##
## These are device prefs, not game progress: SaveManager deliberately keeps
## them in the minimal save so they survive every reset. But SaveManager only
## pushes them into this autoload from load_game(), which runs when the GAME
## scene loads — not at launch, and not at all if the player sits on the main
## menu. Until then the window stayed on DEFAULT_WINDOW_MODE, so a player who
## had configured windowed still booted fullscreen every time.
##
## Reading them here makes the configured value authoritative from the first
## frame. Anything missing or malformed falls through to the setters, which snap
## unknown values to the defaults.
func _load_device_prefs() -> void:
	if not FileAccess.file_exists(SaveManager.SAVE_PATH):
		return
	var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	if "max_fps" in data:
		_max_fps = int(data["max_fps"]) if int(data["max_fps"]) in FPS_OPTIONS else DEFAULT_MAX_FPS
	if "window_mode" in data:
		var mode: int = int(data["window_mode"])
		_window_mode = mode if mode in WINDOW_MODE_OPTIONS else DEFAULT_WINDOW_MODE


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
##
## The window-mode assignment is guarded on an actual mode change. This autoload's
## _apply() runs during early init, before the OS window is fully realized;
## re-asserting fullscreen there (when the window already boots fullscreen via
## display/window/size/mode) left the window mis-sized and offset on Windows.
## Only writing get_window().mode when it differs means the boot-time fullscreen
## the engine created natively is left untouched, and later real transitions
## (Options toggle, a saved windowed pref) still apply. Mirrors the working
## windowed->fullscreen re-toggle players used as a manual fix.
func _apply() -> void:
	Engine.max_fps = _max_fps
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		if not OS.has_feature("web") and get_window().mode != _window_mode:
			get_window().mode = _window_mode
