extends Node3D

## Step 6: mouse input — click to place a building on a road-adjacent cell.
## Also: top-down mode toggle, vehicle that drives on a road loop.

const GRID := 32
const CELL := 2.0
const ROAD_EVERY := 4
const HALF := GRID * CELL * 0.5  # = 32; world centered at origin

func _wx(x: float) -> float: return x - HALF
func _wz(z: float) -> float: return z - HALF

var sun: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var _t := 0.5
var time_speed: float = 1.0  # +/- keys change this
var lamps: Array[MeshInstance3D] = []
var buildings_root: Node3D
var placed_buildings: Array[Vector3i] = []  # (x, z, color_index)

# ---- Sim layer (SimCity foundation) ----
var sim_population: int = 1250
var sim_budget: int = 20000
var sim_day_count: int = 0
var sim_residential_demand: float = 50.0  # 0-100
var sim_commercial_demand: float = 50.0
var sim_industrial_demand: float = 50.0
var sim_tax_rate: float = 0.09
var sim_residential_tax_rate: float = 0.09
var sim_income_today: int = 0
var sim_expenses_today: int = 0
var growth_accum: float = 0.0
var sim_day_accum: float = 0.0  # seconds until next sim day
# Power system
const COAL_POWER_RADIUS = 12
const WIND_POWER_RADIUS = 8
const WATER_RADIUS = 2
var power_plants: Array[Vector3i] = []  # (x, z, color_index) where color_index 3=coal, 4=wind
var water_tiles: Array[Vector2i] = []
var powered_cells: Dictionary = {}  # key "%d,%d" -> bool
var watered_cells: Dictionary = {}  # key "%d,%d" -> bool
var pollution: Array = []  # pollution[x][z] -> float  # pollution level per cell, 0.0 to 1.0
# City health warning system: surfaces sim failure modes to the player
var sim_population_peak: int = 1250
var sim_budget_deficit_days: int = 0  # consecutive days sim_budget went down
var sim_high_tax_days: int = 0  # consecutive days tax rate > 15%
var sim_active_health_warning: String = ""
var avg_res_pollution: float = 0.0  # average pollution of residential zones
var health_warning_label: Label
var health_warning_bg: ColorRect
var health_warning_timer: float = 0.0
# Dynamic weather system: 0=clear, 1=rain, 2=storm (rain + darker sky + wet look)
var weather_state: int = 0
var weather_state_names: Array[String] = ["CLEAR", "RAIN", "STORM"]
var weather_state_icons: Array[String] = ["SUN", "RAIN", "STORM"]
var weather_timer: float = 0.0  # counts up; cycles state at threshold
var weather_state_duration: float = 90.0  # seconds per state (sim time scaled)
var rain_drops: Array[MeshInstance3D] = []  # pre-built rain particles, recycled
var rain_root: Node3D
var weather_label: Label
var weather_ambient_mod: float = 0.0  # 0=clear, -0.2=rain, -0.35=storm
var sim_unlocked: Array[String] = ["Basic Zone"]
var missions: Array = []  # active missions
var completed_missions: Array = []
var stats_npcs_killed: int = 0
var stats_cars_smashed: int = 0
var stats_money_earned: int = 0
var stats_missions_failed: int = 0
var total_play_time: float = 0.0  # seconds in this session
var game_complete: bool = false
var final_score: int = 0
var final_rank: String = ""
var final_cl: CanvasLayer
var event_timer: float = 0.0  # counts up to next random event
var event_active: Dictionary = {}  # current random event
var event_cl: CanvasLayer  # HUD for active event
var stats_bullets_fired: int = 0
var stats_distance_walked: float = 0.0  # strings of completed mission IDs
var current_mission: Dictionary = {}
var mission_overlay: CanvasLayer
var mission_label: Label
var mission_objective: Label
# Delivery mission (M5 "Pizza Run") state
var pizza_shop_pos: Vector3 = Vector3.ZERO
var pizza_shop_mesh: MeshInstance3D  # red shop building (visual)
var pizza_box_mesh: MeshInstance3D  # yellow pizza box, reparented to player when carried
var delivery_target_pos: Vector3 = Vector3.ZERO
var delivery_target_mesh: MeshInstance3D  # green target marker (visual)
var carrying_pizza: bool = false
var delivery_timer: float = 0.0  # counts DOWN from 90 sim-seconds
const DELIVERY_TIME_LIMIT := 90.0
var PIZZA_SHOP_GRID: Vector2i = Vector2i(15, 15)  # fixed location for the shop
const DELIVERY_RADIUS := 2.5  # how close player must be to shop and target
const PIZZA_REWARD := 400
const PIZZA_PENALTY := 50
var wanted_level: int = 0  # 0..5 stars
var wanted_timer: float = 0.0
var police: Array = []  # list of {mesh, pos, target_pos, speed}
var pickups: Array = []
var bullets: Array = []  # {mesh, pos, vel, ttl}
var bullet_template: Mesh
var bullet_cooldown: float = 0.0  # {mesh, pos, type: "money"|"health", value}
var player_health: int = 100
var player_max_health: int = 100
var ammo: int = 30  # bullets left
var max_ammo: int = 30
var last_shot_time: float = 0.0
var total_deaths: int = 0  # times player was busted/killed
var total_respawns: int = 0
var player_invulnerable: float = 0.0  # seconds of i-frames after respawn
var announcement_label: Label  # big yellow banner for unlocks, mission start, etc.
var announcement_timer: float = 0.0
var audio_on: bool = true
var difficulty: int = 1
var paused: bool = false
var pause_cl: CanvasLayer
var menu_footer: Label
var stats_cl: CanvasLayer
var stats_label: Label
# Story missions in play order. M advances to the first one not yet done;
# the game is complete once every id here is in completed_missions.
const MISSION_CHAIN: Array[String] = ["bust_the_burglar", "chase_the_bank_robber", "collect_bonus", "the_big_heist", "pizza_delivery"]
var damage_flash: float = 0.0
var damage_flash_cl: CanvasLayer  # 0=easy, 1=normal, 2=hard
var easy_mode: bool = false
var menu_cl: CanvasLayer
var menu_label: Label
var buy_menu_open: bool = false
var buy_menu_cl: CanvasLayer
var vehicle_in: bool = false  # true when player is driving a car
var current_vehicle: MeshInstance3D
var current_vehicle_pos: Vector3
var current_vehicle_yaw: float = 0.0
var current_vehicle_speed: float = 0.0
var vehicles: Array = []  # list of {mesh, pos, yaw, speed, color}
var interior_view: bool = false
var interior_root: Node3D
var player: MeshInstance3D
var player_pos: Vector3 = Vector3.ZERO
var player_vel: Vector3 = Vector3.ZERO
var player_speed: float = 6.0
var cam_thirdperson: bool = false
var cam_player_yaw: float = 35.0
var cam_player_pitch: float = -25.0
var cam_player_dist: float = 12.0
var demand_bars_root: Node
var cam_pitch := -50.0
var cam_yaw := 35.0
var cam_dist := 90.0
var cam_topdown := false
var hover_cell := Vector2i(-1, -1)
# Tool state: "select" | "zone_res" | "zone_com" | "zone_ind" | "bulldoze" | "road"
var current_tool: String = "select"
var tool_cost_zone: int = 100
var tool_cost_road: int = 10
var tool_cost_bulldoze: int = 1
var tool_cost_coal: int = 250
var tool_cost_wind: int = 200
var controls_overlay: CanvasLayer
var controls_label: Label


func _ready() -> void:
	_setup_input_map()
	# Auto-dismiss menu if --start passed on command line
	var _auto_start: bool = false
	var _pending_warning: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--start" or arg == "--play":
			_auto_start = true
		if arg == "--easy":
			difficulty = 0
		if arg == "--hard":
			difficulty = 2
		if arg.begins_with("--simulate-warning="):
			_pending_warning = arg.substr(19)
		# Debug: force a starting tax rate to verify the HUD field + warnings
		if arg.begins_with("--start-tax="):
			sim_residential_tax_rate = clamp(float(arg.substr(12)) / 100.0, 0.0, 0.20)
		if arg == "--rain":
			weather_state = 1
		if arg == "--storm":
			weather_state = 2
	buildings_root = Node3D.new()
	add_child(buildings_root)
	_build_ground()
	_build_hills()
	_build_water()
	_update_water_tiles()
	# Initialize pollution grid
	pollution = []
	for x in GRID:
		pollution.append([])
		for z in GRID:
			pollution[x].append(0.0)
	_build_traffic()
	_build_cars()
	_build_parked_cars()
	_build_pickups()
	_build_npcs()
	_build_cone_pool()
	_build_trees()
	_build_roads()
	_build_initial_buildings()
	_build_lamps()
	_build_police()
	_build_burglar()
	_setup_missions()
	_build_light_env()
	_build_weather()
	_build_camera()
	_build_player()
	_build_minimap()
	_build_stats_overlay()
	_build_context_hint()
	_build_main_menu()
	_build_buy_menu()
	if _auto_start:
		print("AUTOSTART: dismissing menu")
		_dismiss_menu()
	bullet_template = CylinderMesh.new()
	bullet_template.top_radius = 0.06
	bullet_template.bottom_radius = 0.06
	bullet_template.height = 0.4
	_build_hud()
	if _pending_warning != "":
		_apply_debug_warning(_pending_warning)
	demand_bars_root = Node.new()
	hud_label.add_child(demand_bars_root)

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--time="):
			_t = float(a.substr(7))
		if a == "--topdown":
			cam_topdown = true
	_apply_time()
	if cam_topdown:
		_refresh_camera()

	if "--capture" in args:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://capture.png")
		print("CITY: saved t=", _t, " placed=", placed_buildings.size())
		get_tree().quit(0)



# Godot's built-in ui_* actions only cover the arrow keys. The player and
# vehicle code polls ui_up/down/left/right, so bind WASD to them as well.
func _setup_input_map() -> void:
	var binds := {"ui_up": KEY_W, "ui_down": KEY_S, "ui_left": KEY_A, "ui_right": KEY_D}
	for action in binds:
		var ev := InputEventKey.new()
		ev.physical_keycode = binds[action]
		InputMap.action_add_event(action, ev)


func _process(delta: float) -> void:
	if paused or game_over:
		return
	# Slowly advance time so user sees day/night if windowed
	_t = fmod(_t + delta * 0.02, 1.0)
	_apply_time()
	_update_traffic(delta)
	_update_traffic_cones(delta)
	_update_cars(delta)
	_update_weather(delta)
	if menu_cl:
		# Title screen: the city animates behind the menu, gameplay waits
		return
	_update_police(delta)
	_update_mission(delta)
	_update_heist(delta)
	_update_wanted(delta)
	_update_npcs(delta)
	_update_pickups(delta)
	_update_bullets(delta)
	_update_player(delta)
	_update_vehicle(delta)
	_update_health_banner(delta)
	# Growth: every 0.5s, randomly bump a built cell to a higher density
	growth_accum += delta
	if growth_accum > 0.5:
		growth_accum -= 0.5
		_grow_random_cell()
	# Daily tick: 1 sim day = 4 real seconds
	sim_day_accum += delta
	if sim_day_accum > 4.0:
		sim_day_accum -= 4.0
		_sim_daily_tick()
	_refresh_hud()
	_refresh_wanted_label()
	_update_minimap()
	if stats_cl and stats_cl.visible:
		_refresh_stats_overlay()


func _sim_daily_tick() -> void:
	# Decay pollution slightly each day
	for x in GRID:
		for z in GRID:
			pollution[x][z] *= 0.95
	# Count buildings by zone type (color_index 0=residential, 1=commercial, 2=industrial)
	var r_count: int = 0
	var c_count: int = 0
	var i_count: int = 0
	for b in placed_buildings:
		match b.z:
			0: r_count += 1
			1: c_count += 1
			2: i_count += 1

	# Update pollution from industrial buildings
	for b in placed_buildings:
		if b.z == 2:  # industrial
			var radius = 2  # cells
			for dx in range(-radius, radius+1):
				for dz in range(-radius, radius+1):
					var x = b.x + dx
					var z = b.y + dz
					if x >= 0 and x < GRID and z >= 0 and z < GRID:
						# Add pollution, clamp to 1.0
						pollution[x][z] = min(1.0, pollution[x][z] + 0.1)
	# Compute average pollution of residential zones
	var total_res_pollution: float = 0.0
	var res_count: int = 0
	for b in placed_buildings:
		if b.z == 0:  # residential
			total_res_pollution += pollution[b.x][b.y]
			res_count += 1
	if res_count > 0:
		avg_res_pollution = total_res_pollution / res_count
	else:
		avg_res_pollution = 0.0
	# Demand: R wants jobs nearby; C wants residents; I wants commercial
	# SimCity-ish: R demand = 100 - clamp(jobs/2, 0, 100) + residential quality
	# High taxes drive residents away (SimCity tax-revolt mechanic)
	var tax_suppression: float = 0.0
	if sim_residential_tax_rate > 0.10:
		# 0% at 10%, 50% penalty at 20% (linear in 10..20% range)
		tax_suppression = clamp((sim_residential_tax_rate - 0.10) * 500.0, 0.0, 50.0)
	var r_base: float = 100.0 - clamp(c_count * 4.0, 0.0, 80.0) + (sim_budget / 500.0) - tax_suppression
	var c_base: float = clamp(r_count * 6.0, 0.0, 100.0) - (i_count * 2.0)
	var i_base: float = clamp(c_count * 5.0, 0.0, 100.0) - (r_count * 1.0)
	sim_residential_demand = clamp(r_base * (1.0 - avg_res_pollution), 0.0, 100.0)
	sim_commercial_demand = clamp(c_base, 0.0, 100.0)
	sim_industrial_demand = clamp(i_base, 0.0, 100.0)

	# Population grows when residential zones exist and demand is decent
	var pop_target: float = r_count * 12.0
	if sim_residential_demand > 60.0 and r_count > 0:
		pop_target *= 1.4
	elif sim_residential_demand < 25.0:
		pop_target *= 0.7
	pop_target = clamp(pop_target, 0.0, 50000.0)
	# Move sim_population 10% toward target each day
	sim_population = int(sim_population * 0.9 + pop_target * 0.1)
	if sim_population < 100 and r_count > 0:
		sim_population = 100

	# Tax income (per-capita daily, scaled by demand)
	var per_cap: float = 4.0 + (sim_residential_demand / 50.0) * 2.0
	sim_income_today = int(sim_population * per_cap * sim_residential_tax_rate * 30.0)  # ~monthly rate
	sim_expenses_today = int(r_count * 5 + c_count * 8 + i_count * 12)  # per-day upkeep
	sim_budget += sim_income_today - sim_expenses_today

	# Budget floor: if money runs out, demand drops (people leave)
	if sim_budget < -2000:
		sim_residential_demand = max(0.0, sim_residential_demand - 20.0)

	# Track consecutive high-tax days for the TAX REVOLT warning
	if sim_residential_tax_rate > 0.15:
		sim_high_tax_days += 1
	else:
		sim_high_tax_days = 0

	sim_day_count += 1
	_update_city_health(r_count, c_count, i_count)
	_update_power_coverage()
	_update_water_coverage()


func _update_city_health(r_count: int, c_count: int, i_count: int) -> void:
	# Track population peak so we can warn when it drops
	if sim_population > sim_population_peak:
		sim_population_peak = sim_population
	# Track consecutive deficit days
	if (sim_income_today - sim_expenses_today) < 0:
		sim_budget_deficit_days += 1
	else:
		sim_budget_deficit_days = 0
	# Pick the most severe warning (priority: budget > population > jobs > workers)
	var warning: String = ""
	var col: Color = Color(1, 0.85, 0.2)
	var duration: float = 4.0
	# 1. Budget crisis: 3+ days of negative net income
	if sim_budget_deficit_days >= 3:
		warning = "BUDGET CRISIS: %d days in deficit! Zone commercial to boost tax income." % sim_budget_deficit_days
		col = Color(1.0, 0.3, 0.3)
		duration = 6.0
	# 1b. Tax revolt: player set tax > 15% for 3+ days
	elif sim_high_tax_days >= 3 and r_count >= 2:
		warning = "TAX REVOLT: %d%% rate is unsustainable — residents fleeing. Press [ to lower taxes." % int(sim_residential_tax_rate * 100.0)
		col = Color(0.95, 0.4, 0.5)
		duration = 5.5
	# 2. Population exodus: down >15% from peak AND we have residential
	elif sim_population_peak > 200 and sim_population < int(sim_population_peak * 0.85):
		var loss_pct: int = int(100.0 - (float(sim_population) / float(sim_population_peak) * 100.0))
		warning = "POPULATION EXODUS: -%d%% from peak (%d/%d). Build more residential or lower taxes." % [loss_pct, sim_population, sim_population_peak]
		col = Color(1.0, 0.6, 0.2)
		duration = 5.0
	# 3. Jobs without workers: lots of industrial, no residential nearby
	elif i_count > 4 and r_count < 2 and i_count > r_count * 2:
		warning = "NEED WORKERS: %d industrial jobs but only %d residential — people are commuting from out of town." % [i_count, r_count]
		col = Color(0.9, 0.8, 0.3)
		duration = 4.5
	# 4. Workers without jobs: residential but no commerce/industry
	elif r_count > 5 and c_count < 2 and i_count < 2:
		warning = "UNEMPLOYMENT: %d residential but only %d shops/factories. Zone commercial or industrial to hire them." % [r_count, c_count + i_count]
		col = Color(0.7, 0.8, 1.0)
		duration = 4.5
	# Only fire warning if state changed (so we don't spam the banner every day)
	if warning != "" and warning != sim_active_health_warning:
		_show_health_banner(warning, col, duration)
		sim_active_health_warning = warning
	elif warning == "":
		sim_active_health_warning = ""


func _show_health_banner(text: String, col: Color, duration: float) -> void:
	if health_warning_label == null:
		return
	health_warning_label.text = text
	health_warning_label.add_theme_color_override("font_color", col)
	if health_warning_bg:
		health_warning_bg.color = Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.85)
	health_warning_label.modulate = Color(1, 1, 1, 1)
	health_warning_label.visible = true
	if health_warning_bg:
		health_warning_bg.visible = true
	health_warning_timer = duration


func _apply_debug_warning(wname: String) -> void:
	# Debug hook for the cron capture: force a known health warning
	# to verify the banner renders. Used via --simulate-warning=name.
	# Recognized names: budget, exodus, workers, unemployment.
	match wname:
		"budget":
			sim_budget = -5000
			sim_budget_deficit_days = 4
			_show_health_banner(
				"BUDGET CRISIS: 4 days in deficit! Zone commercial to boost tax income.",
				Color(1.0, 0.3, 0.3), 30.0)
		"exodus":
			sim_population_peak = 5000
			sim_population = 3000
			_show_health_banner(
				"POPULATION EXODUS: -40% from peak (3000/5000). Build more residential or lower taxes.",
				Color(1.0, 0.6, 0.2), 30.0)
		"workers":
			_show_health_banner(
				"NEED WORKERS: 8 industrial jobs but only 2 residential — people are commuting from out of town.",
				Color(0.9, 0.8, 0.3), 30.0)
		"unemployment":
			_show_health_banner(
				"UNEMPLOYMENT: 12 residential but only 1 shops/factories. Zone commercial or industrial to hire them.",
				Color(0.7, 0.8, 1.0), 30.0)


