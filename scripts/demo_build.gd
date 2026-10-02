class_name DemoBuild

## Demo-build rules shared by Main (lockdown overlay) and MainMenu (wishlist
## button), so the two can't disagree about whether this is the demo.

## The full game's store page (NOT the demo's app 4692020 — that's what the
## player is already running).
const STORE_URL := "https://store.steampowered.com/app/4681710/"


## Ship safety: any exported build (e.g. the itch upload) MUST run as the demo,
## regardless of an accidental Inspector toggle or a dirty working tree. The
## per-scene `demo_mode` export stays editor-toggleable for local testing, but
## `false` can never reach players. (To intentionally ship a full, non-demo
## build later, remove the editor check.)
static func is_active(editor_toggle: bool) -> bool:
	return editor_toggle or not OS.has_feature("editor")


## Desktop opens the page inside the Steam client, where the player is already
## logged in (one click to wishlist). The browser can't follow steam:// links,
## so the web build uses the plain URL.
static func store_link() -> String:
	if OS.has_feature("web"):
		return STORE_URL
	return "steam://openurl/" + STORE_URL
