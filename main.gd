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
	_build_water()
	_build_traffic()
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
	_refresh_hud()
	_update_traffic(delta)


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
						_place_building(hover_cell.x, hover_cell.y, randi() % 3)
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
	add_child(_make_box(Vector3(GRID * CELL, 0.05, 8),
		Vector3(0, 0.0, HALF - 4),
		Color(0.30, 0.50, 0.78)))
	add_child(_make_box(Vector3(8, 0.05, 8),
		Vector3(HALF - 8, 0.0, HALF - 8),
		Color(0.30, 0.50, 0.78)))


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
	return z > GRID - 6


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


var building_meshes: Array[MeshInstance3D] = []

func _place_building(x: int, z: int, color_idx: int, h: float = -1.0) -> void:
	if h < 0:
		h = randf_range(1.0, 4.0)
	var b := _make_box(Vector3(CELL * 0.8, h, CELL * 0.8),
		Vector3(_wx(x * CELL), h * 0.5, _wz(z * CELL)), _zone_color(color_idx))
	buildings_root.add_child(b)
	placed_buildings.append(Vector3i(x, z, color_idx))
	building_meshes.append(b)


func _build_initial_buildings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for x in GRID:
		for z in GRID:
			if _is_road(x, z) or _is_water(x, z):
				continue
			if rng.randf() < 0.55:
				_place_building(x, z, rng.randi() % 3)


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
	if not is_day:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.05, 0.07, 0.15)
	else:
		env.background_mode = Environment.BG_SKY
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

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.size = Vector2(800, 40)
	cl.add_child(bg)
	hud_label = Label.new()
	hud_label.position = Vector2(12, 10)
	hud_label.add_theme_font_size_override("font_size", 16)
	hud_label.add_theme_color_override("font_color", Color(0.95, 0.94, 0.88))
	cl.add_child(hud_label)
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