func _update_health_banner(delta: float) -> void:
	if health_warning_label == null or not health_warning_label.visible:
		return
	health_warning_timer -= delta
	if health_warning_timer <= 0.0:
		health_warning_label.visible = false
		if health_warning_bg:
			health_warning_bg.visible = false
		return
	# Fade out the last 1 second
	if health_warning_timer < 1.0:
		var a: float = clamp(health_warning_timer, 0.0, 1.0)
		health_warning_label.modulate = Color(1, 1, 1, a)


func _grow_random_cell() -> void:
	if placed_buildings.is_empty():
		return
	var idx: int = randi() % placed_buildings.size()
	var cell: Vector3i = placed_buildings[idx]
	var key := "%d,%d" % [cell.x, cell.y]
	if not watered_cells.has(key):
		return
	var d: int = cell_density.get(key, 1)
	if d >= DENSITY_MAX:
		return
	d += 1
	cell_density[key] = d
	_refresh_building_at(cell.x, cell.y)


# Modal screens (title menu, game over, pause, store) swallow input so keys
# like 1/2/3 mean "difficulty" or "buy" there instead of zone tools. This runs
# in _input (before the GUI) because the overlays' full-screen ColorRects would
# otherwise eat mouse clicks before _unhandled_input ever saw them.
func _input(event: InputEvent) -> void:
	if _handle_modal_input(event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hit := _raycast_ground(event.position)
		if hit != Vector3.INF:
			hover_cell = Vector2i(int(round(hit.x / CELL)), int(round(hit.z / CELL)))
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_apply_tool_at_hover()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam_dist = maxf(cam_dist - 5, 20.0)
			_refresh_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_dist = minf(cam_dist + 5, 200.0)
			_refresh_camera()
	elif event is InputEventKey and event.pressed:
		# Holding Space auto-fires; every other key acts once per press
		if event.echo and event.keycode != KEY_SPACE:
			return
		match event.keycode:
			KEY_1: current_tool = "zone_res"
			KEY_2: current_tool = "zone_com"
			KEY_3: current_tool = "zone_ind"
			KEY_4: current_tool = "road"
			KEY_5: current_tool = "bulldoze"
			KEY_6: current_tool = "zone_coal"
			KEY_7: current_tool = "zone_wind"
			KEY_0: current_tool = "select"
			KEY_SPACE: _try_shoot()
			KEY_F:
				if vehicle_in:
					_exit_vehicle()
				else:
					_try_enter_vehicle()
			KEY_E:
				if interior_view:
					_exit_building()
				else:
					_try_enter_building()
			KEY_ESCAPE:
				if interior_view:
					_exit_building()
				else:
					_set_paused(true)
			KEY_P: _set_paused(true)
			KEY_B: _toggle_buy_menu()
			KEY_TAB: _toggle_stats()
			KEY_G: _add_wanted(1)
			KEY_J:
				if player_invulnerable <= 0.0:
					player_health -= 10
					damage_flash = 0.2
					_announce("OUCH (-10 HP)", Color(1, 0.3, 0.3))
			KEY_T: cam_topdown = not cam_topdown; _refresh_camera()
			KEY_F5: save_city()
			KEY_F9: load_city()
			KEY_PLUS, KEY_KP_ADD: time_speed = clamp(time_speed * 1.5, 0.25, 8.0)
			KEY_MINUS, KEY_KP_SUBTRACT: time_speed = clamp(time_speed / 1.5, 0.25, 8.0)
			KEY_BRACKETLEFT:
				# Lower residential tax rate by 1% (SimCity: [ decreases tax)
				sim_residential_tax_rate = clamp(sim_residential_tax_rate - 0.01, 0.0, 0.20)
				_announce("TAX RATE: %d%%" % int(sim_residential_tax_rate * 100.0),
					Color(0.5, 0.85, 0.5) if sim_residential_tax_rate <= 0.10 else Color(1.0, 0.7, 0.3))
			KEY_BRACKETRIGHT:
				# Raise residential tax rate by 1% (SimCity: ] increases tax)
				sim_residential_tax_rate = clamp(sim_residential_tax_rate + 0.01, 0.0, 0.20)
				_announce("TAX RATE: %d%%" % int(sim_residential_tax_rate * 100.0),
					Color(0.5, 0.85, 0.5) if sim_residential_tax_rate <= 0.10 else Color(1.0, 0.7, 0.3))
			KEY_H: _toggle_controls()
			KEY_C:
				cam_thirdperson = true
				_refresh_player_camera()
			KEY_V:
				cam_thirdperson = false
				_refresh_camera()
			KEY_N: _cycle_weather()
			KEY_M: _advance_mission()
		_refresh_controls()


# Returns true when a modal screen is up and consumed the event.
func _handle_modal_input(event: InputEvent) -> bool:
	var key: int = -1
	if event is InputEventKey and event.pressed and not event.echo:
		key = event.keycode
	var clicked: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if menu_cl:
		match key:
			KEY_1: _set_difficulty(0)
			KEY_2: _set_difficulty(1)
			KEY_3: _set_difficulty(2)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _dismiss_menu()
			KEY_ESCAPE: get_tree().quit()
		if clicked:
			_dismiss_menu()
		return true
	if game_over:
		match key:
			KEY_R: _respawn_after_game_over()
			KEY_ESCAPE, KEY_Q: get_tree().quit()
		return true
	if final_cl:
		match key:
			KEY_R: _restart_game()
			KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE:
				# Close the results screen and keep playing
				final_cl.queue_free()
				final_cl = null
		return true
	if paused:
		match key:
			KEY_P, KEY_ESCAPE: _set_paused(false)
			KEY_Q: get_tree().quit()
		return true
	if buy_menu_open:
		match key:
			KEY_1: _buy_item(1)
			KEY_2: _buy_item(2)
			KEY_3: _buy_item(3)
			KEY_4: _buy_item(4)
			KEY_0, KEY_B, KEY_ESCAPE: _toggle_buy_menu()
		return key != -1 or clicked
	return false


func _set_difficulty(d: int) -> void:
	difficulty = d
	if menu_footer:
		menu_footer.text = "Difficulty: %s  -  press ENTER or click to start" % ["EASY", "NORMAL", "HARD"][d]


func _set_paused(on: bool) -> void:
	paused = on
	if on and pause_cl == null:
		pause_cl = CanvasLayer.new()
		pause_cl.layer = 14
		add_child(pause_cl)
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.6)
		bg.size = Vector2(1280, 720)
		pause_cl.add_child(bg)
		var t := Label.new()
		t.text = "PAUSED\n\nP / Esc  resume\nQ  quit"
		t.position = Vector2(0, 250)
		t.size = Vector2(1280, 200)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_font_size_override("font_size", 36)
		t.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
		pause_cl.add_child(t)
	elif not on and pause_cl:
		pause_cl.queue_free()
		pause_cl = null


func _toggle_stats() -> void:
	if stats_cl:
		stats_cl.visible = not stats_cl.visible
		_refresh_stats_overlay()


func _apply_tool_at_hover() -> void:
	if hover_cell.x < 0 or hover_cell.y < 0:
		return
	if not _in_bounds(hover_cell.x, hover_cell.y):
		return
	match current_tool:
		"zone_res": _try_zone(hover_cell.x, hover_cell.y, 0, tool_cost_zone)
		"zone_com": _try_zone(hover_cell.x, hover_cell.y, 1, tool_cost_zone)
		"zone_ind": _try_zone(hover_cell.x, hover_cell.y, 2, tool_cost_zone)
		"road": _try_road(hover_cell.x, hover_cell.y)
		"bulldoze": _try_bulldoze(hover_cell.x, hover_cell.y)
		"zone_coal":
			_try_zone(hover_cell.x, hover_cell.y, 3, tool_cost_coal)
			_update_power_coverage()
		"zone_wind":
			_try_zone(hover_cell.x, hover_cell.y, 4, tool_cost_wind)
			_update_power_coverage()
	_refresh_hud()
	_refresh_wanted_label()
	_update_minimap()


func _try_zone(x: int, z: int, color: int, cost: int) -> void:
	if _is_water(x, z):
		return
	if sim_budget < cost:
		return
	for i in range(placed_buildings.size()):
		var b: Vector3i = placed_buildings[i]
		if b.x == x and b.y == z:
			var cur_density: int = cell_density.get(_bk(x, z), 0)
			if b.z == color and sim_budget >= cost:
				if cur_density >= 3:
					return
				sim_budget -= cost
				cell_density[_bk(x, z)] = cur_density + 1
				_refresh_building_at(x, z)
				return
			else:
				if sim_budget >= cost + tool_cost_bulldoze:
					sim_budget -= tool_cost_bulldoze
					sim_budget -= cost
					placed_buildings[i] = Vector3i(x, z, color)
					var key = "%d,%d" % [x, z]
					powered_cells[key] = false
					cell_density[_bk(x, z)] = 0
					_refresh_building_at(x, z)
					return
				return
	if not _is_road_adjacent(x, z):
		return
	sim_budget -= cost
	_place_building(x, z, color, 0)

# Update power coverage for all buildings
func _update_power_coverage() -> void:
	var COAL_RADIUS = COAL_POWER_RADIUS
	var WIND_RADIUS = WIND_POWER_RADIUS
	for pb in placed_buildings:
		var key = "%d,%d" % [pb.x, pb.y]
		var powered = false
		for pp in power_plants:
			var dx = pb.x - pp.x
			var dz = pb.y - pp.z
			var dist = sqrt(dx*dx + dz*dz)
			var radius = 0.0
			if pp.z == 3:  # coal
				radius = COAL_RADIUS
			elif pp.z == 4:  # wind
				radius = WIND_RADIUS
			if dist <= radius:
				powered = true
				break
		powered_cells[key] = powered

func _update_water_coverage() -> void:
	for pb in placed_buildings:
		var key = "%d,%d" % [pb.x, pb.y]
		var watered = false
		for wt in water_tiles:
			var dx = pb.x - wt.x
			var dz = pb.y - wt.y
			var dist = sqrt(dx*dx + dz*dz)
			if dist <= WATER_RADIUS:
				watered = true
				break
		watered_cells[key] = watered

func _update_water_tiles() -> void:
	water_tiles.clear()
	for x in GRID:
		for z in GRID:
			if _is_water(x, z):
				water_tiles.append(Vector2i(x, z))


func _bk(x: int, z: int) -> String:
	return "%d,%d" % [x, z]


func _is_road_adjacent(x: int, z: int) -> bool:
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			if _is_road_at(x + dx, z + dz):
				return true
	return false


func _try_road(x: int, z: int) -> void:
	if sim_budget < tool_cost_road:
		return
	for b in placed_buildings:
		if b.x == x and b.y == z:
			return
	if _is_water(x, z):
		return
	sim_budget -= tool_cost_road
	var strip := _make_box(Vector3(CELL * 0.95, 0.05, CELL * 0.95),
		Vector3(_wx(x * CELL), 0.025, _wz(z * CELL)),
		Color(0.20, 0.20, 0.22))
	strip.add_to_group("custom_road")
	add_child(strip)
	if not custom_roads.has(Vector2i(x, z)):
		custom_roads.append(Vector2i(x, z))


func _try_bulldoze(x: int, z: int) -> void:
	for i in range(placed_buildings.size()):
		var b: Vector3i = placed_buildings[i]
		if b.x == x and b.y == z:
			var key = "%d,%d" % [x, z]
			# Remove from power_plants if it's a power plant
			if b.z == 3 or b.z == 4:
				for j in power_plants.size():
					if power_plants[j] == Vector3i(x, z, b.z):
						power_plants.remove_at(j)
						break
			powered_cells.erase(key)
			sim_budget += tool_cost_zone / 2
			placed_buildings.remove_at(i)
			_refresh_building_at(x, z)
			return
	for ridx in range(custom_roads.size()):
		if custom_roads[ridx].x == x and custom_roads[ridx].y == z:
			sim_budget += tool_cost_road / 2
			custom_roads.remove_at(ridx)
			for n in get_tree().get_nodes_in_group("custom_road"):
				n.queue_free()
			return


func _is_road_at(x: int, z: int) -> bool:
	if _is_road(x, z):
		return true
	for r in custom_roads:
		if r.x == x and r.y == z:
			return true
	return false


func _toggle_controls() -> void:
	if controls_overlay:
		controls_overlay.visible = not controls_overlay.visible


func _refresh_wanted_label() -> void:
	var node := get_node_or_null("WantedLabel")
	if node == null:
		return
	node.text = "WANTED: %d/5" % wanted_level


func _refresh_controls() -> void:
	if controls_label == null:
		return
	var tool_name: String = ""
	match current_tool:
		"zone_res": tool_name = "RES ZONE $100"
		"zone_com": tool_name = "COM ZONE $100"
		"zone_ind": tool_name = "IND ZONE $100"
		"road": tool_name = "ROAD $10"
		"bulldoze": tool_name = "BULLDOZE"
		"zone_coal": tool_name = "COAL PLANT $250"
		"zone_wind": tool_name = "WIND PLANT $200"
		_: tool_name = "SELECT"
	controls_label.text = "Tool: %s   Speed: %.2fx   [H] Help" % [tool_name, time_speed]






func _cell_has_building(x: int, z: int) -> bool:
	for b in placed_buildings:
		if b.x == x and b.y == z:
			return true
	return false

func _raycast_ground(screen_pos: Vector2) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.INF
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 1000.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	var r2 := space.intersect_ray(q)
	if r2.is_empty():
		# ground is at y=0; solve analytically
		var n: Vector3 = cam.project_ray_normal(screen_pos)
		if absf(n.y) < 0.001:
			return Vector3.INF
		var t := -from.y / n.y
		if t < 0:
			return Vector3.INF
		return from + n * t
	return r2.position


func _make_box(s: Vector3, p: Vector3, c: Color, em := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = s
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	if em:
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 1.5
	m.material_override = mat
	m.position = p
	return m


# Attach 4 small emissive boxes to a car: 2 white headlights at the front, 2 red
# tail lights at the rear. Lights are children of `car` so they inherit its
# rotation/position. Long axis of the body tells us which local axis is "front":
#   long_is_z=true  -> long axis is Z, headlights at -Z, taillights at +Z
#   long_is_z=false -> long axis is X, headlights at -X, taillights at +X
# We store all four lights in car.set_meta("car_lights", [h0, h1, t0, t1])
# so _apply_time() can toggle their emission_enabled with the day/night cycle.
func _add_car_lights(car: MeshInstance3D, long_is_z: bool, half_long: float, half_short: float) -> void:
	var lights: Array[MeshInstance3D] = []
	var head_col := Color(1.0, 0.95, 0.78)
	var tail_col := Color(0.95, 0.18, 0.10)
	var lamp_size := Vector3(0.18, 0.18, 0.18) if long_is_z else Vector3(0.18, 0.18, 0.18)
	# Side offsets are along the SHORT axis so the two lamps sit on the left/right
	# edges of the car body. Inset slightly inward from the body half-width.
	var side_off: float = half_short * 0.55
	if long_is_z:
		# Front (-Z) headlights, rear (+Z) tail lights
		var front_z: float = -half_long * 0.92
		var rear_z: float = half_long * 0.92
		var h_l := _make_lamp(Vector3(side_off, -0.05, front_z), head_col, true)
		var h_r := _make_lamp(Vector3(-side_off, -0.05, front_z), head_col, true)
		var t_l := _make_lamp(Vector3(side_off, -0.05, rear_z), tail_col, true)
		var t_r := _make_lamp(Vector3(-side_off, -0.05, rear_z), tail_col, true)
		car.add_child(h_l); car.add_child(h_r); car.add_child(t_l); car.add_child(t_r)
		lights = [h_l, h_r, t_l, t_r]
	else:
		# Long axis is X: front (-X) headlights, rear (+X) tail lights
		var front_x: float = -half_long * 0.92
		var rear_x: float = half_long * 0.92
		var h_l := _make_lamp(Vector3(front_x, -0.05, side_off), head_col, true)
		var h_r := _make_lamp(Vector3(front_x, -0.05, -side_off), head_col, true)
		var t_l := _make_lamp(Vector3(rear_x, -0.05, side_off), tail_col, true)
		var t_r := _make_lamp(Vector3(rear_x, -0.05, -side_off), tail_col, true)
		car.add_child(h_l); car.add_child(h_r); car.add_child(t_l); car.add_child(t_r)
		lights = [h_l, h_r, t_l, t_r]
	# Store with a per-light color so _apply_time can pick the right brightness
	car.set_meta("car_lights", lights)
	car.set_meta("car_lights_long_is_z", long_is_z)


# Helper for _add_car_lights: one small emissive lamp at a local offset.
# `em` starts ON (we want them visible at night) but _apply_time() will turn
# them off during the day.
func _make_lamp(local_pos: Vector3, col: Color, em: bool) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.18, 0.18, 0.18)
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	if em:
		mat.emission_enabled = false  # off by default; _apply_time() enables at night
		mat.emission = col
		mat.emission_energy_multiplier = 2.2
	m.material_override = mat
	m.position = local_pos
	return m


func _build_ground() -> void:
	var plane := MeshInstance3D.new()
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(GRID * CELL, GRID * CELL)
	plane.mesh = pmesh
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.50, 0.62, 0.32)
	plane.material_override = pmat
	# giant collision box so raycasts hit
	plane.add_child(_make_box(
		Vector3(GRID * CELL * 2, 0.1, GRID * CELL * 2),
		Vector3(0, -0.05, 0),
		Color(0, 0, 0, 0)))
	add_child(plane)


func _build_water() -> void:
	# River along the BOTTOM edge (z > HALF means outside city south)
	# Width: 8m strip, length: extends 8m past the grid on both sides
	var river_y := 0.02
	# River: a thinner strip running along the south edge
	add_child(_make_box(
		Vector3(GRID * CELL + 20, 0.05, 6),
		Vector3(0, river_y, HALF + 4),
		Color(0.30, 0.50, 0.78)))
	# Beach shore just inside the river (north of it)
	add_child(_make_box(
		Vector3(GRID * CELL + 20, 0.04, 1.2),
		Vector3(0, river_y - 0.01, HALF + 1.0),
		Color(0.85, 0.80, 0.65)))
	# Pond: 12x12 blue tile in the lower-LEFT (away from hills)
	add_child(_make_box(
		Vector3(12.0, 0.04, 12.0),
		Vector3(_wx(-3 * CELL), river_y, _wz(GRID * CELL + 3 * CELL)),
		Color(0.30, 0.50, 0.78)))
	# Beach on the east side of pond
	add_child(_make_box(
		Vector3(1.5, 0.04, 13.0),
		Vector3(_wx(-3 * CELL) + 6, river_y - 0.01, _wz(GRID * CELL + 3 * CELL)),
		Color(0.85, 0.80, 0.65)))
	# Tree-line along river bank (north shore, between city and water)
	for x in range(-int(GRID / 2 + 4), int(GRID / 2 + 4), 2):
		add_child(_make_box(Vector3(0.4, 1.0, 0.4),
			Vector3(_wx(x * CELL), 0.5, HALF + 0.5),
			Color(0.45, 0.30, 0.20)))
		add_child(_make_box(Vector3(1.2, 1.5, 1.2),
			Vector3(_wx(x * CELL), 1.75, HALF + 0.5),
			Color(0.20, 0.45, 0.20)))


