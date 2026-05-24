extends "res://test/test_base.gd"

## MainMenu button wiring tests — run with:
##   godot --headless --scene res://test/test_main_menu_wiring.tscn
##
## Instantiates the real main_menu.tscn, injects spy seams (PeekAnimator
## precedent) so nothing launches a browser, wipes the save, or quits the
## runner, then drives the handlers directly and asserts intent.

const MainMenuScene := preload("res://entities/main_menu/main_menu.tscn")


func _run_tests() -> void:
	print("\n=== MainMenu Wiring Tests ===\n")
	test_url_constants_well_formed()
	await test_external_links_route_to_shell_open()
	await test_quit_routes_to_quit_seam()
	await test_reset_path_reachable_via_settings()


func _make_menu() -> MainMenu:
	var menu: MainMenu = MainMenuScene.instantiate()
	# Deferred: the test scene's own _ready is still on the stack, so the tree
	# root is busy setting up children.
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	return menu


func test_url_constants_well_formed() -> void:
	print("test_url_constants_well_formed")
	for url in [MainMenu.DISCORD_URL, MainMenu.FEEDBACK_URL]:
		assert_true(url.length() > 0, "url non-empty: %s" % url)
		assert_true(url.begins_with("http"), "url is http(s): %s" % url)


func test_external_links_route_to_shell_open() -> void:
	print("test_external_links_route_to_shell_open")
	var menu := await _make_menu()
	var opened: Array = []
	menu._shell_open_fn = func(u: String) -> void: opened.append(u)

	menu._on_discord_pressed()
	menu._on_feedback_pressed()

	assert_equal(opened.size(), 2, "two links opened")
	assert_equal(opened[0], MainMenu.DISCORD_URL, "discord → DISCORD_URL")
	assert_equal(opened[1], MainMenu.FEEDBACK_URL, "feedback → FEEDBACK_URL")
	menu.free()


func test_quit_routes_to_quit_seam() -> void:
	print("test_quit_routes_to_quit_seam")
	var menu := await _make_menu()
	var quit_calls := [0]
	menu._quit_fn = func() -> void: quit_calls[0] += 1

	menu._on_quit_pressed()

	assert_equal(quit_calls[0], 1, "quit seam called exactly once")
	menu.free()


func test_reset_path_reachable_via_settings() -> void:
	print("test_reset_path_reachable_via_settings")
	var menu := await _make_menu()
	var reset_calls := [0]
	menu._full_reset_fn = func() -> void: reset_calls[0] += 1

	# Reset Game moved into Settings: the dialog must be MAIN_MENU context
	# (no in-game "Return to Main Menu" button) and signal up.
	var dialog: OptionsDialog = menu._options_dialog
	assert_equal(dialog.context, OptionsDialog.Context.MAIN_MENU,
		"options dialog opened in MAIN_MENU context")
	assert_true(dialog._return_button == null,
		"in-game 'Return to Main Menu' button not constructed in menu context")
	assert_true(dialog.reset_requested.is_connected(menu._on_reset_requested),
		"dialog.reset_requested wired to MainMenu")

	# Drive the full chain: dialog asks → confirm shows → confirm wipes.
	dialog.reset_requested.emit()
	assert_true(menu.confirm_overlay.visible, "confirm overlay shown after request")
	assert_false(dialog.visible, "options dialog hidden while confirm is up")

	menu._on_confirm_reset_pressed()
	assert_equal(reset_calls[0], 1, "full_reset seam called exactly once")
	assert_false(menu.confirm_overlay.visible, "confirm overlay hidden after reset")

	# Cancel re-opens Settings rather than dropping to the bare menu.
	menu._on_reset_requested()
	menu._on_cancel_pressed()
	assert_false(menu.confirm_overlay.visible, "confirm overlay hidden after cancel")
	assert_true(dialog.visible, "settings re-shown after cancel")
	menu.free()
