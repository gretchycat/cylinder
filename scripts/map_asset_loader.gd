class_name MapAssetLoader
extends RefCounted

## Instantiate any imported Godot 3D scene, or wrap a directly imported Mesh
## (the default import mode for OBJ) in a MeshInstance3D.
static var model_cache: Dictionary = {}
static var solid_collision_cache: Dictionary = {}
static var collision_hulls_visible: bool = false
static var collision_debug_material: StandardMaterial3D = null
const MAX_TEXTURE_DIMENSION := 8192
const MAX_TEXTURE_PIXELS := 16777216

static func texture_dimensions_allowed(dimensions: Vector2i) -> bool:
	return dimensions.x > 0 and dimensions.y > 0 and dimensions.x <= MAX_TEXTURE_DIMENSION and dimensions.y <= MAX_TEXTURE_DIMENSION and dimensions.x * dimensions.y <= MAX_TEXTURE_PIXELS

static func instantiate_model(path: String) -> Node3D:
	if path.is_empty():
		return null
	if path.get_extension().to_lower() == "glb" and not path.begins_with("res://"):
		if model_cache.has(path):
			return model_cache[path].instantiate()
		var bytes = FileAccess.get_file_as_bytes(path)
		if bytes.size() < 20 or bytes.size() > 67108864 or bytes.decode_u32(0) != 0x46546c67:
			return null
		var json_length = bytes.decode_u32(12)
		if json_length + 20 > bytes.size():
			return null
		var document: Variant = JSON.parse_string(bytes.slice(20, 20 + json_length).get_string_from_utf8())
		if not document is Dictionary:
			return null
		for section in ["buffers", "images"]:
			for entry in document.get(section, []):
				if entry.has("uri") and not str(entry.uri).begins_with("data:"):
					return null # Require a self-contained model, no host dependencies.
		var gltf = GLTFDocument.new()
		var state = GLTFState.new()
		if gltf.append_from_buffer(bytes, "", state) != OK:
			return null
		var scene = gltf.generate_scene(state)
		if not scene:
			return null
		var packed = PackedScene.new()
		if packed.pack(scene) == OK:
			model_cache[path] = packed
		return scene
	var resource = ResourceLoader.load(path)
	if resource is PackedScene:
		var instance: Node = (resource as PackedScene).instantiate()
		if instance is Node3D:
			return instance
		var wrapper = Node3D.new()
		wrapper.add_child(instance)
		return wrapper
	if resource is Mesh:
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = resource
		return mesh_instance
	return null

## Builds and caches simplified convex collision shapes from an imported model.
## The cached shapes are resource-safe to share between instances; transforms
## remain per-instance because imported scene nodes may have different roots.
static func ensure_solid_collision(root: Node3D, cache_key: String, collision_config_path: String = "") -> void:
	if not root or cache_key.is_empty():
		return
	if root.find_child("SolidCollision", true, false) or root.find_child("SolidTreeCollision", true, false):
		return
	var categories: Dictionary = _load_collision_categories(collision_config_path)
	if not collision_config_path.is_empty() and categories.is_empty():
		return
	var entries: Array = solid_collision_cache.get(cache_key, [])
	if entries.is_empty():
		# The generated body is attached below root, so its entries must be
		# relative to root. Including root.transform here would apply the model
		# root's position/scale a second time.
		for child: Node in root.get_children():
			_collect_convex_collision_entries(child, Transform3D.IDENTITY, entries, categories)
		if entries.is_empty():
			return
		solid_collision_cache[cache_key] = entries
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "SolidCollision"
	root.add_child(body)
	for entry: Dictionary in entries:
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.shape = entry.shape
		collider.transform = entry.transform
		body.add_child(collider)
		_attach_collision_debug_mesh(collider)

static func set_collision_hulls_visible(tree: SceneTree, visible: bool) -> void:
	collision_hulls_visible = visible
	if not tree:
		return
	for node: Node in tree.get_nodes_in_group("collision_debug_hull"):
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).visible = visible

