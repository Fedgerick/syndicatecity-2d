extends Node3D

## Step 4: day/night cycle. Time-based sun, window emission at night.

const GRID := 32
const CELL := 2.0
const ROAD_EVERY := 4

var sun: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var _t := 0.5  # 0..1 day phase, default afternoon
var lamps: Array[MeshInstance3D] = []


func _ready() -> void:
	_build_ground()
	_build_water()
	_build_trees()
	_build_roads()
	_build_buildings()
	_build_lamps()
	_build_light_env()
	_build_camera()
	_build_hud()

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--time="):
			_t = float(a.substr(7))
	if "--capture" in args:
		_apply_time()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://capture.png")
		print("CITY: saved t=", _t)
		get_tree().quit(0)


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
	pmesh.size = Vector2(GRID * CELL * 2, GRID * CELL * 2)
	plane.mesh = pmesh
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.45, 0.55, 0.35)
	plane.material_override = pmat
	add_child(plane)


func _build_water() -> void:
	add_child(_make_box(Vector3(GRID * CELL, 0.05, 8),
		Vector3(GRID * CELL * 0.5, 0.0, GRID * CELL - 4),
		Color(0.30, 0.50, 0.78)))
	add_child(_make_box(Vector3(8, 0.05, 8),
		Vector3(GRID * CELL - 8, 0.0, GRID * CELL - 8),
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
			Vector3(x * CELL, 0.5, z * CELL), Color(0.45, 0.30, 0.20)))
		add_child(_make_box(Vector3(1.2, 1.5, 1.2),
			Vector3(x * CELL, 1.75, z * CELL), Color(0.20, 0.45, 0.20)))


func _is_road(x: int, z: int) -> bool:
	return x % ROAD_EVERY == 0 or z % ROAD_EVERY == 0


func _build_roads() -> void:
	for x in GRID:
		for z in GRID:
			if _is_road(x, z):
				add_child(_make_box(
					Vector3(CELL * 0.9, 0.06, CELL * 0.9),
					Vector3(x * CELL, 0.03, z * CELL),
					Color(0.18, 0.18, 0.18)))


func _build_buildings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var colors := [
		Color(0.85, 0.78, 0.55),
		Color(0.50, 0.65, 0.85),
		Color(0.70, 0.55, 0.40),
	]
	for x in GRID:
		for z in GRID:
			if _is_road(x, z) or z > GRID - 6:
				continue
			if rng.randf() < 0.55:
				var h := rng.randf_range(1.0, 4.0)
				var c: Color = colors[rng.randi() % 3]
				add_child(_make_box(
					Vector3(CELL * 0.8, h, CELL * 0.8),
					Vector3(x * CELL, h * 0.5, z * CELL), c))


func _build_lamps() -> void:
	for x in range(0, GRID + 1, ROAD_EVERY):
		for z in range(0, GRID + 1, ROAD_EVERY):
			if x > GRID or z > GRID or z > GRID - 6:
				continue
			add_child(_make_box(Vector3(0.1, 1.4, 0.1),
				Vector3(x * CELL, 0.7, z * CELL), Color(0.15, 0.15, 0.18)))
			# emissive head — registered so we can dim by day phase
			var h := _make_box(Vector3(0.25, 0.18, 0.25),
				Vector3(x * CELL, 1.45, z * CELL), Color(1.0, 0.85, 0.5), true)
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
	# t in [0,1]: 0 = midnight, 0.5 = noon, 0.75 = dusk, 1 = back to midnight
	# Sun angle: rise at 0.25, peak at 0.5, set at 0.75
	var sun_phase: float = (_t - 0.25) / 0.5  # 0..1 over day
	sun_phase = clamp(sun_phase, 0.0, 1.0)
	var sun_angle: float = sun_phase * PI  # 0..180°
	var sun_height: float = sin(sun_angle)
	sun.rotation_degrees = Vector3(-rad_to_deg(asin(sun_height)), -30, 0)
	var is_day := sun_height > 0.0
	sun.light_energy = max(sun_height * 1.2, 0.0)
	sun.light_color = Color(1.0, lerpf(0.6, 0.95, is_day as float), lerpf(0.4, 0.85, is_day as float))
	env.ambient_light_energy = lerpf(0.15, 0.6, is_day as float)
	# Sky darkens at night
	if not is_day:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.05, 0.07, 0.15)
	else:
		env.background_mode = Environment.BG_SKY
	# Lamp emission: bright at night, dim during day
	var lamp_e := lerpf(1.5, 0.0, is_day as float)
	for lm in lamps:
		var mat: StandardMaterial3D = lm.material_override
		mat.emission_energy_multiplier = lamp_e


func _build_camera() -> void:
	var cam := Camera3D.new()
	var center := Vector3(GRID * CELL * 0.5, 0, GRID * CELL * 0.5)
	# isometric-ish: high pitch, slight yaw
	var dist := GRID * CELL * 1.2
	var pitch := deg_to_rad(-65)
	var yaw := deg_to_rad(35)
	cam.position = center + Vector3(
		sin(yaw) * cos(pitch) * dist,
		-sin(pitch) * dist,
		cos(yaw) * cos(pitch) * dist)
	add_child(cam)
	cam.look_at(center, Vector3.UP)
	cam.make_current()


func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.size = Vector2(800, 40)
	cl.add_child(bg)
	var lbl := Label.new()
	lbl.text = "SYNDICATE CITY   Feb 1926   $20,000   Pop 1,250"
	lbl.position = Vector2(12, 10)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.94, 0.88))
	cl.add_child(lbl)