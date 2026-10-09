extends SceneTree
# Automated playthrough: boots main.tscn, presses real keys/clicks through the
# input system, and plays every story mission to the end.
#
#   Godot_v4.5-stable_win64_console.exe --headless --path . -s tests/smoke_test.gd
#
# Exit code 0 = all checks passed, 1 = something failed (see FAIL lines).

var main: Node
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_click_starts_game()
	await _test_full_playthrough()
	print("SMOKE TEST: %s (%d failure(s))" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func _boot() -> void:
	if main:
		main.queue_free()
		await process_frame
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func key(code: Key, hold_frames: int = 1) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(hold_frames)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


func click() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = Vector2(640, 360)
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)


func teleport(pos: Vector3) -> void:
	main.player_pos = Vector3(pos.x, 0.7, pos.z)
	main.player.position = main.player_pos
	await _frames(3)


func _test_click_starts_game() -> void:
	print("[menu: click to start]")
	await _boot()
	check(main.menu_cl != null, "title menu is shown on launch")
	await click()
	check(main.menu_cl == null, "clicking dismisses the menu")


func _test_full_playthrough() -> void:
	print("[menu: keyboard]")
	await _boot()
	await key(KEY_3)
	check(main.difficulty == 2, "3 selects HARD on the menu")
	await key(KEY_2)
	check(main.difficulty == 1, "2 selects NORMAL on the menu")
	check(main.current_tool == "select", "menu keys don't change the build tool")
	await key(KEY_ENTER)
	check(main.menu_cl == null, "ENTER starts the game")

	print("[movement]")
	await teleport(Vector3(main._wx(8 * main.CELL), 0, main._wz(8 * main.CELL)))
	var start: Vector3 = main.player_pos
	await key(KEY_W, 30)
	check(main.player_pos.distance_to(start) > 0.5, "W moves the player")
	start = main.player_pos
	await key(KEY_UP, 30)
	check(main.player_pos.distance_to(start) > 0.5, "arrow keys move the player")

	print("[keys]")
	await key(KEY_P)
	check(main.paused, "P pauses")
	await key(KEY_1)
	check(main.current_tool == "select", "keys are ignored while paused")
	await key(KEY_ESCAPE)
	check(not main.paused, "Esc resumes")
	await key(KEY_B)
	check(main.buy_menu_open, "B opens the store")
	var budget: int = main.sim_budget
	await key(KEY_2)
	check(main.sim_budget == budget - 150, "store: 2 buys ammo")
	await key(KEY_0)
	check(not main.buy_menu_open, "store: 0 closes it")
	await key(KEY_TAB)
	check(main.stats_cl.visible and main.stats_label.text.begins_with("Day"), "TAB shows stats")
	await key(KEY_TAB)
	var ammo: int = main.ammo
	await key(KEY_SPACE)
	check(main.ammo == ammo - 1, "Space shoots")
	check(main.current_tool == "select", "Space no longer switches tools")
	await key(KEY_G)
	check(main.wanted_level >= 1, "G raises wanted level")
	main.wanted_level = 0
	await key(KEY_1)
	check(main.current_tool == "zone_res", "1 picks residential zoning in-game")
	await key(KEY_0)

	print("[vehicle]")
	await teleport(main.vehicles[0]["pos"] + Vector3(1.0, 0, 0))
	await key(KEY_F)
	check(main.vehicle_in, "F enters a nearby car")
	start = main.current_vehicle_pos
	await key(KEY_W, 40)
	check(main.current_vehicle_pos.distance_to(start) > 0.5, "W drives the car")
	await key(KEY_F)
	check(not main.vehicle_in, "F exits the car")

	print("[missions]")
	check(main.current_mission.get("id") == "bust_the_burglar", "mission 1 active at start")
	await teleport(main.current_mission["target_pos"])
	check(main.current_mission.get("status") == "complete", "M1 completes at the burglar")
	check(not main.game_complete, "finishing M1 does not end the game")
	await key(KEY_M)
	check(main.current_mission.get("id") == "chase_the_bank_robber", "M starts mission 2")
	await teleport(main.current_mission["target_pos"])
	check(main.current_mission.get("status") == "complete", "M2 completes")
	await key(KEY_M)
	check(main.current_mission.get("id") == "collect_bonus", "M starts mission 3")
	var bags: int = 0
	for p in main.pickups.duplicate():
		if p["type"] == "money" and main.current_mission.get("status") == "active":
			await teleport(p["pos"])
			bags += 1
	check(main.current_mission.get("status") == "complete", "M3 completes after %d money bags" % bags)
	await key(KEY_M)
	check(main.current_mission.get("id") == "the_big_heist", "M starts the heist")
	await teleport(main.current_mission["heist_target"])
	check(main.current_mission.get("heist_stage") == "escape", "reaching the bank robs it")
	main.wanted_level = 0
	await _frames(3)
	check(main.current_mission.get("status") == "complete", "heist completes once wanted is 0")
	await key(KEY_M)
	check(main.current_mission.get("id") == "pizza_delivery", "M starts the pizza run")
	await teleport(main.pizza_shop_pos)
	check(main.carrying_pizza, "pizza picked up at the shop")
	await teleport(main.delivery_target_pos)
	check(main.current_mission.get("status") == "complete", "pizza delivered")
	await _frames(3)
	check(main.game_complete and main.final_cl != null, "all 5 missions -> GAME COMPLETE screen")
	await key(KEY_ENTER)
	check(main.final_cl == null, "ENTER closes results to keep playing")

	print("[death]")
	main.difficulty = 1
	main.player_health = 0
	await _frames(5)
	check(main.game_over, "0 HP -> game over")
	var overlays: int = 0
	for c in main.get_children():
		if c is CanvasLayer and c.layer == 13:
			overlays += 1
	check(overlays == 1, "exactly one game-over screen (was %d)" % overlays)
	await key(KEY_R)
	check(not main.game_over and main.player_health == main.player_max_health, "R respawns")