static func attach_existing_collision_debug_meshes(root: Node) -> void:
	if not root:
		return
	for node: Node in root.find_children("*", "CollisionShape3D", true, false):
		var collider := node as CollisionShape3D
		if collider and collider.shape and not collider.get_node_or_null("CollisionHullDebug"):
			_attach_collision_debug_mesh(collider)

static func _attach_collision_debug_mesh(collider: CollisionShape3D) -> void:
	if not collider or not collider.shape:
		return
	var debug_mesh: ArrayMesh = collider.shape.get_debug_mesh()
	if not debug_mesh:
		return
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "CollisionHullDebug"
	mesh_instance.mesh = debug_mesh
	mesh_instance.material_override = _get_collision_debug_material()
	mesh_instance.visible = collision_hulls_visible
	mesh_instance.add_to_group("collision_debug_hull")
	collider.add_child(mesh_instance)

static func _get_collision_debug_material() -> StandardMaterial3D:
	if collision_debug_material:
		return collision_debug_material
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.0, 1.0, 0.5)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	collision_debug_material = material
	return collision_debug_material

static func _load_collision_categories(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not document is Dictionary or not document.get("categories", {}) is Dictionary:
		return {}
	return document.categories as Dictionary

static func _collect_convex_collision_entries(node: Node, parent_transform: Transform3D, output: Array, categories: Dictionary = {}) -> void:
	if node.is_in_group("collision_debug_hull") or node is CollisionShape3D:
		return
	var local_transform: Transform3D = parent_transform
	if node is Node3D:
		local_transform *= (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh:
			for surface_index: int in mesh.get_surface_count():
				if not categories.is_empty() and not _surface_matches_collision_categories(node, mesh, surface_index, categories):
					continue
				var arrays: Array = mesh.surface_get_arrays(surface_index)
				if arrays.size() <= Mesh.ARRAY_VERTEX:
					continue
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				if vertices.size() < 4:
					continue
				var shape := ConvexPolygonShape3D.new()
				shape.points = vertices
				output.append({"shape": shape, "transform": local_transform})
	for child: Node in node.get_children():
		_collect_convex_collision_entries(child, local_transform, output, categories)

static func _surface_matches_collision_categories(node: Node, mesh: Mesh, surface_index: int, categories: Dictionary) -> bool:
	var material: Material = mesh.surface_get_material(surface_index)
	var names: PackedStringArray = [node.name.to_lower()]
	if material:
		names.append(material.resource_name.to_lower())
	var category_tokens: Dictionary = {
		"roots": ["root", "roots"],
		"trunk": ["trunk", "bark", "stem", "wood"],
		"main_branches": ["main_branch", "main branch", "branch", "limb"]
	}
	for category: String in category_tokens:
		var configured: Variant = categories.get(category, false)
		if configured is Array:
			if (configured as Array).is_empty():
				continue
		else:
			if not bool(configured):
				continue
		var tokens: Array[String] = []
		if configured is Array:
			for configured_token: Variant in configured as Array:
				tokens.append(str(configured_token).to_lower())
		else:
			for default_token: String in category_tokens[category]:
				tokens.append(default_token)
		if tokens.is_empty():
			continue
		for name: String in names:
			if category == "trunk" and (name.contains("leaf") or name.contains("foliage")):
				continue
			if category == "trunk" and name.begins_with("island_tree"):
				return true
			for token: String in tokens:
				if name.contains(token):
					return true
	return false

static func solid_collision_cache_size() -> int:
	return solid_collision_cache.size()

## Load a texture through Godot's importer first, then decode a project/user
## image directly when the resource is not imported (for example user://).
static func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var resource = ResourceLoader.load(path)
		if resource is Texture2D:
			return resource
	var image = load_image(path)
	if image and not image.is_empty():
		return ImageTexture.create_from_image(image)
	return null

## Image.load_from_file detects the supported raster/vector encoding from file
## contents, allowing maps to use any image format enabled in this Godot build.
static func _image_dimensions(path: String) -> Vector2i:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return Vector2i.ZERO
	var ext = path.get_extension().to_lower()
	if ext == "png":
		var header = file.get_buffer(24)
		if header.size() < 24 or header.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]) or header.slice(12, 16).get_string_from_ascii() != "IHDR":
			return Vector2i(-1, -1)
		var w = (header[16] << 24) | (header[17] << 16) | (header[18] << 8) | header[19]
		var h = (header[20] << 24) | (header[21] << 16) | (header[22] << 8) | header[23]
		return Vector2i(w, h)
	if ext in ["jpg", "jpeg"]:
		var file_length = file.get_length()
		if file_length < 4 or file.get_buffer(2) != PackedByteArray([255, 216]):
			return Vector2i(-1, -1)
		file.big_endian = true
		var position = 2
		while position + 4 < file_length and position < 1048576:
			file.seek(position)
			if file.get_8() != 255:
				return Vector2i(-1, -1)
			var marker = file.get_8()
			while marker == 255:
				marker = file.get_8()
			if marker in [0xD8, 0xD9, 0x01] or marker in range(0xD0, 0xD8):
				position = file.get_position()
				continue
			var segment_length = file.get_16()
			if segment_length < 2 or position + 2 + segment_length > file_length:
				return Vector2i(-1, -1)
			if marker in [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]:
				if segment_length < 7:
					return Vector2i(-1, -1)
				var height = file.get_16()
				var width = file.get_16()
				return Vector2i(width, height)
			position += 2 + segment_length
		return Vector2i(-1, -1)
	if ext == "webp":
		var header = file.get_buffer(30)
		if header.size() < 25 or header.slice(0, 4).get_string_from_ascii() != "RIFF" or header.slice(8, 12).get_string_from_ascii() != "WEBP":
			return Vector2i(-1, -1)
		var chunk = header.slice(12, 16).get_string_from_ascii()
		if chunk == "VP8X" and header.size() >= 30:
			var w = 1 + header[24] + (header[25] << 8) + (header[26] << 16)
			var h = 1 + header[27] + (header[28] << 8) + (header[29] << 16)
			return Vector2i(w, h)
		if chunk == "VP8L" and header[20] == 0x2f:
			var w = 1 + header[21] + ((header[22] & 0x3f) << 8)
			var h = 1 + (header[22] >> 6) + (header[23] << 2) + ((header[24] & 0x0f) << 10)
			return Vector2i(w, h)
		if chunk == "VP8 " and header.size() >= 30 and header.slice(23, 26) == PackedByteArray([157, 1, 42]):
			return Vector2i((header[26] | (header[27] << 8)) & 0x3fff, (header[28] | (header[29] << 8)) & 0x3fff)
		return Vector2i(-1, -1)
	return Vector2i.ZERO

static func load_image(path: String, max_pixels: int = MAX_TEXTURE_PIXELS) -> Image:
	if path.is_empty():
		return null
	if FileAccess.file_exists(path):
		var dimensions = _image_dimensions(path)
		if not texture_dimensions_allowed(dimensions):
			return null
		if max_pixels > 0 and dimensions.x * dimensions.y > max_pixels:
			return null
		var file = FileAccess.open(path, FileAccess.READ)
		if not file or file.get_length() > 134217728:
			return null
		var bytes = file.get_buffer(file.get_length())
		var image = Image.new()
		var error = ERR_FILE_UNRECOGNIZED
		match path.get_extension().to_lower():
			"png": error = image.load_png_from_buffer(bytes)
			"jpg", "jpeg": error = image.load_jpg_from_buffer(bytes)
			"webp": error = image.load_webp_from_buffer(bytes)
		if error == OK:
			return image
	if ResourceLoader.exists(path):
		var resource = ResourceLoader.load(path)
		if resource is Texture2D:
			if not texture_dimensions_allowed(Vector2i(resource.get_width(), resource.get_height())) or (max_pixels > 0 and resource.get_width() * resource.get_height() > max_pixels):
				return null
			return resource.get_image()
	return null