func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for i in 60:
		var x: int = rng.randi_range(2, GRID - 2)
		var z: int = rng.randi_range(2, GRID - 2)
		if _is_road(x, z):
			continue
		add_child(_make_box(Vector3(0.4, 1.0, 0.4),
			Vector3(_wx(x * CELL), 0.5, _wz(z * CELL)), Color(0.45, 0.30, 0.20)))
		add_child(_make_box(Vector3(1.2, 1.5, 1.2),
			Vector3(_wx(x * CELL), 1.75, _wz(z * CELL)), Color(0.20, 0.45, 0.20)))


func _is_road(x: int, z: int) -> bool:
	return x % ROAD_EVERY == 0 or z % ROAD_EVERY == 0


func _is_water(_x: int, z: int) -> bool:
	# z > GRID - 4 means within the river (south edge of grid)
	return z > GRID - 4


func _in_bounds(x: int, z: int) -> bool:
	return x >= 0 and x < GRID and z >= 0 and z < GRID


func _build_roads() -> void:
	for x in GRID:
		for z in GRID:
			if _is_road(x, z):
				add_child(_make_box(
					Vector3(CELL * 0.9, 0.06, CELL * 0.9),
					Vector3(_wx(x * CELL), 0.03, _wz(z * CELL)),
					Color(0.18, 0.18, 0.18)))


func _zone_color(idx: int) -> Color:
	return [Color(0.85, 0.78, 0.55),
			Color(0.50, 0.65, 0.85),
			Color(0.70, 0.55, 0.40)][idx % 3]


# Density stages: 0 = empty lot, 1 = low (1 story), 2 = medium (2 story),
# 3 = high (3-4 story tower), 4 = landmark (5+ story)
const DENSITY_LOW := 1
const DENSITY_MED := 2
const DENSITY_HIGH := 3
const DENSITY_MAX := 4
var custom_roads: Array[Vector2i] = []
var building_meshes: Array[MeshInstance3D] = []
var cell_density: Dictionary = {}  # key "x,y:z" -> density stage
var cell_color: Dictionary = {}    # key -> color index


func _density_height(d: int) -> float:
	return [0.0, 1.4, 2.6, 4.2, 6.5][clamp(d, 0, 4)]


func _place_building(x: int, z: int, color_idx: int, d: int = 1) -> void:
	var key := "%d,%d" % [x, z]
	cell_density[key] = d
	cell_color[key] = color_idx
	var h: float = _density_height(d)
	var b := _make_box(Vector3(CELL * 0.8, h, CELL * 0.8),
		Vector3(_wx(x * CELL), h * 0.5, _wz(z * CELL)), _zone_color(color_idx))
	b.set_meta("color_idx", color_idx)
	buildings_root.add_child(b)
	placed_buildings.append(Vector3i(x, z, color_idx))
	powered_cells[key] = false
	building_meshes.append(b)


func _refresh_building_at(x: int, z: int) -> void:
	var key := "%d,%d" % [x, z]
	var mesh_idx: int = placed_buildings.find(Vector3i(x, z, cell_color.get(key, 0)))
	if mesh_idx < 0:
		return
	var b := building_meshes[mesh_idx]
	var d: int = cell_density.get(key, 0)
	var h: float = _density_height(d)
	b.scale = Vector3(1, maxf(h, 0.4), 1)
	b.position = Vector3(_wx(x * CELL), h * 0.5, _wz(z * CELL))



func _build_initial_buildings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for x in GRID:
		for z in GRID:
			if _is_road(x, z) or _is_water(x, z):
				continue
			if rng.randf() < 0.55:
				_place_building(x, z, rng.randi() % 3, rng.randi_range(1, 3))


func _build_lamps() -> void:
	for x in range(0, GRID + 1, ROAD_EVERY):
		for z in range(0, GRID + 1, ROAD_EVERY):
			if x > GRID or z > GRID or _is_water(x, z):
				continue
			add_child(_make_box(Vector3(0.1, 1.4, 0.1),
				Vector3(_wx(x * CELL), 0.7, _wz(z * CELL)), Color(0.15, 0.15, 0.18)))
			var h := _make_box(Vector3(0.25, 0.18, 0.25),
				Vector3(_wx(x * CELL), 1.45, _wz(z * CELL)), Color(1.0, 0.85, 0.5), true)
			add_child(h)
			lamps.append(h)


func _build_light_env() -> void:
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.95, 0.85)
	add_child(sun)

	world_env = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	world_env.environment = env
	add_child(world_env)


func _apply_time() -> void:
	var sun_phase: float = clamp((_t - 0.25) / 0.5, 0.0, 1.0)
	var sun_angle: float = sun_phase * PI
	var sun_height: float = sin(sun_angle)
	sun.rotation_degrees = Vector3(-rad_to_deg(asin(sun_height)), -30, 0)
	var is_day := sun_height > 0.0
	sun.light_energy = max(sun_height * 1.2, 0.0)
	sun.light_color = Color(1.0, lerpf(0.6, 0.95, is_day as float), lerpf(0.4, 0.85, is_day as float))
	env.ambient_light_energy = lerpf(0.55, 0.9, is_day as float)
	env.ambient_light_color = Color(0.85, 0.85, 0.95)
	# Weather: rain/storm darkens the sky and reduces ambient
	if weather_ambient_mod < 0.0:
		env.ambient_light_energy = max(0.05, env.ambient_light_energy + weather_ambient_mod)
		env.ambient_light_color = env.ambient_light_color.lerp(Color(0.55, 0.60, 0.72), 0.55)
	if is_day:
		env.background_mode = Environment.BG_SKY
		env.ambient_light_sky_contribution = 1.0
		if env.sky and env.sky.sky_material:
			if weather_ambient_mod < 0.0:
				# Overcast sky when raining: greyer, less saturated
				env.sky.sky_material.sky_top_color = Color(0.40, 0.45, 0.52)
				env.sky.sky_material.sky_horizon_color = Color(0.55, 0.58, 0.62)
			else:
				env.sky.sky_material.sky_top_color = Color(0.25, 0.45, 0.95)
				env.sky.sky_material.sky_horizon_color = Color(0.60, 0.70, 0.95)
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.05, 0.07, 0.15)
		env.ambient_light_sky_contribution = 0.3
	# Lamps: warm pool of light; much stronger at night with slight flicker
	var lamp_e := lerpf(1.8, 0.0, is_day as float)
	var flicker: float = 0.98 + randf() * 0.04
	for lm in lamps:
		var mat: StandardMaterial3D = lm.material_override
		mat.emission_energy_multiplier = lamp_e * flicker
	# Building windows / neon storefronts keyed to time-of-day
	var window_e := lerpf(0.0, 1.4, (not is_day) as float)
	var neon_e := lerpf(0.0, 2.2, (not is_day) as float)
	for i in building_meshes.size():
		var b: Node3D = building_meshes[i]
		var bp: Vector3i = placed_buildings[i]
		var key = "%d,%d" % [bp.x, bp.y]
		var powered: bool = powered_cells.get(key, false)
		var bmat: StandardMaterial3D = b.material_override
		var cidx: int = b.get_meta("color_idx") as int
		bmat.emission_enabled = true
		if is_day:
			bmat.emission = Color(0, 0, 0)
			bmat.emission_energy_multiplier = 0.0
		else:
			if not powered:
				bmat.emission = Color(0, 0, 0)
				bmat.emission_energy_multiplier = 0.0
			elif cidx == 1:
				# Commercial zones get neon storefront glow (magenta/cyan)
				bmat.emission = Color(0.9, 0.25, 0.85)
				bmat.emission_energy_multiplier = neon_e
			else:
				# Residential / industrial get warm window light
				bmat.emission = Color(1.0, 0.85, 0.4)
				bmat.emission_energy_multiplier = window_e

	# Vehicle headlights + tail lights: turn on at night, off by day.
	# Iterate all cars (traffic + parked + police) via the meta key set in
	# _add_car_lights(). car_lights = [h_left, h_right, t_left, t_right].
	var car_lights_on: bool = not is_day
	# Traffic (12 cars in `cars`)
	for car in cars:
		if not is_instance_valid(car):
			continue
		var lights_meta = car.get_meta("car_lights", [])
		if lights_meta == null:
			continue
		for lamp in lights_meta:
			if is_instance_valid(lamp) and lamp.material_override:
				lamp.material_override.emission_enabled = car_lights_on
	# Parked (4 cars in `vehicles`)
	for v in vehicles:
		var vmesh: MeshInstance3D = v.get("mesh")
		if vmesh == null or not is_instance_valid(vmesh):
			continue
		var lights_meta2 = vmesh.get_meta("car_lights", [])
		if lights_meta2 == null:
			continue
		for lamp in lights_meta2:
			if is_instance_valid(lamp) and lamp.material_override:
				lamp.material_override.emission_enabled = car_lights_on
	# Police (2 units in `police`)
	for p in police:
		var pmesh: MeshInstance3D = p.get("mesh")
		if pmesh == null or not is_instance_valid(pmesh):
			continue
		var lights_meta3 = pmesh.get_meta("car_lights", [])
		if lights_meta3 == null:
			continue
		for lamp in lights_meta3:
			if is_instance_valid(lamp) and lamp.material_override:
				lamp.material_override.emission_enabled = car_lights_on
	# Player's current vehicle (if driving)
	if vehicle_in and is_instance_valid(current_vehicle):
		var lights_meta4 = current_vehicle.get_meta("car_lights", [])
		if lights_meta4 != null:
			for lamp in lights_meta4:
				if is_instance_valid(lamp) and lamp.material_override:
					lamp.material_override.emission_enabled = car_lights_on


var _camera: Camera3D

func _build_camera() -> void:
	_camera = Camera3D.new()
	add_child(_camera)
	_refresh_camera()
	_camera.make_current()



func _build_player() -> void:
	player = MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.height = 1.6
	body_mesh.radius = 0.35
	player.mesh = body_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.55, 0.95)  # blue shirt
	mat.roughness = 0.6
	player.material_override = mat
	player.scale = Vector3(1.0, 1.0, 1.0)
	# Start at a road cell (8, 4 = inside grid, on a road row)
	var sx: int = 0  # road x index
	var sz: int = 4  # road z row
	player_pos = Vector3(_wx(sx * CELL + CELL * 0.5), 0.8, _wz(sz * CELL + CELL * 0.5))
	player.position = player_pos
	add_child(player)
	# Head indicator (small sphere above)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	head.mesh = sm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.95, 0.78, 0.65)
	head.material_override = hmat
	head.position = Vector3(0.0, 1.05, 0.0)
	player.add_child(head)


func _update_player(delta: float) -> void:
	if player == null:
		return
	# WASD/arrows: world-relative movement based on camera yaw
	var fwd := Vector3(sin(deg_to_rad(cam_yaw)), 0.0, cos(deg_to_rad(cam_yaw)))
	var right := Vector3(cos(deg_to_rad(cam_yaw)), 0.0, -sin(deg_to_rad(cam_yaw)))
	var move := Vector3.ZERO
	if Input.is_action_pressed("ui_up"):
		move += fwd
	if Input.is_action_pressed("ui_down"):
		move -= fwd
	if Input.is_action_pressed("ui_left"):
		move -= right
	if Input.is_action_pressed("ui_right"):
		move += right
	if move.length() > 0.01:
			move = move.normalized() * player_speed * delta
			var new_pos: Vector3 = player_pos + move
			# Clamp to world bounds (stay on grid + a bit of margin)
			var bound: float = HALF - CELL * 0.5
			new_pos.x = clamp(new_pos.x, -bound, bound)
			new_pos.z = clamp(new_pos.z, -bound, bound)
			# Block: don't walk through buildings (slide along them)
			var cx: int = int(round((new_pos.x + HALF) / CELL))
			var cz: int = int(round((new_pos.z + HALF) / CELL))
			if _cell_has_building(cx, cz):
				# Try X-only move
				var alt_x: Vector3 = Vector3(new_pos.x, player_pos.y, player_pos.z)
				var cx2: int = int(round((alt_x.x + HALF) / CELL))
				var cz2: int = int(round((alt_x.z + HALF) / CELL))
				if not _cell_has_building(cx2, cz2):
					new_pos = alt_x
				else:
					# Try Z-only move
					var alt_z: Vector3 = Vector3(player_pos.x, player_pos.y, new_pos.z)
					var cx3: int = int(round((alt_z.x + HALF) / CELL))
					var cz3: int = int(round((alt_z.z + HALF) / CELL))
					if not _cell_has_building(cx3, cz3):
						new_pos = alt_z
					else:
						# Blocked both ways, no movement
						new_pos = player_pos
			if new_pos.distance_to(player_pos) > 0.001:
				stats_distance_walked += new_pos.distance_to(player_pos)
			player_pos = new_pos
			player.position = player_pos
			# Face the direction of movement
			var yaw_rad: float = atan2(move.x, move.z)
			player.rotation.y = yaw_rad
	# Toggle third-person camera with C
	if Input.is_key_pressed(KEY_C) and not cam_thirdperson:
		cam_thirdperson = true
		_refresh_player_camera()
	elif Input.is_key_pressed(KEY_V) and cam_thirdperson:
		cam_thirdperson = false
		_refresh_camera()
	if cam_thirdperson:
		_refresh_player_camera()


func _refresh_player_camera() -> void:
	var cam: Camera3D = _camera
	if cam == null:
		return
	var offset := Vector3(
		sin(deg_to_rad(cam_player_yaw)) * cos(deg_to_rad(cam_player_pitch)),
		sin(deg_to_rad(cam_player_pitch)),
		cos(deg_to_rad(cam_player_yaw)) * cos(deg_to_rad(cam_player_pitch))
	) * cam_player_dist
	cam.position = player_pos + offset + Vector3(0.0, 1.5, 0.0)
	cam.look_at(player_pos + Vector3(0.0, 1.0, 0.0), Vector3.UP)


func _on_player_pos() -> void:
	pass

func _refresh_camera() -> void:
	if _camera == null:
		return
	var center := Vector3.ZERO
	if cam_topdown:
		_camera.position = center + Vector3(0, 90, 0.01)
		_camera.rotation_degrees = Vector3(-90, 0, 0)
		return
	var pitch := deg_to_rad(cam_pitch)
	var yaw := deg_to_rad(cam_yaw)
	_camera.position = center + Vector3(
		sin(yaw) * cos(pitch) * cam_dist,
		-sin(pitch) * cam_dist,
		cos(yaw) * cos(pitch) * cam_dist)
	_camera.look_at(center, Vector3.UP)


var hud_label: Label
var context_hint_label: Label
var minimap_image: Image
var minimap_texture: ImageTexture
var minimap_sprite: Sprite2D
var minimap_dirty: bool = true
var minimap_grid: Dictionary = {}  # key -> color string
var hud_time_slider: HSlider

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.size = Vector2(1280, 36)
	cl.add_child(bg)
	hud_label = Label.new()
	hud_label.position = Vector2(12, 8)
	hud_label.add_theme_font_size_override("font_size", 18)
	hud_label.add_theme_color_override("font_color", Color(0.95, 0.94, 0.88))
	cl.add_child(hud_label)
	var lbl2 := Label.new()
	lbl2.text = "  Time of Day:"
	lbl2.position = Vector2(1020, 8)
	lbl2.add_theme_font_size_override("font_size", 14)
	lbl2.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	cl.add_child(lbl2)
	hud_time_slider = HSlider.new()
	hud_time_slider.min_value = 0
	hud_time_slider.max_value = 1
	hud_time_slider.step = 0.01
	hud_time_slider.value = _t
	hud_time_slider.position = Vector2(1120, 6)
	hud_time_slider.size = Vector2(150, 24)
	hud_time_slider.value_changed.connect(func(v): _t = v; _apply_time())
	cl.add_child(hud_time_slider)
	_refresh_hud()
	_refresh_wanted_label()
	_update_minimap()
	_build_health_banner()




	# Controls overlay (top-right under time slider)
	controls_overlay = CanvasLayer.new()
	add_child(controls_overlay)
	var ctl_bg := ColorRect.new()
	ctl_bg.color = Color(0, 0, 0, 0.65)
	ctl_bg.size = Vector2(360, 285)
	ctl_bg.position = Vector2(910, 80)
	controls_overlay.add_child(ctl_bg)
	controls_label = Label.new()
	controls_label.position = Vector2(920, 50)
	controls_label.add_theme_font_size_override("font_size", 16)
	controls_label.add_theme_color_override("font_color", Color(0.95, 0.94, 0.88))
	controls_overlay.add_child(controls_label)
	var help := Label.new()
	help.position = Vector2(920, 90)
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(0.95, 0.94, 0.88))
	help.text = "1=Res  2=Com  3=Ind\n4=Road  5=Bulldoze\n6=Coal  7=Wind\n0 = Select\nClick to apply tool\nWASD = Move\nF = Enter/Exit car\nE = Enter building\nSpace = Shoot\nB = Store  TAB = Stats\nG = Raise wanted\nJ = Take damage\nP / Esc = Pause\nC/V = Cam toggle\nH = Hide help\nF5/F9 = Save/Load\n+/- = Speed\n[/] = Tax rate (0-20%)\nT = Top-down\nN = Cycle weather\nM = Next mission"
	controls_overlay.add_child(help)
	# Wanted meter overlay (top-left)
	var wanted_cl := CanvasLayer.new()
	add_child(wanted_cl)
	var wanted_bg := ColorRect.new()
	wanted_bg.color = Color(0.85, 0.10, 0.10, 0.85)
	wanted_bg.size = Vector2(220, 36)
	wanted_bg.position = Vector2(12, 44)
	wanted_cl.add_child(wanted_bg)
	var wanted_lbl := Label.new()
	wanted_lbl.name = "WantedLabel"
	wanted_lbl.position = Vector2(20, 48)
	wanted_lbl.add_theme_font_size_override("font_size", 16)
	wanted_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	wanted_lbl.text = "WANTED: 0/5"
	wanted_cl.add_child(wanted_lbl)
	_refresh_controls()

func _abs_budget_fmt() -> String:
	var v: int = sim_budget if sim_budget >= 0 else -sim_budget
	if v >= 1000000: return "%d.%dM" % [v / 1000000, (v % 1000000) / 100000]
	if v >= 1000: return "%d,%03d" % [v / 1000, v % 1000]
	return str(v)

func _refresh_demand_bars() -> void:
	# Three coloured bars at the right side of the HUD: R (green) C (blue) I (red)
	if demand_bars_root == null:
		return
	for child in demand_bars_root.get_children():
		child.queue_free()
	var bar_w: float = 120.0
	var bar_h: float = 14.0
	var base_x: float = 760.0
	var base_y: float = 8.0
	var labels: Array = ["R", "C", "I"]
	var cols: Array = [Color(0.40, 0.85, 0.40), Color(0.40, 0.55, 0.95), Color(0.85, 0.55, 0.30)]
	var vals: Array = [sim_residential_demand, sim_commercial_demand, sim_industrial_demand]
	for i in range(3):
		var lbl := Label.new()
		lbl.text = labels[i]
		lbl.add_theme_color_override("font_color", cols[i])
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.position = Vector2(base_x, base_y + i * (bar_h + 2))
		demand_bars_root.add_child(lbl)
		var bg := ColorRect.new()
		bg.color = Color(0.1, 0.1, 0.1, 0.7)
		bg.position = Vector2(base_x + 16, base_y + i * (bar_h + 2))
		bg.size = Vector2(bar_w, bar_h)
		demand_bars_root.add_child(bg)
		var fill := ColorRect.new()
		fill.color = cols[i]
		fill.position = Vector2(base_x + 16, base_y + i * (bar_h + 2))
		fill.size = Vector2(bar_w * (vals[i] / 100.0), bar_h)
		demand_bars_root.add_child(fill)

