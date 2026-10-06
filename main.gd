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
var cam_pitch := -65.0
var cam_yaw := 35.0
var cam_dist := 75.0
var cam_topdown := false
var hover_cell := Vector2i(-1, -1)


func _ready() -> void:
	buildings_root = Node3D.new()
	add_child(buildings_root)
	_build_ground()
	_build_hills()
	_build_water()
	_build_traffic()
	_build_cars()
	_build_trees()
	_build_roads()
	_build_initial_buildings()
	_build_lamps()
	_build_light_env()
	_build_camera()
	_build_hud()

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


var growth_accum := 0.0

func _process(delta: float) -> void:
	# Slowly advance time so user sees day/night if windowed
	_t = fmod(_t + delta * 0.02, 1.0)
	_apply_time()
	_update_traffic(delta)
	_update_cars(delta)
	# Growth: every 0.5s, randomly bump a built cell to a higher density
	growth_accum += delta
	if growth_accum > 0.5:
		growth_accum -= 0.5
		_grow_random_cell()
	_refresh_hud()


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
			if hover_cell.x >= 0 and hover_cell.y >= 0:
				if not _is_road(hover_cell.x, hover_cell.y) and _in_bounds(hover_cell.x, hover_cell.y):
					if not _is_water(hover_cell.x, hover_cell.y):
						_place_building(hover_cell.x, hover_cell.y, randi() % 3, DENSITY_LOW)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam_dist = maxf(cam_dist - 5, 20.0)
			_refresh_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_dist = minf(cam_dist + 5, 200.0)
			_refresh_camera()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_T:
				cam_topdown = not cam_topdown
				_refresh_camera()
			KEY_F5:
				save_city()
			KEY_F9:
				load_city()


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
	pmat.albedo_color = Color(0.55, 0.65, 0.40)
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
	# Pond: 14x14 lake in upper-right corner (avoids hills)
	add_child(_make_box(
		Vector3(14.0, 0.04, 14.0),
		Vector3(_wx(GRID * CELL + 3 * CELL), river_y, _wz(-3 * CELL)),
		Color(0.30, 0.50, 0.78)))
	# Beach around pond (south edge - lighter sand)
	add_child(_make_box(
		Vector3(15.0, 0.04, 1.5),
		Vector3(_wx(GRID * CELL + 3 * CELL), river_y - 0.01, _wz(-3 * CELL) + 7),
		Color(0.85, 0.80, 0.65)))


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
	env.ambient_light_energy = lerpf(0.35, 0.8, is_day as float)
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


func _refresh_hud() -> void:
	if hud_label:
		hud_label.text = "SYNDICATE CITY   Feb 1926   $20,000   Pop 1,250   placed=%d" % placed_buildings.size()
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



func save_city() -> void:
	var data := {
		"version": 1,
		"t": _t,
		"buildings": [],
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
	var path := "user://city_save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	print("SAVE: %d buildings -> %s" % [data.buildings.size(), path])


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
	# Load new city
	for entry in data.buildings:
		_place_building(int(entry.x), int(entry.z), int(entry.color), int(entry.density))
	_t = float(data.get("t", 0.5))
	print("LOAD: %d buildings" % placed_buildings.size())
var cars: Array[MeshInstance3D] = []


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
