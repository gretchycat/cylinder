extends SceneTree

const Bush = preload("res://assets/maps/default/models/ground_clutter/woodland_bush.gd")
const Geometry = preload("res://assets/maps/default/models/ground_clutter/clutter_geometry.gd")
var failures: int = 0
var camera: Camera3D
var holder: Node3D
var clutter: ClutterManager
var world: CylinderGenerator
var doc: Dictionary

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var started: int = Time.get_ticks_usec()
	var mesh: ArrayMesh = Bush.build(1.10, 0.95)
	print("BUSH_BUILD_US: ", Time.get_ticks_usec() - started)
	var arrays: Array = mesh.surface_get_arrays(0)
	var triangles: int = arrays[Mesh.ARRAY_INDEX].size() / 3
	var low_mesh: ArrayMesh = Bush.build(1.10, 0.95, 1)
	var low_triangles: int = low_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
	print("BUSH_TRIANGLES: ", triangles, " LOD1_TRIANGLES: ", low_triangles, " VERTICES: ", arrays[Mesh.ARRAY_VERTEX].size(), " BOUNDS: ", mesh.get_aabb())
	check(mesh.get_surface_count() == 1 and triangles < 1800, "Bush uses one surface within 1800-triangle budget")
	check(RenderingServer.mesh_get_surface(mesh.get_rid(), 0).get("lods", []).size() == 2, "Two native mesh LODs are present for instanced rendering")
	check(low_triangles < triangles * 0.65, "Distant mesh reduces triangles by at least 35 percent")
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var valid_faces: bool = true
	for index: int in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[index]]
		var b: Vector3 = vertices[indices[index + 1]]
		var c: Vector3 = vertices[indices[index + 2]]
		if not a.is_finite() or (b - a).cross(c - a).length_squared() < 1e-14:
			valid_faces = false
	check(valid_faces, "Bush has finite vertices and no degenerate triangles")
	check(mesh.get_aabb().position.y >= -0.01 and mesh.get_aabb().size.y < 1.25, "Bush stays rooted and within existing metre-scale envelope")
	check(arrays[Mesh.ARRAY_VERTEX] == Bush.build(1.10, 0.95).surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "Geometry generation is deterministic")
	doc = MapConfig.load_map_config("default")
	world = CylinderGenerator.new()
	clutter = ClutterManager.new()
	clutter.cylinder_world = world
	clutter.map_config = doc
	clutter.view_radius = 220.0
	clutter.fade_distance = 60.0
	clutter.chunk_size = 40.0
	var source: MeshInstance3D = MeshInstance3D.new()
	source.mesh = mesh
	var parts: Array = []
	clutter._collect_parts(source, Transform3D.IDENTITY, doc.ground_clutter.models.shrubs, parts)
	check(parts.size() == 1 and parts[0].material.get_shader_parameter("albedo_texture") == Bush.ATLAS, "Clutter material retains bush atlas")
	var check_root: Node3D = Node3D.new()
	var test_transforms: Array[Transform3D] = [Transform3D.IDENTITY]
	var test_colors: Array[Color] = [Color(0.25, 0.60, 0.15, 1.0)]
	clutter._add_multimesh_to_chunk(check_root, "BushCheck", parts[0].mesh, parts[0].material, test_transforms, test_colors, test_colors)
	check(is_equal_approx((check_root.get_child(0) as MultiMeshInstance3D).extra_cull_margin, 0.1), "Bush bounds allow distance LOD instead of retaining the generic 150m padding")
	var instances: MultiMesh = (check_root.get_child(0) as MultiMeshInstance3D).multimesh
	if DisplayServer.get_name() != "headless":
		check(instances.get_instance_color(0).is_equal_approx(Color.WHITE) and instances.get_instance_custom_data(0).is_equal_approx(test_colors[0]), "Bark retains its pigment while leaves receive the biome palette once")
	else:
		check(bool(parts[0].mesh.get_meta("palette_in_custom_data", false)) and instances.use_custom_data, "Instanced bush preserves separate foliage palette metadata")
	check_root.free()
	source.free()
	if DisplayServer.get_name() == "headless":
		clutter.free()
		world.free()
		quit(failures)
		return
	root.size = Vector2i(1280, 900)
	root.mesh_lod_threshold = 1.0
	root.scaling_3d_scale = 1.0
	root.msaa_3d = Viewport.MSAA_2X
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.11, 0.14, 0.16)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.70, 0.80, 0.95)
	environment.environment.ambient_light_energy = 0.45
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.91, 0.77)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	stage.add_child(sun)
	var floor_node: MeshInstance3D = MeshInstance3D.new()
	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = Vector2(100, 100)
	floor_node.mesh = floor_mesh
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.19, 0.17, 0.13)
	floor_material.roughness = 1.0
	floor_node.material_override = floor_material
	stage.add_child(floor_node)
	camera = Camera3D.new()
	camera.fov = 38.0
	stage.add_child(camera)
	holder = Node3D.new()
	stage.add_child(holder)
	var material: ShaderMaterial = parts[0].material
	material.set_shader_parameter("air_density", 0.0)
	material.set_shader_parameter("wind_strength", 0.018)
	material.set_shader_parameter("gradient_mode", 0)
	material.set_shader_parameter("base_color", Color.WHITE)
	material.set_shader_parameter("cylinder_radius", 4000.0)
	var legacy_mesh: ArrayMesh = _legacy_bush()
	var legacy_material: ShaderMaterial = material.duplicate()
	legacy_material.set_shader_parameter("albedo_texture", null)
	if not OS.get_cmdline_user_args().has("--benchmark-only"):
		_show(mesh, material, 1)
		await _shot("bush-front", Vector3(1.75, 1.25, 2.15), Vector3(0, 0.52, 0))
		await _shot("bush-back", Vector3(-1.9, 1.1, -2.1), Vector3(0, 0.52, 0))
		await _shot("bush-detail", Vector3(0.48, 1.18, 0.92), Vector3(0.10, 0.62, 0.02))
		_show(low_mesh, material, 1)
		await _shot("bush-lod1", Vector3(1.75, 1.25, 2.15), Vector3(0, 0.52, 0))
		_show(legacy_mesh, legacy_material, 1)
		await _shot("bush-before", Vector3(1.75, 1.25, 2.15), Vector3(0, 0.52, 0))
	if OS.get_cmdline_user_args().has("--screenshots-only"):
		clutter.free()
		world.free()
		quit(failures)
		return
	root.size = Vector2i(640, 450)
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.scaling_3d_scale = 0.75
	print("BENCH_RESOLUTION: 640x450 at 0.75 render scale, no MSAA")
	for entry: Dictionary in [{"name": "before", "mesh": legacy_mesh, "material": legacy_material}, {"name": "after", "mesh": mesh, "material": material}]:
		_show(entry.mesh, entry.material, 256)
		camera.position = Vector3(14, 9, 20)
		camera.look_at(Vector3(10, 0.3, 10))
		for frame: int in range(2):
			await process_frame
		var start: int = Time.get_ticks_usec()
		for frame: int in range(8):
			await process_frame
		print("BENCH_256_", entry.name, " mean_frame_ms=", float(Time.get_ticks_usec() - start) / 8000.0, " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " rendered_primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		await _shot("bush-field-" + entry.name, camera.position, Vector3(10, 0.3, 10))
	clutter.free()
	world.free()
	quit(failures)

func _show(mesh: Mesh, material: Material, count: int) -> void:
	for child: Node in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for index: int in range(count):
		var position: Vector3 = Vector3.ZERO if count == 1 else Vector3(index % 16 * 1.35, 0, index / 16 * 1.35)
		transforms.append(Transform3D(Basis(Vector3.UP, float(index) * 2.39996), position))
		colors.append(Color(0.30, 0.52, 0.18, 1.0))
	clutter._add_multimesh_to_chunk(holder, "BushPreview", mesh, material, transforms, colors, colors)

func _shot(label: String, position: Vector3, target: Vector3) -> void:
	camera.position = position
	camera.look_at(target)
	for frame: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://build/" + label + ".png") == OK, "Saved " + label)

# Prior sphere placeholder retained only as a reproducible benchmark fixture.
func _legacy_bush() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center: Vector3 = Vector3(0, 0.95 * 0.45, 0)
	for index: int in range(7):
		var angle: float = TAU * float(index) / 7.0
		var radius: float = 1.10 * (0.20 + 0.12 * float(index % 3))
		var point: Vector3 = Vector3(cos(angle) * radius, 0.95 * (0.35 + 0.08 * float(index % 2)), sin(angle) * radius)
		var value: float = 0.92 + 0.14 * sin(float(index * 3 + 1))
		st.set_color(Color(0.70 * value, 0.70 * value, 0.70 * value, 1.0))
		Geometry._add_uv_sphere(st, point, 1.10 * (0.20 + 0.025 * float(index % 3)), 6, 4, center)
	st.set_color(Color(0.95, 0.95, 0.95, 1.0))
	Geometry._add_uv_sphere(st, Vector3(0, 0.95 * 0.62, 0), 1.10 * 0.30, 7, 4, center)
	return st.commit()
