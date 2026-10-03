class_name MapAssetLoader
extends RefCounted

## Instantiate any imported Godot 3D scene, or wrap a directly imported Mesh
## (the default import mode for OBJ) in a MeshInstance3D.
static var model_cache: Dictionary = {}
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
	if ResourceLoader.exists(path):
		var resource = ResourceLoader.load(path)
		if resource is Texture2D:
			if not texture_dimensions_allowed(Vector2i(resource.get_width(), resource.get_height())) or (max_pixels > 0 and resource.get_width() * resource.get_height() > max_pixels):
				return null
			return resource.get_image()
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
	return null
