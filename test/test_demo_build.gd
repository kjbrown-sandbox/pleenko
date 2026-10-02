extends "res://test/test_base.gd"

## DemoBuild rules + the end-of-demo overlay's wishlist button — run with:
##   godot --headless --scene res://test/test_demo_build.tscn
##
## Runs under the editor binary, so OS.has_feature("editor") is true here and
## the Inspector toggle decides. The exported-build half (always the demo) is
## not reachable from a headless editor run.

const OverlayScript := preload("res://entities/coming_soon_overlay/coming_soon_overlay.gd")


func _run_tests() -> void:
	print("\n=== DemoBuild Tests ===\n")
	test_editor_toggle_decides_in_editor()
	test_store_url_is_full_game_not_demo()
	test_store_link_opens_in_steam_client()
	await test_overlay_wishlist_routes_to_store_link()


func test_editor_toggle_decides_in_editor() -> void:
	print("test_editor_toggle_decides_in_editor")
	assert_true(OS.has_feature("editor"), "precondition: running under the editor binary")
	assert_true(DemoBuild.is_active(true), "toggle on → demo")
	assert_false(DemoBuild.is_active(false), "toggle off → full game (editor only)")


func test_store_url_is_full_game_not_demo() -> void:
	print("test_store_url_is_full_game_not_demo")
	assert_true(DemoBuild.STORE_URL.begins_with("https://store.steampowered.com/app/"),
		"store url points at a Steam app page")
	assert_true(DemoBuild.STORE_URL.contains("/4681710/"), "store url is the full game's app")
	assert_false(DemoBuild.STORE_URL.contains("4692020"), "store url is NOT the demo's app")


func test_store_link_opens_in_steam_client() -> void:
	print("test_store_link_opens_in_steam_client")
	assert_false(OS.has_feature("web"), "precondition: desktop run")
	assert_equal(DemoBuild.store_link(), "steam://openurl/" + DemoBuild.STORE_URL,
		"desktop wraps the store url in steam://openurl/")


func test_overlay_wishlist_routes_to_store_link() -> void:
	print("test_overlay_wishlist_routes_to_store_link")
	var overlay := CanvasLayer.new()
	overlay.set_script(OverlayScript)
	add_child(overlay)
	await get_tree().process_frame
	var opened: Array = []
	overlay._shell_open_fn = func(u: String) -> void: opened.append(u)

	assert_false(overlay.visible, "overlay starts hidden")
	overlay._on_wishlist_pressed()

	assert_equal(opened, [DemoBuild.store_link()], "wishlist opens the store link once")
	overlay.free()
