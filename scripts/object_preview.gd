class_name ObjectPreview
extends SubViewportContainer

const AssetLoader = preload("res://scripts/map_asset_loader.gd")
var viewport: SubViewport
var model_root: Node3D
var camera: Camera3D
var mesh_count := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	viewport = SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	model_root = Node3D.new()
	viewport.add_child(model_root)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	viewport.add_child(camera)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 1.1
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	viewport.add_child(light)
	resized.connect(func(): refresh.call_deferred())

func show_model(path: String, tint: Color = Color.WHITE) -> void:
	for child in model_root.get_children():
		child.free()
	mesh_count = 0
	var source := AssetLoader.instantiate_model(path)
	if not source:
		return
	# Copy only meshes: previews never run object scripts, particles, physics,
	# or join the real world's local-light selection group.
	_copy_meshes(source, Transform3D.IDENTITY, tint)
	source.free()
	if mesh_count == 0:
		return
	var bounds: AABB
	var first := true
	for child in model_root.get_children():
		var box: AABB = child.transform * child.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var diameter := maxf(bounds.size.length(), 0.1)
	camera.position = bounds.get_center() + Vector3(1, 0.65, -1).normalized() * diameter * 2.0
	camera.look_at(bounds.get_center(), Vector3.UP)
	camera.size = diameter * 1.2
	camera.near = 0.01
	camera.far = diameter * 5.0
	refresh()

func refresh() -> void:
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _copy_meshes(node: Node, parent_transform: Transform3D, tint: Color) -> void:
	var transform := parent_transform
	if node is Node3D:
		transform *= node.transform
	if node is MeshInstance3D and node.visible:
		var source_mesh: Mesh = node.mesh
		if not source_mesh and node.has_method("build_mesh"):
			source_mesh = node.call("build_mesh", 0) as Mesh
		if not source_mesh:
			for child in node.get_children():
				_copy_meshes(child, transform, tint)
			return
		var copy := MeshInstance3D.new()
		copy.mesh = source_mesh
		copy.transform = transform
		copy.material_override = _tint_material(node.material_override, tint)
		for surface in range(source_mesh.get_surface_count()):
			var source_material: Material = node.get_active_material(surface)
			if source_material != node.material_override:
				copy.set_surface_override_material(surface, _tint_material(source_material, tint))
		model_root.add_child(copy)
		mesh_count += 1
	for child in node.get_children():
		_copy_meshes(child, transform, tint)

func _tint_material(source: Material, tint: Color) -> Material:
	if not source or tint.is_equal_approx(Color.WHITE):
		return source
	if source is BaseMaterial3D:
		var tinted := source.duplicate() as BaseMaterial3D
		tinted.albedo_color *= tint
		return tinted
	if source is ShaderMaterial:
		var tinted_shader := source.duplicate() as ShaderMaterial
		var albedo: Variant = tinted_shader.get_shader_parameter("albedo_color")
		if albedo is Color:
			tinted_shader.set_shader_parameter("albedo_color", albedo * tint)
		return tinted_shader
	return source