func _build_context_hint() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 4
	add_child(cl)
	context_hint_label = Label.new()
	context_hint_label.add_theme_font_size_override("font_size", 18)
	context_hint_label.add_theme_color_override("font_color", Color(1, 1, 1))
	context_hint_label.position = Vector2(10, 10)
	cl.add_child(context_hint_label)


func _update_context_hint() -> void:
	if context_hint_label == null:
		return
	var hint: String = ""
	if menu_cl:
		hint = "Press 1=EASY, 2=NORMAL, 3=HARD, then ENTER to start"
	elif current_mission.is_empty() and not game_complete:
		hint = "WASD to walk. Place buildings with 1/2/3. Pick a mission: press M."
	elif game_complete:
		hint = "GAME COMPLETE. Press R to restart, or keep playing."
	elif not current_mission.is_empty():
		hint = "[MISSION] " + current_mission.get("name", current_mission.get("title", "?")) + ": " + current_mission.get("objective", "")
	if interior_view:
		hint += "  | Press ESC to leave building"
	if vehicle_in:
		hint += "  | Driving. F to exit."
	if wanted_level >= 3:
		hint += "  | WANTED " + str(wanted_level) + " STARS - run!"
	if not event_active.is_empty():
		hint += "  | EVENT: walk to red marker (" + str(int(event_active.get("life", 0))) + "s)"
	if buy_menu_open:
		hint = "STORE - press 1/2/3/4 to buy, 0 to close"
	context_hint_label.text = hint
	# Color changes with state
	var col: Color = Color(1, 1, 1)
	if wanted_level >= 3:
		col = Color(1, 0.5, 0.4)
	elif wanted_level > 0:
		col = Color(1, 0.8, 0.4)
	elif not current_mission.is_empty():
		col = Color(1, 0.95, 0.4)
	context_hint_label.add_theme_color_override("font_color", col)


func _refresh_hud() -> void:
	if hud_label:
		var hp_str: String = "HP:%d" % player_health
		var bsign: String = "-" if sim_budget < 0 else ""
		hud_label.text = "SYNDICATE CITY   %s   Day %d   $%s%s   Pop %d   TAX %d%%   placed=%d" % [
			hp_str,
			sim_day_count,
			bsign,
			_abs_budget_fmt(),
			sim_population,
			int(sim_residential_tax_rate * 100.0),
			placed_buildings.size()]
	if demand_bars_root != null:
		_refresh_demand_bars()
var traffic_dots: Array[MeshInstance3D] = []
var traffic_paths: Array = []  # each = Array of Vector3 world positions
# Traffic cones: dynamic roadblocks that spawn at events + police roadblocks
var traffic_cones: Array[MeshInstance3D] = []  # active cones currently on the map
var cone_pool: Array[MeshInstance3D] = []      # pre-built cones (visible=false until placed)
const CONE_SPAWN_RADIUS := 3.0                 # scatter radius around an event


func _build_traffic() -> void:
	# Build horizontal road paths (every 4th row)
	for z in range(0, GRID, ROAD_EVERY):
		if z > GRID - 6:
			continue
		var path: Array[Vector3] = []
		for x in range(0, GRID):
			path.append(Vector3(_wx(x * CELL), 0.5, _wz(z * CELL)))
		traffic_paths.append(path)
	# Build vertical road paths
	for x in range(0, GRID, ROAD_EVERY):
		var path: Array[Vector3] = []
		for z in range(0, GRID):
			path.append(Vector3(_wx(x * CELL), 0.5, _wz(z * CELL)))
		traffic_paths.append(path)
	# Spawn dots
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 30:
		var path: Array = traffic_paths[rng.randi() % traffic_paths.size()]
		var dot := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.3
		mesh.height = 0.6
		dot.mesh = mesh
		var mat := StandardMaterial3D.new()
		var is_vert: bool = path[0].x == path[-1].x
		mat.albedo_color = Color(0.9, 0.9, 0.6) if is_vert else Color(0.9, 0.7, 0.3)
		mat.emission = mat.albedo_color
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 1.5
		dot.material_override = mat
		add_child(dot)
		dot.set_meta("path", path)
		dot.set_meta("t", rng.randf())
		traffic_dots.append(dot)

# Traffic cones: pre-build a pool of 20 cones (visible=false) that _place_cone()
# repositions and shows. Cones are orange, emissive, and pulse at 3 Hz so they
# stand out at night. They spawn at random events (roadblocks) and police
# roadblocks (wanted >= 3).
const CONE_POOL_SIZE := 20
const CONE_PULSE_HZ := 3.0

func _build_cone_pool() -> void:
	for i in CONE_POOL_SIZE:
		var c := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		# Classic traffic cone: wide base, narrow top, tapered
		mesh.top_radius = 0.06
		mesh.bottom_radius = 0.32
		mesh.height = 0.55
		c.mesh = mesh
		var mat := StandardMaterial3D.new()
		# Bright orange, emissive so cones glow at night
			(mat.albedo_color = Color(1.0, 0.35, 0.05)
			 mat.emission_enabled = true
			 mat.emission = Color(1.0, 0.35, 0.05)
			 mat.emission_energy_multiplier = 1.2
			 mat.roughness = 0.7
			 c.material_override = mat
			 c.position = Vector3(0, 0.275, 0)
			 c.visible = false
			 add_child(c)
			 cone_pool.append(c)

# Place a cone at `pos` (world Vector3). Returns the cone MeshInstance3D or null
# if the pool is exhausted. The cone is repositioned, shown, and tagged with
# its spawn time so _update_traffic_cones() can pulse it.
func _place_cone(pos: Vector3) -> MeshInstance3D:
	for c in cone_pool:
		if not c.visible:
			c.position = pos + Vector3(0, 0.275, 0)
			c.visible = true
			c.set_meta("spawn_t", Time.get_ticks_msec() / 1000.0)
			return c
	return null

# Remove ALL active cones (used when a random event is resolved/failed).
func _clear_all_cones() -> void:
	for c in traffic_cones:
		if is_instance_valid(c):
			c.visible = false
			c.set_meta("spawn_t", 0.0)
	traffic_cones.clear()

# Pulse cones at CONE_PULSE_HZ so they flicker like real traffic cones.
# Also recycles cones that have been alive too long (> 60s).
func _update_traffic_cones(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var to_remove: Array[MeshInstance3D] = []
	for c in traffic_cones:
		if not is_instance_valid(c):
			to_remove.append(c)
			continue
		var spawn_t: float = c.get_meta("spawn_t") as float
		# Recycle cones older than 60s
		if spawn_t > 0.0 and now - spawn_t > 60.0:
			c.visible = false
			to_remove.append(c)
			continue
		# Pulsing emission: 0.6..1.8 energy at CONE_PULSE_HZ
		var mat: StandardMaterial3D = c.material_override
		if mat:
			var pulse := 0.6 + 0.6 * abs(sin(now * TAU * CONE_PULSE_HZ))
			mat.emission_energy_multiplier = pulse
	for c in to_remove:
		traffic_cones.erase(c)

# Spawn a ring of 3-5 cones around a world position (used for random events
# that block roads — mugging, car theft, fire all get a roadblock).
func _spawn_cone_ring(pos: Vector3, count: int = 4) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 1000 + pos.z)
	for i in count:
		var angle: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(1.0, CONE_SPAWN_RADIUS)
		var offset := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var c := _place_cone(pos + offset)
		if c:
			traffic_cones.append(c)

# Spawn a police roadblock: 4 cones in a line across the nearest road to the
# player. Called when wanted >= 3 so police can set up barriers during chases.
func _spawn_police_roadblock() -> void:
	# Find the nearest traffic path to the player
	var best_path: Array = []
	var best_d: float = 9999.0
	for path in traffic_paths:
		var mid := path[path.size() / 2]
		var d := player_pos.distance_to(mid)
		if d < best_d:
			best_d = d
			best_path = path
	if best_path.is_empty():
		return
	# Place 4 cones evenly along the middle 60% of the path
	var start_idx := int(best_path.size() * 0.2)
	var end_idx := int(best_path.size() * 0.8)
	if end_idx <= start_idx:
		return
	for i in range(4):
		var idx := start_idx + (end_idx - start_idx) * i / 3
		var c := _place_cone(best_path[idx])
		if c:
			traffic_cones.append(c)


func _update_traffic(delta: float) -> void:
	for dot in traffic_dots:
		var path: Array = dot.get_meta("path")
		var t: float = dot.get_meta("t")
		t = fmod(t + delta * 0.15, 1.0)
		dot.set_meta("t", t)
		var idx := int(t * (path.size() - 1))
		var frac := t * (path.size() - 1) - idx
		var a: Vector3 = path[idx]
		var b: Vector3 = path[min(idx + 1, path.size() - 1)]
		dot.position = a.lerp(b, frac)





func _build_npcs() -> void:
	# Spawn 12 pedestrians on roads. Each walks a straight segment back and forth.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for n in 12:
		var road_x: int = rng.randi_range(1, 7) * ROAD_EVERY
		var road_z: int = rng.randi_range(1, 7) * ROAD_EVERY
		# Path: 8 cells in +x direction along z=road_z
		var p0: Vector3 = Vector3(_wx(road_x * CELL), 0.0, _wz(road_z * CELL + CELL * 0.5))
		var p1: Vector3 = Vector3(_wx((road_x + 8) * CELL), 0.0, _wz(road_z * CELL + CELL * 0.5))
		var npc := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.height = 1.4
		capsule.radius = 0.25
		npc.mesh = capsule
		var mat := StandardMaterial3D.new()
		var palette := [Color(0.85, 0.20, 0.20), Color(0.20, 0.85, 0.40), Color(0.95, 0.85, 0.20), Color(0.80, 0.40, 0.95)]
		mat.albedo_color = palette[rng.randi() % palette.size()]
		npc.material_override = mat
		npc.position = p0
		add_child(npc)
		npcs.append({
			"mesh": npc,
			"path": [p0, p1],
			"t": 0.0,
			"dir": 1,
			"speed": rng.randf_range(1.2, 2.2),
		})


func _update_npcs(delta: float) -> void:
	# At night, NPCs slow down / head home
	var is_day: bool = _t > 0.3 and _t < 0.75
	for n in npcs:
		# Faster during day, slower at night
		n["speed"] = lerpf(0.3, 1.0, 1.0 if is_day else 0.2)
		var t: float = n["t"]
		var day_mult: float = 1.0 if (_t > 0.3 and _t < 0.75) else 0.35
		t += delta * n["speed"] * n["dir"] * day_mult / (n["path"][1] - n["path"][0]).length()
		if t > 1.0:
			t = 1.0
			n["dir"] = -1
		elif t < 0.0:
			t = 0.0
			n["dir"] = 1
		n["t"] = t
		var pos: Vector3 = n["path"][0].lerp(n["path"][1], t)
		pos.y = 0.7
		n["mesh"].position = pos
		# Face direction
		var fwd: Vector3 = (n["path"][1] - n["path"][0]).normalized() * n["dir"]
		if fwd.length() > 0.01:
			n["mesh"].rotation.y = atan2(fwd.x, fwd.z)


func _try_enter_building() -> void:
	if interior_view:
		return
	# Find nearest building cell within 4m
	var nearest: Vector2i = Vector2i(-1, -1)
	var best_d: float = 9999.0
	for b in placed_buildings:
		var bpos: Vector3 = Vector3(_wx(b.x * CELL), 0, _wz(b.y * CELL))
		var d: float = player_pos.distance_to(bpos)
		if d < best_d:
			best_d = d
			nearest = Vector2i(b.x, b.y)
	if best_d > 3.5:
		return
	_enter_building(nearest.x, nearest.y)


func _enter_building(x: int, z: int) -> void:
	_play_enter_building_sound()
	# Check if this is the bank
	if Vector3(_wx(x * CELL), 0, _wz(z * CELL)).distance_to(bank_pos) < 1.0 and wanted_level < 3:
		# Walk in clean and you can start the heist
		_announce("BANK - just browsing. The heist comes later in the mission chain.", Color(0.6, 0.9, 0.6))
	interior_view = true
	interior_root = Node3D.new()
	add_child(interior_root)
	# Floor (small dark plane)
	var floor := _make_box(Vector3(2.5, 0.05, 2.5),
		Vector3(0, 0, 0),
		Color(0.30, 0.25, 0.20))
	floor.position = Vector3(_wx(x * CELL), 0.1, _wz(z * CELL))
	interior_root.add_child(floor)
	# Walls
	var wall_mat_color: Color = Color(0.70, 0.65, 0.55)
	interior_root.add_child(_make_box(Vector3(2.5, 2.5, 0.1),
		Vector3(_wx(x * CELL) - 1.2, 1.25, _wz(z * CELL)),
		wall_mat_color))
	interior_root.add_child(_make_box(Vector3(2.5, 2.5, 0.1),
		Vector3(_wx(x * CELL) + 1.2, 1.25, _wz(z * CELL)),
		wall_mat_color))
	interior_root.add_child(_make_box(Vector3(0.1, 2.5, 2.5),
		Vector3(_wx(x * CELL), 1.25, _wz(z * CELL) - 1.2),
		wall_mat_color))
	# Roof
	interior_root.add_child(_make_box(Vector3(2.5, 0.1, 2.5),
		Vector3(_wx(x * CELL), 2.6, _wz(z * CELL)),
		Color(0.40, 0.35, 0.30)))
	# Richer props based on building type (use color_idx)
	var color_idx: int = _bk(x, z).length()  # hash by string for some variety
	var interior_type: int = (x * 7 + z * 13) % 4  # 0=home, 1=shop, 2=office, 3=vault
	if interior_type == 0:
		# Apartment: bed, table, couch
		interior_root.add_child(_make_box(Vector3(1.0, 0.3, 0.6), Vector3(_wx(x * CELL) - 0.6, 0.25, _wz(z * CELL) - 0.6), Color(0.7, 0.4, 0.4)))  # bed
		interior_root.add_child(_make_box(Vector3(0.4, 0.5, 0.4), Vector3(_wx(x * CELL) + 0.5, 0.3, _wz(z * CELL) - 0.6), Color(0.5, 0.35, 0.2)))  # table
		interior_root.add_child(_make_box(Vector3(0.8, 0.4, 0.4), Vector3(_wx(x * CELL), 0.25, _wz(z * CELL) + 0.5), Color(0.6, 0.5, 0.4)))  # couch
	elif interior_type == 1:
		# Shop: counter, shelves
		interior_root.add_child(_make_box(Vector3(1.4, 0.7, 0.3), Vector3(_wx(x * CELL), 0.4, _wz(z * CELL) - 0.85), Color(0.6, 0.5, 0.3)))  # counter
		for sx in [-0.7, 0.0, 0.7]:
			interior_root.add_child(_make_box(Vector3(0.2, 0.4, 0.5), Vector3(_wx(x * CELL) + sx - 0.3, 0.3, _wz(z * CELL) + 0.6), Color(0.7, 0.6, 0.4)))  # shelf
	elif interior_type == 2:
		# Office: desk, chair, computer
		interior_root.add_child(_make_box(Vector3(0.8, 0.5, 0.4), Vector3(_wx(x * CELL) - 0.4, 0.3, _wz(z * CELL) - 0.6), Color(0.5, 0.35, 0.25)))  # desk
		interior_root.add_child(_make_box(Vector3(0.3, 0.6, 0.3), Vector3(_wx(x * CELL) - 0.4, 0.35, _wz(z * CELL) - 0.2), Color(0.3, 0.3, 0.4)))  # chair
		interior_root.add_child(_make_box(Vector3(0.4, 0.3, 0.05), Vector3(_wx(x * CELL) - 0.4, 0.65, _wz(z * CELL) - 0.85), Color(0.1, 0.1, 0.15)))  # monitor
	else:
		# Vault: safe, money pile, gold bars
		interior_root.add_child(_make_box(Vector3(0.8, 1.0, 0.8), Vector3(_wx(x * CELL) - 0.5, 0.55, _wz(z * CELL) - 0.5), Color(0.3, 0.3, 0.4)))  # safe
		for gx in range(3):
			for gz in range(3):
				interior_root.add_child(_make_box(Vector3(0.1, 0.05, 0.1), Vector3(_wx(x * CELL) + 0.3 + gx * 0.15, 0.08, _wz(z * CELL) + 0.3 + gz * 0.15), Color(0.9, 0.75, 0.3)))  # gold
	# Sign on the back wall
	var sign_color: Color = Color(0.9, 0.8, 0.4)
	var sign_text: String = "HOME"
	if interior_type == 1:
		sign_text = "SHOP"
	elif interior_type == 2:
		sign_text = "OFFICE"
	elif interior_type == 3:
		sign_text = "VAULT"
	# (Label3D would be best; skip for now, the boxes are distinctive enough)
	# Hide the exterior, show only interior + dim lighting
	# Easiest: set all OTHER nodes' visible = false, but we tracked them via interior_root separation
	# Move player to interior center
	player_pos = Vector3(_wx(x * CELL), 0.7, _wz(z * CELL) + 0.5)
	player.position = player_pos
	# Switch to interior camera
	cam_thirdperson = true
	cam_player_dist = 2.0
	cam_player_pitch = -10.0
	_refresh_player_camera()


func _exit_building() -> void:
	if not interior_view:
		return
	interior_view = false
	if interior_root:
		interior_root.queue_free()
		interior_root = null
	cam_player_dist = 12.0
	cam_player_pitch = -25.0


func _try_enter_vehicle() -> void:
	if vehicle_in:
		return
	# Find nearest car within 3m
	var best: Dictionary = {}
	var best_d: float = 9999.0
	for v in vehicles:
		var d: float = player_pos.distance_to(v["pos"])
		if d < best_d:
			best_d = d
			best = v
	if best_d > 3.5:
		return
	vehicle_in = true
	current_vehicle = best["mesh"]
	current_vehicle_pos = best["pos"]
	current_vehicle_yaw = best["yaw"]
	current_vehicle_speed = 0.0
	# Hide player mesh; show in vehicle
	player.visible = false
	# Adjust camera
	cam_player_dist = 7.0
	cam_player_pitch = -15.0


func _exit_vehicle() -> void:
	if not vehicle_in:
		return
	vehicle_in = false
	# Save vehicle state
	for v in vehicles:
		if v["mesh"] == current_vehicle:
			v["pos"] = current_vehicle_pos
			v["yaw"] = current_vehicle_yaw
			v["speed"] = current_vehicle_speed
			break
	# Place player next to the vehicle
	var exit_offset := Vector3(-2.5, 0.0, 0.0).rotated(Vector3.UP, current_vehicle_yaw)
	player_pos = current_vehicle_pos + exit_offset
	player.position = player_pos
	player.visible = true
	current_vehicle = null
	cam_player_dist = 12.0
	cam_player_pitch = -25.0




func _check_vehicle_hits() -> void:
	# Hit pedestrians
	for n in npcs:
		var d: float = n["mesh"].position.distance_to(current_vehicle_pos)
		if d < 1.5:
			# Knock them back
			var away: Vector3 = (n["mesh"].position - current_vehicle_pos).normalized()
			n["mesh"].position += away * 4.0
			_add_wanted(1)
			_play_crash_sound()
			# Mark them as hit (visual: turn darker)
			n["mesh"].material_override.albedo_color = Color(0.4, 0.05, 0.05)
	# Hit other parked cars (vehicles list)
	for v in vehicles:
		if v["mesh"] == current_vehicle:
			continue
		var d2: float = v["pos"].distance_to(current_vehicle_pos)
		if d2 < 2.5:
			# Push the parked car
			var push: Vector3 = (v["pos"] - current_vehicle_pos).normalized()
			v["pos"] += push * 1.5
			v["mesh"].position = v["pos"]
			current_vehicle_speed *= 0.4  # bounce
			_play_crash_sound()
			_add_wanted(1)

func _update_vehicle(delta: float) -> void:
	if not vehicle_in or current_vehicle == null:
		return
	# Acceleration / brake
	var accel: float = 0.0
	if Input.is_action_pressed("ui_up"):
		accel = 14.0
	elif Input.is_action_pressed("ui_down"):
		accel = -10.0
	else:
		# Drag
		current_vehicle_speed *= max(0.0, 1.0 - delta * 4.0)
	current_vehicle_speed += accel * delta
	current_vehicle_speed = clamp(current_vehicle_speed, -8.0, 18.0)
	# Steering (only when moving)
	var steer: float = 0.0
	if Input.is_action_pressed("ui_left"):
		steer = -1.0
	elif Input.is_action_pressed("ui_right"):
		steer = 1.0
	if abs(current_vehicle_speed) > 0.1:
		current_vehicle_yaw += steer * (1.6 * delta) * sign(current_vehicle_speed)
	# Move
	var fwd := Vector3(sin(current_vehicle_yaw), 0.0, cos(current_vehicle_yaw))
	var new_pos: Vector3 = current_vehicle_pos + fwd * current_vehicle_speed * delta
	# World bounds
	var bound: float = HALF - CELL * 0.5
	new_pos.x = clamp(new_pos.x, -bound, bound)
	new_pos.z = clamp(new_pos.z, -bound, bound)
	current_vehicle_pos = new_pos
	current_vehicle.position = new_pos
	current_vehicle.rotation.y = current_vehicle_yaw
	# Move player too (so camera follows)
	player_pos = new_pos
	player.position = new_pos
	# Hit detection
	if abs(current_vehicle_speed) > 1.0:
		_check_vehicle_hits()


func _is_player_in_vehicle() -> bool:
	return vehicle_in


func _build_police() -> void:
	# 2 police cars parked on a far road
	for i in range(2):
		var px: int = 0
		var pz: int = (4 + i * 8) * ROAD_EVERY
		var pos := Vector3(_wx(px * CELL + CELL * 0.5), 0.4, _wz(pz * CELL + CELL * 0.5))
		var car := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.8, 0.7, 3.6)
		car.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.10, 0.15, 0.50)  # dark blue
		car.material_override = mat
		car.position = pos
		# Night lights so police look like they're chasing with high beams on at night
		_add_car_lights(car, true, 1.8, 0.9)
		add_child(car)
		# Roof light bar
		var lightbar := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(1.6, 0.15, 0.4)
		lightbar.mesh = lm
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.10, 0.10, 0.10)
		lmat.emission_enabled = true
		lmat.emission = Color(0.9, 0.2, 0.2)
		lmat.emission_energy_multiplier = 0.5
		lightbar.material_override = lmat
		lightbar.position = pos + Vector3(0.0, 0.55, 0.0)
		add_child(lightbar)
		police.append({
			"mesh": car,
			"light": lightbar,
			"pos": pos,
			"yaw": 0.0,
			"speed": 0.0,
		})


