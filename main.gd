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
var sim_unlocked: Array[String] = ["Basic Zone"]
var missions: Array = []  # active missions
var completed_missions: Array = []  # strings of completed mission IDs
var current_mission: Dictionary = {}
var mission_overlay: CanvasLayer
var mission_label: Label
var mission_objective: Label
var wanted_level: int = 0  # 0..5 stars
var wanted_timer: float = 0.0
var police: Array = []  # list of {mesh, pos, target_pos, speed}
var pickups: Array = []  # {mesh, pos, type: "money"|"health", value}
var player_health: int = 100
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
var sim_speed: float = 1.0
var controls_overlay: CanvasLayer
var controls_label: Label


func _ready() -> void:
	buildings_root = Node3D.new()
	add_child(buildings_root)
	_build_ground()
	_build_hills()
	_build_water()
	_build_traffic()
	_build_cars()
	_build_parked_cars()
	_build_pickups()
	_build_npcs()
	_build_trees()
	_build_roads()
	_build_initial_buildings()
	_build_lamps()
	_build_police()
	_build_burglar()
	_setup_missions()
	_build_light_env()
	_build_camera()
	_build_player()
	_build_minimap()
	_build_hud()
	demand_bars_root = Node.new()
	hud_label.add_child(demand_bars_root)

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--time="):
			_t = float(a.substr(7))
	_apply_time()

	for a in args:
		if a == "--topdown":
			cam_topdown = true
			_refresh_camera()

	if "--capture" in args:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://capture.png")
		print("CITY: saved t=", _t, " placed=", placed_buildings.size())
		get_tree().quit(0)



func _process(delta: float) -> void:
	# Slowly advance time so user sees day/night if windowed
	_t = fmod(_t + delta * 0.02, 1.0)
	_apply_time()
	_update_traffic(delta)
	_update_cars(delta)
	_update_police(delta)
	_update_mission(delta)
	_update_wanted(delta)
	_update_npcs(delta)
	_update_pickups(delta)
	_update_player(delta)
	_update_vehicle(delta)
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


func _sim_daily_tick() -> void:
	# Count buildings by zone type (color_index 0=residential, 1=commercial, 2=industrial)
	var r_count: int = 0
	var c_count: int = 0
	var i_count: int = 0
	for b in placed_buildings:
		match b.z:
			0: r_count += 1
			1: c_count += 1
			2: i_count += 1

	# Demand: R wants jobs nearby; C wants residents; I wants commercial
	# SimCity-ish: R demand = 100 - clamp(jobs/2, 0, 100) + residential quality
	var r_base: float = 100.0 - clamp(c_count * 4.0, 0.0, 80.0) + (sim_budget / 500.0)
	var c_base: float = clamp(r_count * 6.0, 0.0, 100.0) - (i_count * 2.0)
	var i_base: float = clamp(c_count * 5.0, 0.0, 100.0) - (r_count * 1.0)
	sim_residential_demand = clamp(r_base, 0.0, 100.0)
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

	sim_day_count += 1


func _grow_random_cell() -> void:
	if placed_buildings.is_empty():
		return
	var idx: int = randi() % placed_buildings.size()
	var cell: Vector3i = placed_buildings[idx]
	var key := "%d,%d" % [cell.x, cell.y]
	var d: int = cell_density.get(key, 1)
	if d >= DENSITY_MAX:
		return
	d += 1
	cell_density[key] = d
	_refresh_building_at(cell.x, cell.y)


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
		match event.keycode:
			KEY_1: current_tool = "zone_res"
			KEY_2: current_tool = "zone_com"
			KEY_3: current_tool = "zone_ind"
			KEY_4: current_tool = "road"
			KEY_5: current_tool = "bulldoze"
			KEY_0, KEY_SPACE: current_tool = "select"
			KEY_T: cam_topdown = not cam_topdown; _refresh_camera()
			KEY_F5: save_city()
			KEY_F9: load_city()
			KEY_PLUS, KEY_KP_ADD: sim_speed = clamp(sim_speed * 1.5, 0.25, 8.0)
			KEY_MINUS, KEY_KP_SUBTRACT: sim_speed = clamp(sim_speed / 1.5, 0.25, 8.0)
			KEY_H: _toggle_controls()
			KEY_C:
				cam_thirdperson = true
				_refresh_player_camera()
			KEY_V:
				cam_thirdperson = false
				_refresh_camera()
		_refresh_controls()


