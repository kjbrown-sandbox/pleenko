# Web Audio Debugging — Godot 4.6.1

## Summary

Godot 4.6.1 web exports have a critical bug: **calling `AudioServer.add_bus()` at runtime silently kills all audio output on web**. The buses appear to create successfully (they show up in `AudioServer.bus_count`, are not muted, have correct volume), and `AudioStreamPlayer.playing` reports `true` — but no sound reaches the browser's speakers. This affects both multi-threaded and single-threaded builds, all browsers (Chrome, Safari), and happens regardless of whether bus effects are attached.

### The Fix

Skip `AudioServer.add_bus()` on web entirely. Route all AudioStreamPlayers to the Master bus instead of custom buses (Melody, Click, Ambient, Drones). The `_bus()` helper method returns `&"Master"` on web and the real bus name on native.

Audio effects (compressor, reverb, low-pass) are also skipped on web as a consequence, but these are known to be unsupported in Godot's web audio pipeline anyway.

### What Still Works on Web

- Preloaded audio files (`.mp3`, `.wav`) via `AudioStreamPlayer`
- Runtime-generated `AudioStreamWAV` buffers (the procedural harp, triangle, kick, drums)
- Multiple AudioStreamPlayers (130+) on the Master bus
- Custom HTML shell with AudioContext resume workaround (needed for multi-threaded builds)

---

## Debugging Process

### 1. Initial Setup — Butler + Build Script

Created `build.sh` to automate Godot headless export → Butler push to itch.io. Discovered the user had installed the wrong `butler` (a macOS keyboard utility via `brew install butler` cask) instead of itch.io's CLI tool. Installed the correct butler from itch.io's broth CDN.

### 2. First Upload — Old Build Still Served

After pushing via Butler, the user still heard old audio. Discovered two uploads on the itch.io game page: the old manual `Archivo 2.zip` and the new Butler-pushed `now-with-more-plinko-html5.zip`. Both had "This file will be played in the browser" checked. Itch serves the first/older one. Fix: uncheck or delete the old upload.

### 3. No Sound on Web — Initial Hypotheses

After fixing the upload, the game was visually working but completely silent on web. Initial hypotheses tested:

**Hypothesis A: Browser autoplay policy (AudioContext suspended)**
- Tested: checked browser console, tried incognito, hard refresh
- Result: No audio-related errors in console. Game loaded fine.
- Verdict: Partially relevant — see step 7

**Hypothesis B: AudioStreamGenerator needs threading**
- Rationale: Thought the procedural audio used real-time `push_frame()` which needs threading
- Tested: Enabled `variant/thread_support=true` in export preset, enabled SharedArrayBuffer on itch
- Result: Build changed to multi-threaded, but still no audio
- Verdict: **Wrong diagnosis.** The instruments don't use `AudioStreamGenerator` at all — they pre-bake `AudioStreamWAV` buffers at init time. Threading was irrelevant.

**Hypothesis C: Browser extension blocking audio worklet files**
- Tested: Tried incognito, checked for `ERR_BLOCKED_BY_CLIENT`
- Result: The blocked resource was from a browser extension (ad blocker), not related to audio
- Verdict: Not the cause

**Hypothesis D: Single-threaded build would fix it**
- Tested: Set `thread_support=false`, re-exported
- Result: No audio AND choppy frame rate
- Verdict: Made things worse. Reverted.

### 4. Confirming the Browser Can Play Audio

Ran a JavaScript test in the browser console:
```javascript
const ctx = new AudioContext();
const o = ctx.createOscillator();
o.connect(ctx.destination);
o.start();
setTimeout(() => o.stop(), 500);
```
Result: Heard a beep. **Browser audio pipeline is fine.**

### 5. Debug Logging from GDScript

Added logging to `AudioManager.play()` and `_ready()`:
- `AudioServer.get_driver_name()` → `"AudioWorklet"`
- `AudioServer.get_mix_rate()` → `48000`
- `AudioServer.bus_count` → `5`
- All buses: not muted, volume 0 dB
- `player.playing` → `true` after calling `.play()`
- Stream and bus assignment both correct

**Key finding: Godot thinks it's playing audio, but nothing comes out.**

### 6. AudioContext Resume Fix

Discovered Godot's generated HTML shell has no AudioContext resume handler. Created a custom HTML shell (`assets/web/custom_shell.html`) that monkey-patches `window.AudioContext` to capture any context Godot creates, then resumes it on first user interaction (click/key/touch).

Console confirmed: `[audio-fix] AudioContext resumed: running`

**Still no audio.** The AudioContext was running, but Godot's internal audio pipeline wasn't producing output.

### 7. Sample Playback Mode