var _police_siren_cooldown: float = 0.0
var _police_roadblock_active: bool = false  # prevent respawning roadblocks every frame

func _update_police(delta: float) -> void:
	# Chase player when wanted > 0; otherwise return to station
	for p in police:
		var dist: float = p["pos"].distance_to(player_pos)
		if wanted_level > 0 and dist > 3.0:
			# Move toward player
			var to_player: Vector3 = (player_pos - p["pos"])
			to_player.y = 0
			if to_player.length() > 0.1:
				var target_yaw: float = atan2(to_player.x, to_player.z)
				# Smooth turn
				var diff: float = target_yaw - p["yaw"]
				while diff > PI: diff -= TAU
				while diff < -PI: diff += TAU
				p["yaw"] += diff * min(1.0, delta * 4.0)
				var forward_speed: float = 12.0 + wanted_level * 4.0
				p["speed"] = lerpf(p["speed"], forward_speed, min(1.0, delta * 4.0))
				var fwd := Vector3(sin(p["yaw"]), 0.0, cos(p["yaw"]))
				p["pos"] += fwd * p["speed"] * delta
		else:
			# Return to idle
			p["speed"] *= max(0.0, 1.0 - delta * 3.0)
		p["mesh"].position = p["pos"]
		p["mesh"].rotation.y = p["yaw"]
		p["light"].position = p["pos"] + Vector3(0.0, 0.55, 0.0)
		# Flash the lights when chasing
		if wanted_level > 0:
			var phase: float = fmod(Time.get_ticks_msec() / 200.0, 2.0)
			var flash_col: Color = Color(0.9, 0.2, 0.2) if phase < 1.0 else Color(0.2, 0.4, 0.9)
			p["light"].material_override.emission = flash_col
	# Police roadblock: at wanted >= 3, spawn cones across the nearest road
	# to the player so police can set up barriers during chases.
	if wanted_level >= 3 and not _police_roadblock_active:
		_spawn_police_roadblock()
		_police_roadblock_active = true
		_announce("POLICE ROADBLOCK - find another route!", Color(1, 0.3, 0.3))
	elif wanted_level < 3 and _police_roadblock_active:
		# Clear the roadblock when wanted drops
		_clear_all_cones()
		_police_roadblock_active = false
# Police siren cooldown (function level)
	_police_siren_cooldown -= delta
	if wanted_level > 0 and _police_siren_cooldown <= 0.0:
		_play_police_sound()
		_police_siren_cooldown = 0.6
# Catch any police that touches player (function level)
	for po in police:
		if wanted_level > 0 and po["pos"].distance_to(player_pos) < 1.5:
			# Police rams player - deal damage proportional to police speed
			var ramspeed: float = float(po.get("speed", 0.0))
			if ramspeed > 8.0:
				# Damage from being rammed
				if player_invulnerable <= 0.0:
					var dmg: int = int(clamp(ramspeed * 1.5, 8.0, 30.0))
					player_health -= dmg
					_announce("HIT BY POLICE (-" + str(dmg) + " HP)", Color(1, 0.3, 0.3))
					_play_beep(110, 0.15, 0.4)
					player_invulnerable = 0.8
					damage_flash = 0.2
					# Smash sound
				if ramspeed > 14.0:
					_play_crash_sound()
				if player_health <= 0:
					# Death handled in _update_player_status
					pass
			else:
				_busted()
			break


func _busted() -> void:
	# Getting caught mid-escape loses the heist (and the loot) - without this
	# the wanted reset below would count as a successful getaway.
	if current_mission.get("id") == "the_big_heist" and current_mission.get("heist_stage") == "escape" and current_mission.get("status") == "active":
		sim_budget -= 5000
		_announce("BUSTED! Heist failed, loot confiscated.", Color(1, 0.4, 0.4))
		_fail_current_mission()
	# Reset wanted, dock budget, take player to nearest cell (the police station)
	wanted_level = 0
	var dock: int = 200
	if difficulty == 2:
		dock = 500
	elif difficulty == 0:
		dock = 50
	sim_budget -= dock
	if difficulty == 2:
		player_health = max(0, player_health - 30)  # hard mode: police beat you
	# Send player back to a road cell
	player_pos = Vector3(_wx(4 * CELL), 0.7, _wz(8 * CELL))
	player.position = player_pos
	if vehicle_in:
		_exit_vehicle()


func _add_wanted(amount: int) -> void:
	var amt: int = amount
	if difficulty == 2:
		amt = int(amt * 1.5)
	elif difficulty == 0:
		amt = max(1, int(amt * 0.5))
	wanted_level = clamp(wanted_level + amt, 0, 5)
	wanted_timer = 10.0  # seconds before it starts decaying


func _update_wanted(delta: float) -> void:
	if wanted_level > 0:
		_decay_wanted(delta)
	_update_player_status(delta)
	_update_announcement(delta)
	_update_context_hint()
	_update_damage_flash(delta)
	total_play_time += delta
	_update_random_events(delta)
	if not game_complete and _story_missions_done() >= MISSION_CHAIN.size():
		_show_game_complete()


func _story_missions_done() -> int:
	var n: int = 0
	for id in MISSION_CHAIN:
		if completed_missions.has(id):
			n += 1
	return n


func _decay_wanted(delta: float) -> void:
	# Inside building: lose wanted 2x faster
	var decay: float = delta
	if interior_view:
		decay *= 2.0
	wanted_timer -= decay
	if wanted_timer <= 0.0:
		wanted_level = max(0, wanted_level - 1)
		wanted_timer = 8.0
	# If wanted is 5 for too long, current mission fails
	if wanted_level == 5 and current_mission and not current_mission.is_empty():
		if not current_mission.get("fail_timer", 0.0):
			current_mission["fail_timer"] = 0.0
		current_mission["fail_timer"] = current_mission.get("fail_timer", 0.0) + delta
		if current_mission["fail_timer"] > 12.0:
			# Mission failed
			stats_missions_failed += 1
			_announce("MISSION FAILED: " + str(current_mission.get("name", current_mission.get("title", "?"))) + " - Wanted too high!", Color(1, 0.4, 0.4))
			_fail_current_mission()


func _update_damage_flash(delta: float) -> void:
	if damage_flash > 0.0:
		damage_flash -= delta
		if damage_flash_cl == null:
			damage_flash_cl = CanvasLayer.new()
			damage_flash_cl.layer = 11
			add_child(damage_flash_cl)
			var fr := ColorRect.new()
			fr.color = Color(1, 0, 0, 0.3)
			fr.size = Vector2(1280, 720)
			damage_flash_cl.add_child(fr)
		if damage_flash_cl:
			var fade: float = clamp(damage_flash / 0.2, 0.0, 1.0)
			for c in damage_flash_cl.get_children():
				(c as ColorRect).color.a = 0.3 * fade
		if damage_flash <= 0.0 and damage_flash_cl:
			damage_flash_cl.queue_free()
			damage_flash_cl = null





func _update_player_status(delta: float) -> void:
	# Invulnerability frames
	if player_invulnerable > 0.0:
		player_invulnerable -= delta
		# Blink the player mesh
		if player:
			var v: float = abs(sin(Time.get_ticks_msec() * 0.02))
			player.visible = v > 0.4
	else:
		if player:
			player.visible = true
	# Clamp health, kill if zero
	if player_health <= 0 and not game_over:
		_on_player_death()
	# Ammo reload at home? No, buy at store.


var game_over: bool = false
var game_over_cl: CanvasLayer


func _show_game_over() -> void:
	game_over = true
	game_over_cl = CanvasLayer.new()
	game_over_cl.layer = 13
	add_child(game_over_cl)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.92)
	bg.size = Vector2(1280, 720)
	game_over_cl.add_child(bg)
	var t := Label.new()
	t.text = "YOU DIED"
	t.position = Vector2(440, 200)
	t.add_theme_font_size_override("font_size", 96)
	t.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	game_over_cl.add_child(t)
	var s := Label.new()
	s.text = "Score: $" + str(sim_budget + stats_money_earned)
	s.position = Vector2(490, 340)
	s.add_theme_font_size_override("font_size", 32)
	s.add_theme_color_override("font_color", Color(1, 1, 1))
	game_over_cl.add_child(s)
	var d := Label.new()
	d.text = "Day " + str(sim_day_count) + " - " + str(completed_missions.size()) + " missions done"
	d.position = Vector2(450, 400)
	d.add_theme_font_size_override("font_size", 22)
	d.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	game_over_cl.add_child(d)
	var r := Label.new()
	r.text = "Press R to respawn (-$500) | Esc to quit"
	r.position = Vector2(400, 480)
	r.add_theme_font_size_override("font_size", 24)
	r.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	game_over_cl.add_child(r)


func _respawn_after_game_over() -> void:
	game_over = false
	if game_over_cl:
		game_over_cl.queue_free()
		game_over_cl = null
	sim_budget -= 500
	total_respawns += 1
	player_health = player_max_health
	player_invulnerable = 3.0
	wanted_level = 0
	player_pos = Vector3(_wx(8 * CELL), 0.7, _wz(12 * CELL))
	if player:
		player.position = player_pos
	if vehicle_in:
		_exit_vehicle()
	_announce("RESPAWNED AT HOSPITAL (-$500)", Color(0.7, 0.9, 0.7))


func _on_player_death() -> void:
	total_deaths += 1
	# Easy mode: quick respawn. Normal/Hard: GAME OVER
	if difficulty == 0:
		player_health = player_max_health
		ammo = max_ammo
		sim_budget = max(sim_budget, 1000)
	else:
		_show_game_over()
		return
	if difficulty == 0:
		# Easy mode: restore some inventory
		ammo = max_ammo
		sim_budget = max(sim_budget, 1000)
	player_invulnerable = 3.0
	wanted_level = max(0, wanted_level - 2)
	# Spawn player at hospital area
	player_pos = Vector3(_wx(8 * CELL), 0.7, _wz(12 * CELL))
	if player:
		player.position = player_pos
	if vehicle_in:
		_exit_vehicle()
	_announce("RESPAWNED AT HOSPITAL", Color(0.7, 0.9, 0.7))
	_play_beep(220, 0.3, 0.4)


func _announce(text: String, col: Color = Color(1, 0.85, 0.2)) -> void:
	# Set the text and reset the timer; displayed in _process for a few seconds
	if announcement_label == null:
		# Build it
		var cl := CanvasLayer.new()
		cl.layer = 8
		add_child(cl)
		announcement_label = Label.new()
		announcement_label.add_theme_font_size_override("font_size", 36)
		announcement_label.add_theme_color_override("font_color", col)
		announcement_label.position = Vector2(640, 240)
		announcement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		announcement_label.size = Vector2(800, 50)
		cl.add_child(announcement_label)
	announcement_label.text = text
	announcement_label.add_theme_color_override("font_color", col)
	announcement_timer = 3.0


func _update_announcement(delta: float) -> void:
	if announcement_timer > 0.0:
		announcement_timer -= delta
		if announcement_label:
			# Fade out at end
			var a: float = clamp(announcement_timer / 1.0, 0.0, 1.0)
			var col: Color = announcement_label.get_theme_color("font_color")
			col.a = a
			announcement_label.modulate = Color(1, 1, 1, a)
		if announcement_timer <= 0.0 and announcement_label:
			announcement_label.text = ""


func _build_buy_menu() -> void:
	buy_menu_cl = CanvasLayer.new()
	buy_menu_cl.layer = 7
	add_child(buy_menu_cl)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.10, 0.92)
	bg.size = Vector2(520, 360)
	bg.position = Vector2(380, 180)
	buy_menu_cl.add_child(bg)
	var title := Label.new()
	title.text = "STORE (press B)"
	title.position = Vector2(390, 195)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	buy_menu_cl.add_child(title)
	var hint := Label.new()
	hint.text = "Buy with $ to keep playing."
	hint.position = Vector2(390, 235)
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	buy_menu_cl.add_child(hint)
	buy_menu_cl.visible = false


func _build_health_banner() -> void:
	# Centered banner — placed between the wanted meter (x=12..232, y=44..80)
	# and the controls label "Tool: ..." which starts around x=920, y=50.
	# The free strip is x=240..880, y=44..76 (32px tall).
	var hcl := CanvasLayer.new()
	hcl.layer = 6
	add_child(hcl)
	health_warning_bg = ColorRect.new()
	health_warning_bg.color = Color(0.3, 0.1, 0.1, 0.85)
	health_warning_bg.size = Vector2(640, 32)
	health_warning_bg.position = Vector2(240, 44)
	health_warning_bg.visible = false
	hcl.add_child(health_warning_bg)
	health_warning_label = Label.new()
	health_warning_label.add_theme_font_size_override("font_size", 14)
	health_warning_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	health_warning_label.add_theme_color_override("font_outline_color", Color.BLACK)
	health_warning_label.add_theme_constant_override("outline_size", 3)
	health_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_warning_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	health_warning_label.size = Vector2(640, 32)
	health_warning_label.position = Vector2(240, 44)
	health_warning_label.visible = false
	hcl.add_child(health_warning_label)


func _refresh_buy_menu() -> void:
	if buy_menu_cl == null:
		return
	# Clear and rebuild list
	for c in buy_menu_cl.get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.10, 0.94)
	bg.size = Vector2(540, 380)
	bg.position = Vector2(370, 170)
	buy_menu_cl.add_child(bg)
	var title := Label.new()
	title.text = "STORE"
	title.position = Vector2(580, 185)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	buy_menu_cl.add_child(title)
	var info := Label.new()
	info.text = "Your money: $" + str(sim_budget) + "  Health: " + str(player_health) + "/" + str(player_max_health) + "  Ammo: " + str(ammo) + "/" + str(max_ammo)
	info.position = Vector2(380, 230)
	info.add_theme_font_size_override("font_size", 16)
	info.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	buy_menu_cl.add_child(info)
	# 1: Health Pack $200
	var h1 := Label.new()
	h1.text = "[1] Health Pack (+50 HP) - $200"
	h1.position = Vector2(390, 270)
	h1.add_theme_font_size_override("font_size", 18)
	h1.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if sim_budget >= 200 else Color(0.5, 0.5, 0.5))
	buy_menu_cl.add_child(h1)
	var h2 := Label.new()
	h2.text = "[2] Ammo Crate (+30 bullets) - $150"
	h2.position = Vector2(390, 305)
	h2.add_theme_font_size_override("font_size", 18)
	h2.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if sim_budget >= 150 else Color(0.5, 0.5, 0.5))
	buy_menu_cl.add_child(h2)
	var h3 := Label.new()
	h3.text = "[3] Bail Bond (wanted -2) - $500"
	h3.position = Vector2(390, 340)
	h3.add_theme_font_size_override("font_size", 18)
	h3.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if sim_budget >= 500 else Color(0.5, 0.5, 0.5))
	buy_menu_cl.add_child(h3)
	var h4 := Label.new()
	h4.text = "[4] Smog Upgrade (car 2x faster) - $1000"
	h4.position = Vector2(390, 375)
	h4.add_theme_font_size_override("font_size", 18)
	h4.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if sim_budget >= 1000 else Color(0.5, 0.5, 0.5))
	buy_menu_cl.add_child(h4)
	var h5 := Label.new()
	h5.text = "[0] Close Store"
	h5.position = Vector2(390, 410)
	h5.add_theme_font_size_override("font_size", 18)
	h5.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	buy_menu_cl.add_child(h5)


func _toggle_buy_menu() -> void:
	if buy_menu_open:
		buy_menu_open = false
		if buy_menu_cl:
			buy_menu_cl.visible = false
	else:
		buy_menu_open = true
		if buy_menu_cl == null:
			_build_buy_menu()
		buy_menu_cl.visible = true
		_refresh_buy_menu()