func _apply_tool_at_hover() -> void:
	if hover_cell.x < 0 or hover_cell.y < 0:
		return
	if not _in_bounds(hover_cell.x, hover_cell.y):
		return
	match current_tool:
		"zone_res": _try_zone(hover_cell.x, hover_cell.y, 0)
		"zone_com": _try_zone(hover_cell.x, hover_cell.y, 1)
		"zone_ind": _try_zone(hover_cell.x, hover_cell.y, 2)
		"road": _try_road(hover_cell.x, hover_cell.y)
		"bulldoze": _try_bulldoze(hover_cell.x, hover_cell.y)
	_refresh_hud()
	_refresh_wanted_label()
	_update_minimap()


func _try_zone(x: int, z: int, color: int) -> void:
	if _is_water(x, z):
		return
	if sim_budget < tool_cost_zone:
		return
	for i in range(placed_buildings.size()):
		var b: Vector3i = placed_buildings[i]
		if b.x == x and b.y == z:
			var cur_density: int = cell_density.get(_bk(x, z), 0)
			if b.z == color and sim_budget >= tool_cost_zone:
				if cur_density >= 3:
					return
				sim_budget -= tool_cost_zone
				cell_density[_bk(x, z)] = cur_density + 1
				_refresh_building_at(x, z)
				return
			else:
				if sim_budget >= tool_cost_zone + tool_cost_bulldoze:
					sim_budget -= tool_cost_bulldoze
					sim_budget -= tool_cost_zone
					placed_buildings[i] = Vector3i(x, z, color)
					cell_density[_bk(x, z)] = 0
					_refresh_building_at(x, z)
					return
				return
	if not _is_road_adjacent(x, z):
		return
	sim_budget -= tool_cost_zone
	_place_building(x, z, color, 0)

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
			sim_budget += tool_cost_zone / 2
			placed_buildings.remove_at(i)
			_refresh_building_at(x, z)
			return
	for i in range(custom_roads.size()):
		if custom_roads[i].x == x and custom_roads[i].y == z:
			sim_budget += tool_cost_road / 2
			custom_roads.remove_at(i)
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
		_: tool_name = "SELECT"
	controls_label.text = "Tool: %s   Speed: %.2fx   [H] Help" % [tool_name, sim_speed]






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
	buildings_root.add_child(b)
	placed_buildings.append(Vector3i(x, z, color_idx))
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
	if is_day:
		env.background_mode = Environment.BG_SKY
		env.ambient_light_sky_contribution = 1.0
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.05, 0.07, 0.15)
		env.ambient_light_sky_contribution = 0.3
	var lamp_e := lerpf(1.5, 0.0, is_day as float)
	for lm in lamps:
		var mat: StandardMaterial3D = lm.material_override
		mat.emission_energy_multiplier = lamp_e
	# Building windows glow at night
	var window_e := lerpf(0.0, 1.2, (not is_day) as float)
	for b in building_meshes:
		var bmat: StandardMaterial3D = b.material_override
		bmat.emission_enabled = not is_day
		if not is_day:
			bmat.emission = Color(1.0, 0.85, 0.4)


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
	var cam: Camera3D = $Camera3D
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




	# Controls overlay (top-right under time slider)
	controls_overlay = CanvasLayer.new()
	add_child(controls_overlay)
	var ctl_bg := ColorRect.new()
	ctl_bg.color = Color(0, 0, 0, 0.65)
	ctl_bg.size = Vector2(360, 270)
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
	help.text = "1=Res  2=Com  3=Ind\n4=Road  5=Bulldoze\n0/Space = Select\nClick to apply tool\nWASD = Move\nF = Enter/Exit car\nE = Enter building\nEsc = Exit\nC/V = Cam toggle\nH = Hide help\nF5/F9 = Save/Load\n+/- = Speed\nT = Top-down\nM = Next mission"
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