Researched Godot 4.4+'s `audio/general/default_playback_type` setting that switches between "Stream" (AudioWorklet) and "Sample" (WebAudio buffer) modes. Added `audio/general/default_playback_type.web=1` to project.godot.

**Still no audio.** The setting either didn't take effect or didn't help.

### 8. Minimal Test Project — The Breakthrough

Created a fresh Godot project at `/tmp/godot-audio-test/` with:
- 1 scene, 1 script, 1 AudioStreamPlayer, 1 mp3 file
- No autoloads, no custom buses, no effects
- Same Godot 4.6.1, same multi-threaded export

**Result: Audio played!** This proved the issue was project-specific, not a Godot engine bug.

### 9. Binary Search Within AudioManager

Systematically disabled parts of `AudioManager._ready()` on web:

| Test | What was enabled | Audio? |
|------|-----------------|--------|
| 1 | Single test player only (skip all init) | YES |
| 2 | Legacy sound pools (~130 players on Master) | YES |
| 3 | Legacy pools + `_setup_buses()` | **NO** |

**Root cause found: `_setup_buses()` kills all web audio.**

`_setup_buses()` calls `AudioServer.add_bus()` to create Melody, Click, Ambient, and Drones buses at runtime. Even without any bus effects attached, this breaks all audio output on web. Buses appear to create successfully — they show up in `AudioServer.bus_count`, report correct names and volumes — but all audio output is silently killed.

### 10. Final Fix

- Skip `_setup_buses()` on web
- Route all AudioStreamPlayers to Master via `_bus()` helper
- Keep custom HTML shell for AudioContext resume
- All instrument types (preloaded mp3, generated AudioStreamWAV) work on web

---

## Issues

### Why Does `AudioServer.add_bus()` Break Web Audio?

The exact mechanism is unclear without reading Godot's C++ source, but based on observed behavior:

1. **Godot's web audio driver ("AudioWorklet") initializes with a fixed bus topology.** The AudioWorklet processor is set up during engine init with a specific number of output channels/buses. When `add_bus()` is called at runtime, the C++/WASM side updates its internal bus array, but the JavaScript AudioWorklet processor node is NOT reconfigured to match. Audio samples are mixed into bus channels that the worklet doesn't read.

2. **The failure is completely silent.** No errors in the browser console, no errors in Godot's output. `AudioServer.bus_count` reflects the new buses. `AudioStreamPlayer.playing` returns `true`. Every diagnostic looks correct. The audio simply doesn't reach the browser's output.

3. **It's all-or-nothing.** Adding even one bus kills ALL audio, including sounds routed to the Master bus (which existed before the `add_bus()` call). This suggests the bus topology change invalidates the entire audio pipeline, not just the new bus.

4. **Bus effects are a secondary issue.** Even without effects (compressor, reverb, low-pass), adding buses breaks audio. Effects are known to be unsupported on web anyway, but they're not the cause.

### How to Avoid This

- **Never call `AudioServer.add_bus()` on web.** Use only the Master bus. If you need logical separation of audio channels on web, manage it in GDScript (e.g., separate volume control via player volume_db).

- **Use `OS.has_feature("web")` to gate bus creation.** The `_bus()` helper pattern works well:
  ```gdscript
  var _is_web: bool = false
  
  func _bus(name: StringName) -> StringName:
      return &"Master" if _is_web else name
  ```

- **Bus effects don't work on web regardless.** Godot's web audio pipeline (both Stream and Sample modes) doesn't support `AudioEffect` subclasses. Skip them on web even if the bus creation issue is eventually fixed.

- **Custom HTML shell is required for multi-threaded builds.** Godot's default HTML shell doesn't reliably resume the AudioContext after user interaction. The monkey-patch approach (capture AudioContext constructor, resume on click) is a reliable workaround. The custom shell lives at `assets/web/custom_shell.html` and is referenced in `export_presets.cfg`.

- **Test web audio early and often.** The failure mode is completely silent — no errors, no warnings. The only way to catch it is to actually listen.

### What This Means for the Pleenko Audio System

On native (desktop), the full bus topology works: Melody, Click, Ambient, and Drones buses each have their own effects chain (compressor, reverb, low-pass). On web, everything goes to Master with no effects. The practical impact:

- **No compressor on Drones bus:** Dense drone stacks won't be tamed. Volume attenuation (`VOICE_ATTENUATION_RATIO`) still works since that's GDScript-level, not a bus effect.
- **No reverb:** Dry harp/drone playback. Currently reverb is muted (wet=0) on Melody anyway, and Drones reverb is subtle (wet=0.2).
- **No low-pass filter:** The lofi warmth filter is currently disabled anyway.
- **No bus-level mixing:** Can't independently adjust volume of melody vs. clicks vs. drones. All share Master volume.

None of these are dealbreakers for a web build. The game is playable and sounds reasonable without effects.