func _buy_item(idx: int) -> void:
	if idx == 0:
		_toggle_buy_menu()
		return
	if idx == 1:
		if sim_budget >= 200:
			sim_budget -= 200
			player_health = min(player_max_health, player_health + 50)
			_announce("HEALTH PACK (+50 HP)", Color(0.4, 1.0, 0.4))
	elif idx == 2:
		if sim_budget >= 150:
			sim_budget -= 150
			ammo = min(max_ammo, ammo + 30)
			_announce("AMMO CRATE (+30)", Color(1.0, 0.9, 0.4))
	elif idx == 3:
		if sim_budget >= 500:
			sim_budget -= 500
			wanted_level = max(0, wanted_level - 2)
			_announce("BAIL BOND POSTED", Color(0.4, 0.8, 1.0))
	elif idx == 4:
		if sim_budget >= 1000:
			sim_budget -= 1000
			current_vehicle_speed = max(current_vehicle_speed, 22.0)
			_announce("SMOG TUNING DONE", Color(1.0, 0.7, 0.3))
	_refresh_buy_menu()


func _draw_wanted_meter() -> void:
	# Called from a CanvasLayer; shows stars in top-left
	if hud_label == null:
		return
	var stars: String = ""
	for i in range(5):
		if i < wanted_level:
			stars += "*"
		else:
			stars += "."
	# Append to HUD via overlay
	# (We piggyback on hud_label; full overlay below in HUD layer)
	pass



func _build_minimap() -> void:
	# 256x256 minimap in bottom-left corner
	var w: int = 256
	var h: int = 256
	minimap_image = Image.create(w, h, false, Image.FORMAT_RGB8)
	minimap_image.fill(Color(0.05, 0.10, 0.05))
	minimap_texture = ImageTexture.create_from_image(minimap_image)
	var sprite := Sprite2D.new()
	sprite.texture = minimap_texture
	sprite.position = Vector2(140, 720 - 140)
	# Add to a CanvasLayer so it stays on screen
	var cl := CanvasLayer.new()
	cl.layer = 5
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.size = Vector2(w + 16, h + 36)
	bg.position = Vector2(8, 720 - h - 28)
	cl.add_child(bg)
	var title := Label.new()
	title.text = "MAP"
	title.position = Vector2(16, 720 - h - 24)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	cl.add_child(title)
	cl.add_child(sprite)
	minimap_sprite = sprite


func _update_minimap() -> void:
	if minimap_image == null:
		return
	# World extent
	var w: int = 256
	var h: int = 256
	var world_size: float = GRID * CELL  # 64m
	var scale: float = w / world_size
	minimap_image.fill(Color(0.05, 0.10, 0.05))
	# Draw roads
	for z in range(0, GRID, ROAD_EVERY):
		for x in range(GRID):
			var wx: float = _wx(x * CELL)
			var wz: float = _wz(z * CELL)
			var px: int = int((wx + world_size / 2.0) * scale)
			var py: int = int((wz + world_size / 2.0) * scale)
			draw_dot_on_map(px, py, Color(0.35, 0.35, 0.40))
	for x in range(0, GRID, ROAD_EVERY):
		for z in range(GRID):
			var wx2: float = _wx(x * CELL)
			var wz2: float = _wz(z * CELL)
			var px2: int = int((wx2 + world_size / 2.0) * scale)
			var py2: int = int((wz2 + world_size / 2.0) * scale)
			draw_dot_on_map(px2, py2, Color(0.35, 0.35, 0.40))
	# Draw buildings
	for b in placed_buildings:
		var bx: float = _wx(b.x * CELL)
		var bz: float = _wz(b.y * CELL)
		var px: int = int((bx + world_size / 2.0) * scale)
		var py: int = int((bz + world_size / 2.0) * scale)
		var col: Color = Color(0.95, 0.85, 0.30) if b.z == 0 else (Color(0.30, 0.55, 0.95) if b.z == 1 else Color(0.85, 0.55, 0.30))
		draw_dot_on_map(px, py, col)
	# Draw police
	for po in police:
		var ppx: int = int((po["pos"].x + world_size / 2.0) * scale)
		var ppy: int = int((po["pos"].z + world_size / 2.0) * scale)
		draw_dot_on_map(ppx, ppy, Color(0.10, 0.10, 0.95))
	# Draw mission target (red square)
		if current_mission.get("status") == "active" and current_mission.has("target_pos"):
			var tpos: Vector3 = current_mission["target_pos"]
			var tx2: int = int((tpos.x + GRID * CELL / 2.0) * 256 / (GRID * CELL))
			var ty2: int = int((tpos.z + GRID * CELL / 2.0) * 256 / (GRID * CELL))
			var offsets: Array = [-3, -2, -1, 0, 1, 2, 3]
			for dx2 in offsets:
				for dy2 in offsets:
					var px: int = tx2 + dx2
					var py: int = ty2 + dy2
					if px >= 0 and px < 256 and py >= 0 and py < 256:
						minimap_image.set_pixel(px, py, Color(1, 0, 0))
		# Draw player (yellow arrow)
	var plx: int = int((player_pos.x + world_size / 2.0) * scale)
	var ply: int = int((player_pos.z + world_size / 2.0) * scale)
	draw_dot_on_map(plx, ply, Color(1, 1, 0))
	minimap_texture.update(minimap_image)


func draw_dot_on_map(px: int, py: int, col: Color) -> void:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var nx: int = px + dx
			var ny: int = py + dy
			if nx >= 0 and nx < 256 and ny >= 0 and ny < 256:
				minimap_image.set_pixel(nx, ny, col)

func _setup_missions() -> void:
	# Mission 1: collect bounty on a criminal hiding in the city
	var m1 := {
		"id": "bust_the_burglar",
		"name": "Bust the Burglar",
		"brief": "Find the burglar in the residential zone and arrest them.",
		"objective": "Locate the burglar (red capsule near residential)",
		"status": "active",
		"target_pos": Vector3(_wx(12 * CELL), 0.7, _wz(4 * CELL)),
		"target_radius": 3.0,
		"reward": 500,
	}
	missions.append(m1)
	current_mission = m1
	if mission_overlay == null:
		_build_mission_overlay()
	_refresh_mission_overlay()


func _build_stats_overlay() -> void:
	stats_cl = CanvasLayer.new()
	stats_cl.layer = 6
	add_child(stats_cl)
	var sgt_bg := ColorRect.new()
	sgt_bg.color = Color(0, 0, 0, 0.85)
	sgt_bg.size = Vector2(420, 280)
	sgt_bg.position = Vector2(430, 200)
	stats_cl.add_child(sgt_bg)
	var sgt_title := Label.new()
	sgt_title.text = "STATISTICS"
	sgt_title.position = Vector2(440, 210)
	sgt_title.add_theme_font_size_override("font_size", 22)
	sgt_title.add_theme_color_override("font_color", Color(1, 1, 0.4))
	stats_cl.add_child(sgt_title)
	var sgt_label := Label.new()
	stats_label = sgt_label
	sgt_label.position = Vector2(440, 250)
	sgt_label.add_theme_font_size_override("font_size", 16)
	sgt_label.add_theme_color_override("font_color", Color(0.95, 0.94, 0.88))
	stats_cl.add_child(sgt_label)
	stats_cl.visible = false


func _refresh_stats_overlay() -> void:
	if stats_label == null:
		return
	stats_label.text = "Day %d\nPopulation: %d\nBudget: $%s\nHP: %d/100\n\nKills: %d\nCars smashed: %d\nMoney earned: $%d\nBullets fired: %d\nDistance walked: %.0f m\nMissions done: %d/%d" % [
		sim_day_count,
		sim_population,
		_abs_budget_fmt(),
		player_health,
		stats_npcs_killed,
		stats_cars_smashed,
		stats_money_earned,
		stats_bullets_fired,
		stats_distance_walked,
		_story_missions_done(),
		MISSION_CHAIN.size(),
	]


func _build_mission_overlay() -> void:
	mission_overlay = CanvasLayer.new()
	mission_overlay.layer = 4
	add_child(mission_overlay)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.20, 0.40, 0.85)
	bg.size = Vector2(520, 60)
	bg.position = Vector2(370, 700)
	mission_overlay.add_child(bg)
	mission_label = Label.new()
	mission_label.text = ""
	mission_label.position = Vector2(380, 706)
	mission_label.add_theme_font_size_override("font_size", 16)
	mission_label.add_theme_color_override("font_color", Color(1, 1, 0.4))
	mission_overlay.add_child(mission_label)
	mission_objective = Label.new()
	mission_objective.text = ""
	mission_objective.position = Vector2(380, 728)
	mission_objective.add_theme_font_size_override("font_size", 13)
	mission_objective.add_theme_color_override("font_color", Color(1, 1, 1))
	mission_overlay.add_child(mission_objective)
	_refresh_mission_overlay()


func _refresh_mission_overlay() -> void:
	if mission_label == null or mission_objective == null:
		return
	if current_mission.is_empty():
		mission_label.text = "No mission"
		mission_objective.text = ""
		return
	mission_label.text = "MISSION: %s   [%s]" % [current_mission["name"], current_mission["status"].to_upper()]
	if current_mission["status"] == "active":
		if current_mission.get("id") == "collect_bonus":
			mission_objective.text = "%s  [%d/%d]" % [current_mission["objective"], int(current_mission.get("progress", 0)), int(current_mission.get("target_count", 5))]
		else:
			mission_objective.text = current_mission["objective"]
	elif current_mission["status"] == "complete":
		mission_objective.text = "MISSION COMPLETE! Press M for next mission."
	elif current_mission["status"] == "failed":
		mission_objective.text = "Mission failed. Press M for the next mission."


func _update_mission(delta: float) -> void:
	if current_mission.is_empty() or current_mission.get("status") != "active":
		return
	# Pizza Run has its own state machine (pickup -> deliver); the simple
	# target-radius check below would auto-complete the mission the moment
	# the player walks near the target without picking up the pizza.
	if current_mission.get("id") == "pizza_delivery":
		_update_delivery_mission(delta)
		return
	# Heist and money-bag missions have their own completion logic
	if not current_mission.has("target_pos"):
		return
	var d: float = player_pos.distance_to(current_mission["target_pos"])
	if d < current_mission["target_radius"]:
		_complete_mission()


func _complete_mission() -> void:
	_play_mission_complete_sound()
	current_mission["status"] = "complete"
	var reward: int = current_mission.get("reward", 0)
	sim_budget += reward
	stats_money_earned += reward
	if not completed_missions.has(current_mission["id"]):
		completed_missions.append(current_mission["id"])
	_announce("MISSION COMPLETE: %s  +$%d  (press M for the next one)" % [current_mission.get("name", "?"), reward], Color(0.4, 1.0, 0.4))
	_refresh_mission_overlay()


# Mark the current mission failed. It still counts as "done" for the chain
# so the player is never stuck; they just miss the reward.
func _fail_current_mission() -> void:
	if current_mission.is_empty():
		return
	if current_mission.get("id") == "pizza_delivery":
		_fail_delivery_mission(true)
		return
	current_mission["status"] = "failed"
	if not completed_missions.has(current_mission["id"]):
		completed_missions.append(current_mission["id"])
	_refresh_mission_overlay()


func _next_mission() -> void:
	# Queue next mission: chase a bank robber
	var m2 := {
		"id": "chase_the_bank_robber",
		"name": "Bank Robbery in Progress",
		"brief": "Pursue the robber's getaway car.",
		"objective": "Drive within 5m of the robber's vehicle",
		"status": "active",
		"target_pos": Vector3(_wx(28 * CELL), 0.5, _wz(20 * CELL)),
		"target_radius": 5.0,
		"reward": 1500,
	}
	missions.append(m2)
	current_mission = m2
	_refresh_mission_overlay()


func _next_mission_2() -> void:
	var m3 := {
		"id": "collect_bonus",
		"name": "Tax Bonus",
		"brief": "Collect 5 money pickups to earn a bonus.",
		"objective": "Collect 5 money pickups (yellow bags)",
		"status": "active",
		"progress": 0,
		"target_count": 5,
		"reward": 750,
	}
	missions.append(m3)
	current_mission = m3
	_refresh_mission_overlay()


# Pressed M: advance to the next mission.  Handles both forward-progress
# (active -> complete -> next) and the "all done" end state.
func _advance_mission() -> void:
	# M while a mission is running skips it (no reward) so nobody gets stuck.
	if not current_mission.is_empty() and current_mission.get("status") == "active":
		_announce("MISSION SKIPPED: " + str(current_mission.get("name", "?")), Color(0.7, 0.7, 0.7))
		_fail_current_mission()
	for id in MISSION_CHAIN:
		if not completed_missions.has(id):
			_start_mission(id)
			return
	# Story finished: pizza runs stay available for replay value.
	_next_mission_3()


func _start_mission(id: String) -> void:
	match id:
		"bust_the_burglar": _setup_missions()
		"chase_the_bank_robber": _next_mission()
		"collect_bonus": _next_mission_2()
		"the_big_heist": _start_heist()
		"pizza_delivery": _next_mission_3()
	_announce("NEW MISSION: " + str(current_mission.get("name", "?")), Color(0.95, 0.85, 0.30))


# Mission 5: "Pizza Run".  Build a pizza shop, a yellow box on the counter,
# and a random green target.  Player walks to the shop, picks up the box
# (it parents to their head), then walks to the target within 90 sim-seconds
# for $400.  Failure deducts $50.
func _next_mission_3() -> void:
	# Clean up any leftover delivery visuals from a previous run.
	_clean_delivery_mission()
	carrying_pizza = false
	delivery_timer = DELIVERY_TIME_LIMIT
	# Pizza shop at fixed grid coord — build a red box with a yellow box on top.
	pizza_shop_pos = Vector3(_wx(PIZZA_SHOP_GRID.x * CELL), 0.0, _wz(PIZZA_SHOP_GRID.y * CELL))
	pizza_shop_mesh = _make_box(Vector3(3.0, 2.4, 3.0), pizza_shop_pos + Vector3(0, 1.2, 0), Color(0.75, 0.15, 0.10))
	add_child(pizza_shop_mesh)
	# Window stripes (yellow) so the shop reads as a pizzeria
	var window_stripe := _make_box(Vector3(2.7, 0.3, 0.05), pizza_shop_pos + Vector3(0, 1.8, 1.55), Color(0.95, 0.80, 0.10))
	add_child(window_stripe)
	# Pizza box, yellow flat cube sitting on the counter
	pizza_box_mesh = _make_box(Vector3(0.7, 0.15, 0.7), pizza_shop_pos + Vector3(0, 1.5, 0.0), Color(0.95, 0.80, 0.20))
	add_child(pizza_box_mesh)
	# Pick a random target marker somewhere on the road network (walkable area).
	# Avoid water, and prefer cells that aren't the shop itself.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_msec()) ^ 0x5A5A
	var attempts: int = 0
	while attempts < 50:
		var tx: int = rng.randi_range(2, GRID - 3)
		var tz: int = rng.randi_range(2, GRID - 6)  # avoid southern river strip
		# Snap onto a road so the drop-off is always reachable on foot
		if not _is_road(tx, tz):
			tx = clampi(int(round(float(tx) / ROAD_EVERY)) * ROAD_EVERY, 0, GRID - ROAD_EVERY)
		if tx == PIZZA_SHOP_GRID.x and tz == PIZZA_SHOP_GRID.y:
			attempts += 1
			continue
		delivery_target_pos = Vector3(_wx(tx * CELL), 0.0, _wz(tz * CELL))
		break
	# Green target marker: a thin tall cylinder so the player can see it from a distance.
	delivery_target_mesh = MeshInstance3D.new()
	var t_mesh := CylinderMesh.new()
	t_mesh.top_radius = 0.7
	t_mesh.bottom_radius = 0.7
	t_mesh.height = 0.2
	delivery_target_mesh.mesh = t_mesh
	var t_mat := StandardMaterial3D.new()
	t_mat.albedo_color = Color(0.20, 0.95, 0.35)
	t_mat.emission_enabled = true
	t_mat.emission = Color(0.10, 0.55, 0.20)
	t_mat.emission_energy_multiplier = 0.8
	delivery_target_mesh.material_override = t_mat
	delivery_target_mesh.position = delivery_target_pos + Vector3(0, 0.1, 0)
	add_child(delivery_target_mesh)
	# Build the mission dict
	var m5 := {
		"id": "pizza_delivery",
		"name": "Pizza Run",
		"brief": "Pick up a pizza from Tony's and deliver it to the green marker. 90 sim-seconds.",
		"objective": "Walk to the pizza shop (red building) and pick up the order",
		"status": "active",
		"target_pos": delivery_target_pos,
		"target_radius": DELIVERY_RADIUS,
		"reward": PIZZA_REWARD,
		"stage": "pickup",  # pickup -> deliver -> complete
	}
	missions.append(m5)
	current_mission = m5
	_refresh_mission_overlay()
	_announce("PIZZA RUN: pick up the order at Tony's, deliver to the green marker in 90s. $%d reward." % PIZZA_REWARD, Color(0.95, 0.85, 0.30))


# Called every frame from _update_mission: handles the pickup->deliver handoff
# for the pizza mission (and is a no-op for other missions, which fall through
# to the simple target-radius check).
func _update_delivery_mission(delta: float) -> void:
	if current_mission.get("id") != "pizza_delivery":
		return
	# Tick the timer once the player is carrying the pizza.
	if carrying_pizza and current_mission.get("stage") == "deliver":
		delivery_timer -= delta
		if delivery_timer <= 0.0:
			_fail_delivery_mission(false)
			return
	# Keep the box floating above the player while they're carrying it.
	if carrying_pizza and pizza_box_mesh and is_instance_valid(pizza_box_mesh) and player and is_instance_valid(player):
		if pizza_box_mesh.get_parent() != player:
			pizza_box_mesh.reparent(player)
		pizza_box_mesh.position = Vector3(0, 1.6, 0)
	# Pickup: walk to the shop counter while in the "pickup" stage.
	if current_mission.get("stage") == "pickup" and not carrying_pizza:
		var d: float = player_pos.distance_to(pizza_shop_pos)
		if d < DELIVERY_RADIUS:
			carrying_pizza = true
			current_mission["stage"] = "deliver"
			current_mission["objective"] = "Deliver to the green marker (%.0fs left)" % delivery_timer
			_refresh_mission_overlay()
			_announce("PIZZA ACQUIRED — run!", Color(0.95, 0.85, 0.30))
			_play_collect_pickup_sound()
	# Deliver: walk to the target marker while carrying.
	elif current_mission.get("stage") == "deliver" and carrying_pizza:
		current_mission["objective"] = "Deliver to the green marker (%.0fs left)" % max(0.0, delivery_timer)
		var d2: float = player_pos.distance_to(delivery_target_pos)
		if d2 < DELIVERY_RADIUS:
			_complete_delivery_mission()


func _complete_delivery_mission() -> void:
	_play_mission_complete_sound()
	current_mission["status"] = "complete"
	sim_budget += PIZZA_REWARD
	stats_money_earned += PIZZA_REWARD
	completed_missions.append("pizza_delivery")
	# Small population happiness nudge — residents like fast delivery
	sim_population_peak = max(sim_population_peak, sim_population + 5)
	_announce("PIZZA DELIVERED! +$%d  (5 grateful residents)" % PIZZA_REWARD, Color(0.40, 0.95, 0.40))
	_clean_delivery_mission()
	_refresh_mission_overlay()