func _refresh_hud() -> void:
	if hud_label:
		var hp_str: String = "HP:%d" % player_health
		var bsign: String = "-" if sim_budget < 0 else ""
		hud_label.text = "SYNDICATE CITY   %s   Day %d   $%s%s   Pop %d   placed=%d" % [
			hp_str,
			sim_day_count,
			bsign,
			_abs_budget_fmt(),
			sim_population,
			placed_buildings.size()]
	if demand_bars_root != null:
		_refresh_demand_bars()
var traffic_dots: Array[MeshInstance3D] = []
var traffic_paths: Array = []  # each = Array of Vector3 world positions


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
	for n in npcs:
		var t: float = n["t"]
		t += delta * n["speed"] * n["dir"] / (n["path"][1] - n["path"][0]).length()
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
	# A few props
	for px in [-0.7, 0.0, 0.7]:
		interior_root.add_child(_make_box(Vector3(0.4, 0.4, 0.4),
			Vector3(_wx(x * CELL) + px, 0.3, _wz(z * CELL) - 0.5),
			Color(0.55, 0.45, 0.30)))
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
		# Catch: end game if police touch player
		if wanted_level > 0 and dist < 1.5:
			_busted()
		# Run over NPCs/player with a vehicle
		if vehicle_in and current_vehicle != null:
			var dveh: float = p["pos"].distance_to(current_vehicle_pos)
			if dveh < 1.8:
				# Player rammed a police car: instant wanted
				wanted_level = clamp(wanted_level + 1, 0, 5)


func _busted() -> void:
	# Reset wanted, dock budget, take player to nearest cell (the police station)
	wanted_level = 0
	sim_budget -= 200
	# Send player back to a road cell
	player_pos = Vector3(_wx(4 * CELL), 0.7, _wz(8 * CELL))
	player.position = player_pos
	if vehicle_in:
		_exit_vehicle()


func _add_wanted(amount: int) -> void:
	wanted_level = clamp(wanted_level + amount, 0, 5)
	wanted_timer = 10.0  # seconds before it starts decaying


func _update_wanted(delta: float) -> void:
	if wanted_level == 0:
		return
	wanted_timer -= delta
	if wanted_timer <= 0.0:
		wanted_level = max(0, wanted_level - 1)
		wanted_timer = 8.0


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
	_build_mission_overlay()


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
		mission_objective.text = current_mission["objective"]
	elif current_mission["status"] == "complete":
		mission_objective.text = "MISSION COMPLETE! Press M for next mission."
	elif current_mission["status"] == "failed":
		mission_objective.text = "Mission failed."


func _update_mission(delta: float) -> void:
	if current_mission.is_empty() or current_mission.get("status") != "active":
		return
	var d: float = player_pos.distance_to(current_mission["target_pos"])
	if d < current_mission["target_radius"]:
		_complete_mission()


func _complete_mission() -> void:
	current_mission["status"] = "complete"
	var reward: int = current_mission.get("reward", 0)
	sim_budget += reward
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
			else:
				player_health = min(100, player_health + p2["value"])
			p2["mesh"].queue_free()
			pickups.remove_at(i)

func save_city() -> void:
	var data := {
		"version": 2,
		"t": _t,
		"sim_day_count": sim_day_count,
		"sim_budget": sim_budget,
		"sim_population": sim_population,
		"sim_speed": sim_speed,
		"wanted_level": wanted_level,
		"player_pos": [player_pos.x, player_pos.y, player_pos.z],
		"buildings": [],
		"custom_roads": [],
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
	sim_speed = float(data.get("sim_speed", 1.0))
	wanted_level = int(data.get("wanted_level", 0))
	if data.has("player_pos") and data.player_pos is Array and data.player_pos.size() == 3:
		player_pos = Vector3(float(data.player_pos[0]), float(data.player_pos[1]), float(data.player_pos[2]))
		if player:
			player.position = player_pos
	_t = float(data.get("t", 0.5))
	_apply_time()
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