func _fail_delivery_mission(skipped: bool) -> void:
	current_mission["status"] = "failed"
	stats_missions_failed += 1
	# Penalty only when the player physically ran out the clock — skipping via M
	# shouldn't cost them money.
	if not skipped:
		sim_budget = max(-5000, sim_budget - PIZZA_PENALTY)
		_announce("PIZZA COLD! -$%d penalty." % PIZZA_PENALTY, Color(0.95, 0.40, 0.40))
	else:
		_announce("PIZZA RUN skipped.", Color(0.70, 0.70, 0.70))
	# Mark the mission as completed (in the "failed" sense) so the queue advances
	completed_missions.append("pizza_delivery")
	_clean_delivery_mission()
	_refresh_mission_overlay()


func _clean_delivery_mission() -> void:
	# Free the shop, box, and target marker.  Idempotent.
	if pizza_shop_mesh and is_instance_valid(pizza_shop_mesh):
		pizza_shop_mesh.queue_free()
	pizza_shop_mesh = null
	if pizza_box_mesh and is_instance_valid(pizza_box_mesh):
		# Reparent off the player first so queue_free doesn't fight the player node
		var old_parent := pizza_box_mesh.get_parent()
		if old_parent and old_parent != self:
			old_parent.remove_child(pizza_box_mesh)
		pizza_box_mesh.queue_free()
	pizza_box_mesh = null
	if delivery_target_mesh and is_instance_valid(delivery_target_mesh):
		delivery_target_mesh.queue_free()
	delivery_target_mesh = null
	carrying_pizza = false
	delivery_timer = 0.0


func _build_burglar() -> void:
	# Visual: red capsule marking the mission target
	var b := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.5
	capsule.radius = 0.30
	b.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.10, 0.10)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.05, 0.05)
	mat.emission_energy_multiplier = 0.5
	b.material_override = mat
	b.position = Vector3(_wx(12 * CELL), 0.75, _wz(4 * CELL))
	b.name = "Burglar"
	add_child(b)




func _build_parked_cars() -> void:
	# 4 parked cars in obvious places for player to enter
	var spots: Array = [
		Vector3(_wx(2 * CELL), 0.4, _wz(2 * CELL)),
		Vector3(_wx(28 * CELL), 0.4, _wz(2 * CELL)),
		Vector3(_wx(2 * CELL), 0.4, _wz(28 * CELL)),
		Vector3(_wx(28 * CELL), 0.4, _wz(28 * CELL)),
	]
	var colors: Array = [
		Color(0.85, 0.20, 0.15),
		Color(0.20, 0.40, 0.85),
		Color(0.85, 0.78, 0.20),
		Color(0.20, 0.65, 0.30),
	]
	for i in range(spots.size()):
		var pos: Vector3 = spots[i]
		var car := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 0.7, 3.6)
		car.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		car.material_override = mat
		car.position = pos
		# Night lights: 2 white headlights at the front (-Z), 2 red taillights at +Z.
		# The body is 1.6 wide on X, 3.6 long on Z, so half_long=1.8, half_short=0.8.
		_add_car_lights(car, true, 1.8, 0.8)
		# Random initial yaw
		var yaw: float = randf() * TAU
		car.rotation.y = yaw
		add_child(car)
		vehicles.append({
			"mesh": car,
			"pos": pos,
			"yaw": yaw,
			"speed": 0.0,
		})



func _build_pickups() -> void:
	# Scatter money bags and health kits
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 20:
		var x: int = rng.randi_range(2, GRID - 2)
		var z: int = rng.randi_range(2, GRID - 2)
		if _is_water(x, z):
			continue
		# Snap onto a road: the player can't walk through buildings, so a
		# pickup inside a building lot could never be collected.
		if not _is_road(x, z):
			x = clampi(int(round(float(x) / ROAD_EVERY)) * ROAD_EVERY, 0, GRID - ROAD_EVERY)
		var is_money: bool = rng.randf() < 0.7
		var pickup := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.4, 0.4, 0.4) if is_money else Vector3(0.35, 0.35, 0.35)
		pickup.mesh = bm
		var mat := StandardMaterial3D.new()
		if is_money:
			mat.albedo_color = Color(0.95, 0.78, 0.15)
			mat.emission_enabled = true
			mat.emission = Color(0.5, 0.4, 0.05)
			mat.emission_energy_multiplier = 0.4
		else:
			mat.albedo_color = Color(0.95, 0.20, 0.20)
			mat.emission_enabled = true
			mat.emission = Color(0.6, 0.05, 0.05)
			mat.emission_energy_multiplier = 0.5
		pickup.material_override = mat
		pickup.position = Vector3(_wx(x * CELL), 0.2, _wz(z * CELL))
		add_child(pickup)
		pickups.append({
			"mesh": pickup,
			"pos": pickup.position,
			"type": "money" if is_money else "health",
			"value": rng.randi_range(50, 250) if is_money else rng.randi_range(15, 35),
		})


func _update_pickups(delta: float) -> void:
	# Animate pickup floats
	var t: float = Time.get_ticks_msec() / 1000.0
	for p in pickups:
		p["mesh"].position.y = 0.2 + sin(t * 2.5 + p["pos"].x) * 0.15
		p["mesh"].rotation.y = t * 1.2
	# Check pickup by player
	for i in range(pickups.size() - 1, -1, -1):
		var p2: Dictionary = pickups[i]
		var d: float = player_pos.distance_to(p2["pos"])
		if d < 1.5:
			if p2["type"] == "money":
				sim_budget += p2["value"]
				_play_collect_pickup_sound()
				if current_mission.get("id") == "collect_bonus" and current_mission.get("status") == "active":
					current_mission["progress"] = int(current_mission.get("progress", 0)) + 1
					_refresh_mission_overlay()
					if current_mission["progress"] >= int(current_mission.get("target_count", 5)):
						_complete_mission()
			else:
				player_health = min(100, player_health + p2["value"])
				_play_collect_pickup_sound()
			p2["mesh"].queue_free()
			pickups.remove_at(i)



func _play_beep(freq: float = 440.0, duration: float = 0.1, vol: float = 0.3) -> void:
	if not audio_on:
		return
	# Generate a simple sine wave beep using AudioStreamGenerator
	var player := AudioStreamPlayer.new()
	add_child(player)
	var gen_stream := AudioStreamGenerator.new()
	gen_stream.mix_rate = 22050.0
	gen_stream.buffer_length = 0.5
	player.stream = gen_stream
	player.volume_db = linear_to_db(vol)
	player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var sample_count: int = int(gen_stream.mix_rate * duration)
	var phase: float = 0.0
	var step: float = freq / gen_stream.mix_rate
	for i in range(sample_count):
		var sample: float = sin(phase * TAU) * 0.6
		phase += step
		playback.push_frame(Vector2(sample, sample))
	# Fade out
	var fade_count: int = 1000
	for fi in range(fade_count):
		var fade: float = 1.0 - (float(fi) / fade_count)
		playback.push_frame(Vector2(sin(phase * TAU) * 0.6 * fade, sin(phase * TAU) * 0.6 * fade))
	player.finished.connect(func(): player.queue_free())


func _play_collect_pickup_sound() -> void:
	_play_beep(880.0, 0.08, 0.4)


func _play_crash_sound() -> void:
	_play_beep(180.0, 0.15, 0.5)


func _play_enter_building_sound() -> void:
	_play_beep(660.0, 0.06, 0.3)


func _play_police_sound() -> void:
	# Two-tone police siren
	_play_beep(700.0, 0.3, 0.4)
	await get_tree().create_timer(0.3).timeout
	_play_beep(950.0, 0.3, 0.4)


func _play_mission_complete_sound() -> void:
	# Three-tone success
	_play_beep(523.0, 0.15, 0.5)
	await get_tree().create_timer(0.15).timeout
	_play_beep(659.0, 0.15, 0.5)
	await get_tree().create_timer(0.15).timeout
	_play_beep(784.0, 0.25, 0.5)



func _try_shoot() -> void:
	if ammo <= 0:
		_announce("OUT OF AMMO - Press B to buy", Color(1, 0.4, 0.4))
		_play_beep(110, 0.1, 0.2)
		return
	if Time.get_ticks_msec() - last_shot_time < 200.0:
		return
	last_shot_time = Time.get_ticks_msec()
	ammo -= 1
	if bullet_cooldown > 0.0:
		return
	# Create a bullet mesh
	var b := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.08
	bm.height = 0.16
	b.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.9, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.8, 0)
	mat.emission_energy_multiplier = 2.0
	b.material_override = mat
	# Direction: forward based on camera yaw
	var dir := Vector3(sin(deg_to_rad(cam_yaw)), 0.0, cos(deg_to_rad(cam_yaw)))
	if vehicle_in and current_vehicle != null:
		dir = Vector3(sin(current_vehicle_yaw), 0.0, cos(current_vehicle_yaw))
		b.position = current_vehicle_pos + dir * 2.0 + Vector3(0, 1.0, 0)
	else:
		b.position = player_pos + dir * 3.0 + Vector3(0, 1.2, 0)
	add_child(b)
	bullets.append({
		"mesh": b,
		"pos": b.position,
		"vel": dir * 50.0,
		"ttl": 1.5,
	})
	bullet_cooldown = 0.18
	stats_bullets_fired += 1
	_play_beep(1200.0, 0.05, 0.4)


func _update_bullets(delta: float) -> void:
	bullet_cooldown = max(0.0, bullet_cooldown - delta)
	for i in range(bullets.size() - 1, -1, -1):
		var b: Dictionary = bullets[i]
		b["ttl"] -= delta
		if b["ttl"] <= 0:
			b["mesh"].queue_free()
			bullets.remove_at(i)
			continue
		var new_pos: Vector3 = b["pos"] + b["vel"] * delta
		# Hit NPCs?
		for n in npcs:
			var d: float = n["mesh"].position.distance_to(new_pos)
			if d < 1.0:
				# Kill NPC
				n["mesh"].queue_free()
				npcs.erase(n)
				sim_budget += 100  # loot
				stats_npcs_killed += 1
				stats_money_earned += 100
				_add_wanted(2)
				b["mesh"].queue_free()
				bullets.remove_at(i)
				break
		# Hit parked cars
		for v in vehicles:
			var d2: float = v["pos"].distance_to(new_pos)
			if d2 < 2.0:
				# Car explodes: make it smoky + on fire (emission red)
				v["mesh"].material_override.albedo_color = Color(0.20, 0.10, 0.10)
				v["mesh"].material_override.emission_enabled = true
				v["mesh"].material_override.emission = Color(0.6, 0.2, 0.05)
				stats_cars_smashed += 1
				v["mesh"].material_override.emission_energy_multiplier = 0.5
				_add_wanted(2)
				b["mesh"].queue_free()
				bullets.remove_at(i)
				break
		# Hit police?
		for po in police:
			var d3: float = po["pos"].distance_to(new_pos)
			if d3 < 1.5:
				_add_wanted(2)
				# Police car turns smoky
				po["mesh"].material_override.albedo_color = Color(0.20, 0.10, 0.10)
				b["mesh"].queue_free()
				bullets.remove_at(i)
				break
		b["pos"] = new_pos
		b["mesh"].position = new_pos



# Bank location (corner of map)
var bank_pos: Vector3 = Vector3(_wx(20 * CELL), 0.7, _wz(20 * CELL))

var heist_bank_mesh: MeshInstance3D

func _start_heist() -> void:
	if heist_bank_mesh and is_instance_valid(heist_bank_mesh):
		heist_bank_mesh.queue_free()
	# Mission 4: bank heist! Steal \$5000, escape police for 30s
	var m4 := {
		"id": "the_big_heist",
		"name": "The Big Heist",
		"brief": "Rob the bank at the corner of 5th and Main, then escape the police for 30 seconds.",
		"objective": "Walk up to the bank (big red building) to rob it",
		"status": "active",
		"heist_stage": "rob",  # rob -> escape -> complete
		"heist_started_at": -1.0,
		"heist_target": Vector3(_wx(8 * CELL), 0.0, _wz(8 * CELL)),
		"reward": 5000,
	}
	missions.append(m4)
	current_mission = m4
	# Spawn a red bank cube
	var bank := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6.0, 5.0, 6.0)
	bank.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.10, 0.10)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.05, 0.05)
	mat.emission_energy_multiplier = 0.3
	bank.material_override = mat
	bank.position = m4["heist_target"] + Vector3(0, 2.5, 0)
	bank.name = "Bank"
	add_child(bank)
	heist_bank_mesh = bank
	_refresh_mission_overlay()


func _update_heist(delta: float) -> void:
	if current_mission.get("id") != "the_big_heist":
		return
	if current_mission.get("status") != "active":
		return
	if current_mission.get("heist_stage") == "rob":
		# Check player near bank
		var bank_pos: Vector3 = current_mission["heist_target"]
		var d: float = player_pos.distance_to(bank_pos)
		if d < 4.0:
			# Rob it! +wanted, +5000 cash, mission stage -> escape
			current_mission["heist_stage"] = "escape"
			current_mission["objective"] = "Escape the police for 30 seconds!"
			sim_budget += 5000
			stats_money_earned += 5000
			_add_wanted(5)
			current_mission["heist_started_at"] = sim_day_accum
			# Police frenzy: more police spawn
			for i in range(3):
				_spawn_police_unit()
	elif current_mission.get("heist_stage") == "escape":
		# Mission completes once the heat dies down (wanted back to 0)
		if wanted_level == 0:
			_complete_mission()


func _spawn_police_unit() -> void:
	var px: int = 0
	var pz: int = (randi() % 8) * ROAD_EVERY
	var pos := Vector3(_wx(px * CELL + CELL * 0.5), 0.4, _wz(pz * CELL + CELL * 0.5))
	var car := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.7, 3.6)
	car.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.10, 0.45)
	car.material_override = mat
	car.position = pos
	add_child(car)
	var lightbar := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.6, 0.15, 0.4)
	lightbar.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.10, 0.10, 0.10)
	lmat.emission_enabled = true
	lmat.emission = Color(0.9, 0.2, 0.2)
	lightbar.material_override = lmat
	lightbar.position = pos + Vector3(0.0, 0.55, 0.0)
	add_child(lightbar)
	police.append({
		"mesh": car,
		"light": lightbar,
		"pos": pos,
		"yaw": 0.0,
		"speed": 0.0,
	})






func _show_game_complete() -> void:
	game_complete = true
	final_score = sim_budget + (sim_population * 10) + (stats_money_earned * 2) - (stats_npcs_killed * 100) - (total_deaths * 200)
	if final_score > 50000:
		final_rank = "LEGENDARY CRIMINAL"
	elif final_score > 20000:
		final_rank = "MASTER SYNDICATE BOSS"
	elif final_score > 10000:
		final_rank = "GANG LEADER"
	elif final_score > 5000:
		final_rank = "THIEF"
	elif final_score > 1000:
		final_rank = "PETTY CROOK"
	else:
		final_rank = "TOURIST"
	final_cl = CanvasLayer.new()
	final_cl.layer = 12
	add_child(final_cl)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05, 0.95)
	bg.size = Vector2(1280, 720)
	final_cl.add_child(bg)
	var t := Label.new()
	t.text = "GAME COMPLETE"
	t.position = Vector2(440, 100)
	t.add_theme_font_size_override("font_size", 64)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	final_cl.add_child(t)
	var r := Label.new()
	r.text = "Rank: " + final_rank
	r.position = Vector2(500, 200)
	r.add_theme_font_size_override("font_size", 32)
	r.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	final_cl.add_child(r)
	var s := Label.new()
	s.text = "Final Score: " + str(final_score)
	s.position = Vector2(480, 260)
	s.add_theme_font_size_override("font_size", 28)
	s.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	final_cl.add_child(s)
	var st := Label.new()
	st.position = Vector2(280, 340)
	st.add_theme_font_size_override("font_size", 18)
	st.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	st.text = """FINAL STATS
====================
Money in wallet:           $""" + str(sim_budget) + """
Population:                """ + str(sim_population) + """
Day count:                 """ + str(sim_day_count) + """
Total earned:              $""" + str(stats_money_earned) + """
Missions completed:        """ + str(completed_missions.size()) + """
Missions failed:           """ + str(stats_missions_failed) + """
NPCs killed:               """ + str(stats_npcs_killed) + """
Cars smashed:              """ + str(stats_cars_smashed) + """
Bullets fired:             """ + str(stats_bullets_fired) + """
Distance walked:           """ + str(int(stats_distance_walked)) + """m
Times busted/killed:       """ + str(total_deaths) + """
Total play time:           """ + str(int(total_play_time / 60.0)) + """m """ + str(int(total_play_time) % 60) + """s

Press R to restart, or just keep playing."""
	final_cl.add_child(st)


func _restart_game() -> void:
	# Reset all sim state
	sim_budget = 20000
	sim_population = 1250
	sim_day_count = 0
	sim_residential_demand = 50.0
	sim_commercial_demand = 50.0
	sim_industrial_demand = 50.0
	sim_income_today = 0
	sim_expenses_today = 0
	wanted_level = 0
	wanted_timer = 0.0
	stats_npcs_killed = 0
	stats_cars_smashed = 0
	stats_money_earned = 0
	stats_bullets_fired = 0
	stats_distance_walked = 0.0
	stats_missions_failed = 0
	total_deaths = 0
	total_play_time = 0.0
	player_health = player_max_health
	ammo = max_ammo
	completed_missions.clear()
	game_complete = false
	final_rank = ""
	final_score = 0
	if final_cl:
		final_cl.queue_free()
		final_cl = null
	# Reset missions
	missions.clear()
	_clean_delivery_mission()
	if heist_bank_mesh and is_instance_valid(heist_bank_mesh):
		heist_bank_mesh.queue_free()
	heist_bank_mesh = null
	_setup_missions()
	# Reset player position
	player_pos = Vector3(_wx(8 * CELL), 0.7, _wz(8 * CELL))
	if player:
		player.position = player_pos
	# Reset bullets/pickups
	bullets.clear()
	for p in pickups:
		if p.mesh:
			p.mesh.queue_free()
	pickups.clear()
	_build_pickups()
	_police_roadblock_active = false
	_clear_all_cones()
	_announce("NEW GAME STARTED", Color(0.4, 1.0, 0.4))

func _build_main_menu() -> void:
	menu_cl = CanvasLayer.new()
	menu_cl.layer = 10
	add_child(menu_cl)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.08, 0.92)
	bg.size = Vector2(1280, 720)
	menu_cl.add_child(bg)
	# Title
	var title := Label.new()
	title.text = "SYNDICATE CITY"
	title.position = Vector2(380, 60)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	menu_cl.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "SimCity + GTA"
	subtitle.position = Vector2(540, 160)
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	menu_cl.add_child(subtitle)
	# Instructions
	var inst := Label.new()
	inst.position = Vector2(100, 230)
	inst.add_theme_font_size_override("font_size", 18)
	inst.add_theme_color_override("font_color", Color(0.95, 0.94, 0.88))
	inst.text = """Build your city. Walk its roads. Commit crimes. Make the cash.

1/2/3 zones  4 roads  5 bulldoze  6/7 power  Click to apply
WASD / arrows walk or drive   F enter/exit car   Space shoot   E enter building
+/- sim speed  T top-down  C/V camera  N weather  [ ] tax
M next mission  H hide help  TAB stats  B store  P pause  F5/F9 save/load

DIFFICULTY: press 1 = EASY, 2 = NORMAL, 3 = HARD"""
	menu_cl.add_child(inst)
	# Footer
	var footer := Label.new()
	menu_footer = footer
	footer.text = "Difficulty: NORMAL  -  press ENTER or click to start"
	footer.position = Vector2(0, 670)
	footer.size = Vector2(1280, 40)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 22)
	footer.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	menu_cl.add_child(footer)


func _dismiss_menu() -> void:
	if menu_cl:
		menu_cl.queue_free()
		menu_cl = null
		menu_footer = null
	_refresh_camera()




func _update_random_events(delta: float) -> void:
	event_timer += delta
	if event_active.is_empty() and event_timer > 20.0:
		_spawn_random_event()
	# Active event lifetime
	if not event_active.is_empty():
		var life: float = event_active.get("life", 0.0)
		life -= delta
		event_active["life"] = life
		# Check if player reached event position
		var ev_pos: Vector3 = event_active.get("pos", Vector3.ZERO)
		if player_pos.distance_to(ev_pos) < 4.0:
			_resolve_random_event()
		if life <= 0.0:
			_fail_random_event()
		_refresh_event_hud()


func _spawn_random_event() -> void:
	# Pick a random road cell
	var x: int = randi_range(2, GRID - 3)
	var z: int = randi_range(2, GRID - 3)
	var pos := Vector3(_wx(x * CELL), 0.7, _wz(z * CELL))
	var types: Array = ["mugging", "car_theft", "fire"]
	var t: String = types[randi() % types.size()]
	event_active = {
		"type": t,
		"pos": pos,
		"life": 25.0,
		"reward": 300,
	}
	event_timer = 0.0
	_announce("EVENT: " + t.to_upper().replace("_", " ") + " - Investigate!", Color(1, 0.6, 0.4))
	_build_event_marker(pos, t)
	# Spawn traffic cones around the event site — every random event gets a
	# roadblock so the city feels like it's responding to the incident.
	_spawn_cone_ring(pos, 4)


func _build_event_marker(pos: Vector3, t: String) -> void:
	if event_cl == null:
		event_cl = CanvasLayer.new()
		event_cl.layer = 9
		add_child(event_cl)
	for c in event_cl.get_children():
		c.queue_free()
	var col := Color(1, 0.5, 0.2)
	if t == "fire":
		col = Color(1, 0.3, 0.1)
	elif t == "car_theft":
		col = Color(0.9, 0.7, 0.2)
	elif t == "mugging":
		col = Color(1, 0.4, 0.4)
	# 3D marker
	var marker := _make_box(Vector3(0.5, 2.5, 0.5), pos + Vector3(0, 2.5, 0), col, true)
	marker.name = "event_marker"
	# HUD label
	var lbl := Label.new()
	lbl.text = "EVENT: " + t.to_upper().replace("_", " ") + " (" + str(int(event_active.get("life", 0.0))) + "s)"
	lbl.position = Vector2(50, 600)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", col)
	event_cl.add_child(lbl)


func _refresh_event_hud() -> void:
	if event_cl == null or event_active.is_empty():
		return
	for c in event_cl.get_children():
		if c is Label:
			(c as Label).text = "EVENT: " + event_active.get("type", "").to_upper().replace("_", " ") + " (" + str(int(event_active.get("life", 0.0))) + "s)"
		if c is MeshInstance3D:
			var mat: StandardMaterial3D = (c as MeshInstance3D).material_override
			if mat:
				mat.emission_energy_multiplier = 0.6 + 0.4 * abs(sin(Time.get_ticks_msec() * 0.005))


func _resolve_random_event() -> void:
	var reward: int = event_active.get("reward", 0)
	sim_budget += reward
	stats_money_earned += reward
	_announce("EVENT RESOLVED +$" + str(reward), Color(0.4, 1.0, 0.4))
	_play_beep(660, 0.15, 0.3)
	_play_beep(880, 0.15, 0.3)
	_clear_event()


func _fail_random_event() -> void:
	_announce("EVENT FAILED", Color(0.6, 0.6, 0.6))
	_clear_event()


func _clear_event() -> void:
	event_active.clear()
	if event_cl:
		for c in event_cl.get_children():
			c.queue_free()
	event_timer = 0.0
	# Clear the roadblock cones that spawned with this event
	_clear_all_cones()

func _current_mission_idx() -> int:
	for i in range(missions.size()):
		if missions[i].get("id") == current_mission.get("id"):
			return i
	return 0


func save_city() -> void:
	var data := {
		"version": 4,
		"t": _t,
		"sim_day_count": sim_day_count,
		"sim_budget": sim_budget,
		"sim_population": sim_population,
		"sim_residential_tax_rate": sim_residential_tax_rate,
		"time_speed": time_speed,
		"wanted_level": wanted_level,
		"player_pos": [player_pos.x, player_pos.y, player_pos.z],
		"buildings": [],
		"custom_roads": [],
		"stats_npcs_killed": stats_npcs_killed,
		"stats_cars_smashed": stats_cars_smashed,
		"stats_money_earned": stats_money_earned,
		"stats_bullets_fired": stats_bullets_fired,
		"stats_distance_walked": stats_distance_walked,
		"stats_missions_failed": stats_missions_failed,
		"completed_missions": completed_missions,
		"current_mission_idx": _current_mission_idx(),
		"player_health": player_health,
		"ammo": ammo,
		"difficulty": difficulty,
		"total_play_time": total_play_time,
		"total_deaths": total_deaths,
		"weather_state": weather_state,
		"weather_timer": weather_timer,
	}
	for i in placed_buildings.size():
		var c: Vector3i = placed_buildings[i]
		var key := "%d,%d" % [c.x, c.y]
		data.buildings.append({
			"x": c.x,
			"z": c.y,
			"color": cell_color.get(key, 0),
			"density": cell_density.get(key, 1),
		})
	for r in custom_roads:
		data.custom_roads.append({"x": r.x, "y": r.y})
	var path := "user://city_save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	print("SAVE: %d buildings, $", placed_buildings.size(), sim_budget, " day ", sim_day_count)


func load_city() -> void:
	var path := "user://city_save.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	if data == null or not data is Dictionary:
		return
	# Wipe current city
	for b in building_meshes:
		b.queue_free()
	building_meshes.clear()
	placed_buildings.clear()
	cell_density.clear()
	cell_color.clear()
	# Wipe custom roads
	custom_roads.clear()
	for n in get_tree().get_nodes_in_group("custom_road"):
		n.queue_free()
	# Load new city
	for entry in data.buildings:
		_place_building(int(entry.x), int(entry.z), int(entry.color), int(entry.density))
	for r in data.get("custom_roads", []):
		_try_road(int(r.x), int(r.y))
	sim_day_count = int(data.get("sim_day_count", 0))
	sim_budget = int(data.get("sim_budget", 20000))
	sim_population = int(data.get("sim_population", 1250))
	sim_residential_tax_rate = float(data.get("sim_residential_tax_rate", 0.09))
	time_speed = float(data.get("time_speed", 1.0))
	wanted_level = int(data.get("wanted_level", 0))
	if data.has("player_pos") and data.player_pos is Array and data.player_pos.size() == 3:
		player_pos = Vector3(float(data.player_pos[0]), float(data.player_pos[1]), float(data.player_pos[2]))
		if player:
			player.position = player_pos
	_t = float(data.get("t", 0.5))
	_apply_time()
	stats_npcs_killed = int(data.get("stats_npcs_killed", 0))
	stats_cars_smashed = int(data.get("stats_cars_smashed", 0))
	stats_money_earned = int(data.get("stats_money_earned", 0))
	stats_bullets_fired = int(data.get("stats_bullets_fired", 0))
	stats_distance_walked = float(data.get("stats_distance_walked", 0.0))
	stats_missions_failed = int(data.get("stats_missions_failed", 0))
	player_health = int(data.get("player_health", player_max_health))
	ammo = int(data.get("ammo", max_ammo))
	difficulty = int(data.get("difficulty", 1))
	total_play_time = float(data.get("total_play_time", 0.0))
	total_deaths = int(data.get("total_deaths", 0))
	completed_missions = data.get("completed_missions", [])
	var cm_idx: int = int(data.get("current_mission_idx", 0))
	if cm_idx >= 0 and cm_idx < missions.size():
		current_mission = missions[cm_idx]
	# Pizza delivery needs live mesh state that isn't part of the save; if the
	# loaded mission is in flight, clean it up and re-queue from scratch so the
	# shop/target/box visuals reappear.
	if not current_mission.is_empty() and current_mission.get("id") == "pizza_delivery":
		_clean_delivery_mission()
		current_mission = {}
		# Don't auto-restart; let the player press M when ready.
	# Weather: backwards-compatible (defaults to clear when missing)
	weather_state = int(data.get("weather_state", 0))
	weather_timer = float(data.get("weather_timer", 0.0))
	_apply_weather_mod()
	_refresh_weather_label()
	print("LOAD: %d buildings, $", placed_buildings.size(), sim_budget, " day ", sim_day_count)
var cars: Array[MeshInstance3D] = []
var npcs: Array = []  # each: {mesh, path, idx, t}


func _build_cars() -> void:
	# Place 12 cars on random road paths
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 12:
		var path: Array = traffic_paths[rng.randi() % traffic_paths.size()]
		var car := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var is_vert: bool = path[0].x == path[-1].x
		mesh.size = Vector3(0.9 if is_vert else 1.6, 0.5, 1.6 if is_vert else 0.9)
		car.mesh = mesh
		var mat := StandardMaterial3D.new()
		var car_colors := [
			Color(0.85, 0.20, 0.15),
			Color(0.20, 0.40, 0.85),
			Color(0.85, 0.78, 0.20),
			Color(0.20, 0.65, 0.30),
			Color(0.55, 0.20, 0.65),
		]
		mat.albedo_color = car_colors[i % car_colors.size()]
		# headlights as small emissive
		mat.emission_enabled = false
		car.material_override = mat
		# Add 4 small lamp children (2 white front, 2 red rear) so night driving
		# looks right. Long axis depends on whether this car is on a vertical road.
		var body_size: Vector3 = Vector3(0.9 if is_vert else 1.6, 0.5, 1.6 if is_vert else 0.9)
		_add_car_lights(car, is_vert, body_size.z * 0.5, body_size.x * 0.5)
		add_child(car)
		car.set_meta("path", path)
		car.set_meta("t", rng.randf())
		car.set_meta("is_vert", is_vert)
		cars.append(car)


func _update_cars(delta: float) -> void:
	for car in cars:
		var path: Array = car.get_meta("path")
		var t: float = car.get_meta("t")
		t = fmod(t + delta * 0.07, 1.0)
		car.set_meta("t", t)
		var idx := int(t * (path.size() - 1))
		var frac := t * (path.size() - 1) - idx
		var a: Vector3 = path[idx]
		var b: Vector3 = path[min(idx + 1, path.size() - 1)]
		var p2 = a.lerp(b, frac)
		p2.y = 0.3
		car.position = p2
		# Face direction of motion
		var dir: Vector3 = (b - a).normalized()
		if dir.length() > 0.01:
			car.look_at(car.position + dir, Vector3.UP)
			# rotate so car's long axis aligns with motion
			if car.get_meta("is_vert"):
				car.rotate_object_local(Vector3(0, 1, 0), PI / 2)



func _build_hills() -> void:
	# Hills: pyramidal peaks OUTSIDE the city grid
	var peaks := [
		Vector3(_wx(-3 * CELL), 0, _wz(-3 * CELL)),
		Vector3(_wx(-2 * CELL), 0, _wz(-4 * CELL)),
		Vector3(_wx(GRID * CELL + 3 * CELL), 0, _wz(-2 * CELL)),
		Vector3(_wx(GRID * CELL + 2 * CELL), 0, _wz(-4 * CELL)),
	]
	for i in peaks.size():
		var p: Vector3 = peaks[i]
		var cone := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		# vary height for visual variety
		var h: float = [5.5, 4.0, 4.5, 3.5][i]
		mesh.top_radius = 0.0
		mesh.bottom_radius = 3.0 + (h - 3.5) * 0.3
		mesh.height = h
		cone.mesh = mesh
		var mat := StandardMaterial3D.new()
		# darker at the base, lighter green-grey on top via material override
		mat.albedo_color = Color(0.50, 0.55, 0.40)
		cone.material_override = mat
		cone.position = p + Vector3(0, h * 0.5, 0)
		add_child(cone)
		# snow cap on taller peaks
		if h >= 5.0:
			var cap := MeshInstance3D.new()
			var cap_mesh := CylinderMesh.new()
			cap_mesh.top_radius = 0.0
			cap_mesh.bottom_radius = 0.8
			cap_mesh.height = 1.0
			cap.mesh = cap_mesh
			var cap_mat := StandardMaterial3D.new()
			cap_mat.albedo_color = Color(0.92, 0.92, 0.95)
			cap.material_override = cap_mat
			cap.position = p + Vector3(0, h + 0.5, 0)
			add_child(cap)
		# A few trees on the hillside
		for tx in [-1, 1]:
			add_child(_make_box(Vector3(0.3, 0.8, 0.3), p + Vector3(tx * 2.0, 0.4, 2.0), Color(0.40, 0.25, 0.15)))
			add_child(_make_box(Vector3(1.0, 1.2, 1.0), p + Vector3(tx * 2.0, 1.4, 2.0), Color(0.18, 0.40, 0.18)))

# ---------------- Weather system ----------------
# Three states: 0=clear, 1=rain, 2=storm. State cycles automatically every
# `weather_state_duration` seconds (default 90). Rain particles are 240
# thin emissive-blue vertical boxes pre-positioned across the city extent
# and animated downward, recycled to the top when they reach y<=0. Storm
# state adds wind drift on the X axis. Weather_ambient_mod feeds into
# _apply_time() to dim ambient + greys the daytime sky. Manual cycle via
# N key. Cmdline flags: --rain / --storm force a starting state.

const RAIN_DROP_COUNT := 240
const RAIN_AREA_HALF := 36.0  # spread a little beyond HALF=32 so drops hit hills too
const RAIN_TOP_Y := 22.0      # ceiling where drops spawn
const RAIN_FALL_SPEED := 18.0 # units/sec

func _build_weather() -> void:
	# Parent Node3D so we can scale/transparent-toggle in one shot
	rain_root = Node3D.new()
	rain_root.name = "WeatherRoot"
	add_child(rain_root)
	# Pre-build all rain drops once. Each drop is a thin tall box (like a
	# stretched-out light streak). Materials are cheap (shared StandardMaterial3D
	# would be ideal but visibility-per-drop wants a per-drop state, so we keep
	# a small per-drop material override).
	for i in RAIN_DROP_COUNT:
		var drop := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		# Thin, tall: looks like a rain streak
		mesh.size = Vector3(0.04, 0.9, 0.04)
		drop.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.75, 0.95)
		mat.emission_enabled = true
		mat.emission = Color(0.55, 0.75, 0.95)
		mat.emission_energy_multiplier = 0.6
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Transparency so the streaks don't look like solid bars
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.55
		drop.material_override = mat
		# Initial random position across the city footprint
		drop.position = Vector3(
			randf_range(-RAIN_AREA_HALF, RAIN_AREA_HALF),
			randf_range(0.5, RAIN_TOP_Y),
			randf_range(-RAIN_AREA_HALF, RAIN_AREA_HALF))
		# Per-drop speed variance for visual variety
		drop.set_meta("speed", RAIN_FALL_SPEED * randf_range(0.85, 1.15))
		# Slight per-drop horizontal drift so rain looks slanted in storm
		drop.set_meta("drift", randf_range(-0.4, 0.4))
		# Storm drops are longer (more dramatic streaks)
		if i < RAIN_DROP_COUNT / 2:
			drop.scale = Vector3(1.0, 1.0, 1.0)
		else:
			drop.scale = Vector3(1.0, 2.2, 1.0)  # long streaks
		rain_root.add_child(drop)
		rain_drops.append(drop)
	rain_root.visible = false  # hidden when state=clear
	# HUD badge (top-left, just below the wanted meter) — create FIRST so
	# _apply_weather_mod can toggle its visibility correctly on the initial state.
	var cl := CanvasLayer.new()
	cl.layer = 5
	add_child(cl)
	weather_label = Label.new()
	weather_label.position = Vector2(12, 86)
	weather_label.add_theme_font_size_override("font_size", 16)
	weather_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	cl.add_child(weather_label)
	# Now apply the mod for the initial state (label exists, so visibility toggles correctly)
	_apply_weather_mod()
	_refresh_weather_label()

func _refresh_weather_label() -> void:
	if weather_label == null:
		return
	var name_str: String = weather_state_names[weather_state]
	var icon: String = weather_state_icons[weather_state]
	var col: Color = Color(1.0, 0.9, 0.4)
	if weather_state == 1:
		col = Color(0.55, 0.75, 0.95)
	elif weather_state == 2:
		col = Color(0.85, 0.65, 0.95)
	weather_label.add_theme_color_override("font_color", col)
	weather_label.text = "Weather: %s  (%s)" % [name_str, icon]

func _apply_weather_mod() -> void:
	match weather_state:
		0: weather_ambient_mod = 0.0   # clear: no change
		1: weather_ambient_mod = -0.20 # rain: subtle dim
		2: weather_ambient_mod = -0.35 # storm: noticeable dim
	rain_root.visible = weather_state != 0
	# Hide HUD label if no CanvasLayer
	if weather_label:
		weather_label.visible = weather_state != 0
	_apply_time()  # re-evaluate sky/ambient for the new state

func _update_weather(delta: float) -> void:
	# Cycle states automatically (sim-time scaled to match weather_state_duration)
	# time_speed scales this too, so a fast-forward speeds weather cycles
	weather_timer += delta * time_speed
	if weather_timer >= weather_state_duration:
		weather_timer = 0.0
		weather_state = (weather_state + 1) % 3
		_apply_weather_mod()
		_refresh_weather_label()
		_announce("WEATHER: " + weather_state_names[weather_state],
			Color(0.55, 0.75, 0.95) if weather_state == 1 else
			(Color(0.85, 0.65, 0.95) if weather_state == 2 else Color(1.0, 0.9, 0.4)))
	# Animate rain drops only when raining
	if weather_state == 0:
		return
	# Storm has stronger wind (X drift); rain is mostly vertical
	var wind_x: float = 0.0
	if weather_state == 2:
		wind_x = 1.2 + sin(weather_timer * 0.7) * 0.5
	for drop in rain_drops:
		if not is_instance_valid(drop):
			continue
		var base_speed: float = drop.get_meta("speed") as float
		var drift: float = drop.get_meta("drift") as float
		var fall: float = base_speed * (1.1 if weather_state == 2 else 1.0)
		drop.position.y -= fall * delta
		drop.position.x += (wind_x + drift) * delta
		# Recycle when below ground
		if drop.position.y <= 0.2:
			drop.position.y = RAIN_TOP_Y + randf() * 4.0
			drop.position.x = randf_range(-RAIN_AREA_HALF, RAIN_AREA_HALF)
			drop.position.z = randf_range(-RAIN_AREA_HALF, RAIN_AREA_HALF)

func _cycle_weather() -> void:
	# Manual override (N key) — reset timer so it doesn't auto-cycle right after
	weather_state = (weather_state + 1) % 3
	weather_timer = 0.0
	_apply_weather_mod()
	_refresh_weather_label()
	_announce("WEATHER: " + weather_state_names[weather_state],
		Color(0.55, 0.75, 0.95) if weather_state == 1 else
		(Color(0.85, 0.65, 0.95) if weather_state == 2 else Color(1.0, 0.9, 0.4)))
