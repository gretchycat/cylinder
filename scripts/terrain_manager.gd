class_name TerrainManager
extends RefCounted

const MapAssetLoaderClass = preload("res://scripts/map_asset_loader.gd")

# Dimensions are owned by each layer. grid_u/v are elevation aliases only.
var grid_u: int = 0
var grid_v: int = 0
var elevation_grid_u: int = 0
var elevation_grid_v: int = 0
var terrain_grid_u: int = 0
var terrain_grid_v: int = 0
var elevation_variance: float
var water_level: float
var elevation_data := PackedFloat32Array()
var terrain_data := PackedByteArray()
var elevation_dirty := false
var terrain_dirty := false
var biomes: Dictionary = {}
var biome_by_id: Dictionary = {}
var last_error: String = ""
static var last_read_error: String = ""
var _rust_data: Object = null

func _init(_u: int = 0, _v: int = 0, variance: float = 1.0, sea: float = 0.0) -> void:
	elevation_variance = variance
	water_level = sea
	_rust_data = _new_rust_data()

static func _new_rust_data() -> Object:
	if not ClassDB.class_exists("RustTerrainData"):
		return null
	return ClassDB.instantiate("RustTerrainData")

func configure(doc: Dictionary) -> void:
	elevation_variance = doc.geometry.elevation_variance_m
	water_level = doc.geometry.water_sea_level_m
	biomes = doc.biomes
	biome_by_id.clear()
	for key in biomes:
		biome_by_id[int(biomes[key].raster_id)] = key

func load_layers(elev_path: String, terrain_path: String) -> bool:
	last_error = ""
	if _rust_data == null:
		var old_terrain_data = terrain_data
		var old_terrain_u = terrain_grid_u
		var old_terrain_v = terrain_grid_v
		var old_terrain_dirty = terrain_dirty
		var old_elevation_data = elevation_data
		var old_elevation_u = elevation_grid_u
		var old_elevation_v = elevation_grid_v
		var old_elevation_dirty = elevation_dirty
		if not load_terrain(terrain_path):
			return false
		if not load_elevation(elev_path):
			terrain_data = old_terrain_data
			terrain_grid_u = old_terrain_u
			terrain_grid_v = old_terrain_v
			terrain_dirty = old_terrain_dirty
			elevation_data = old_elevation_data
			elevation_grid_u = old_elevation_u
			elevation_grid_v = old_elevation_v
			elevation_dirty = old_elevation_dirty
			grid_u = old_elevation_u
			grid_v = old_elevation_v
			return false
		last_error = ""
		return true
	# Decode into a temporary Rust-owned layer pair so a failed map load does not
	# replace the terrain currently in use.
	var staged: Object = _new_rust_data()
	var biome_bytes := FileAccess.get_file_as_bytes(terrain_path)
	if biome_bytes.is_empty() or not staged.call("load_biome_png_bytes", biome_bytes, _valid_biome_ids()):
		last_error = str(staged.call("error_message"))
		if last_error.is_empty():
			last_error = "Cannot read biome layer: " + terrain_path
		return false
	var elevation_bytes := FileAccess.get_file_as_bytes(elev_path)
	if elevation_bytes.is_empty() or not staged.call("load_elevation_bytes", elevation_bytes, elevation_variance):
		last_error = str(staged.call("error_message"))
		if last_error.is_empty():
			last_error = "Cannot read elevation layer: " + elev_path
		return false
	_rust_data = staged
	terrain_grid_u = _rust_data.call("biome_width")
	terrain_grid_v = _rust_data.call("biome_height")
	terrain_data = _rust_data.call("biome_samples")
	elevation_grid_u = _rust_data.call("elevation_width")
	elevation_grid_v = _rust_data.call("elevation_height")
	grid_u = elevation_grid_u
	grid_v = elevation_grid_v
	elevation_data = _rust_data.call("elevation_samples_m")
	terrain_dirty = false
	elevation_dirty = false
	last_error = ""
	return true

func _valid_biome_ids() -> PackedByteArray:
	var ids := PackedByteArray()
	for key in biomes:
		ids.append(int(biomes[key].raster_id))
	return ids

static func read_elevation(path: String) -> Image:
	var data: Object = _new_rust_data()
	if data == null:
		var parsed := _read_elevation_data(path)
		if not parsed.get("ok", false):
			last_read_error = str(parsed.get("error", "Invalid elevation layer: " + path))
			return null
		last_read_error = ""
		return Image.create_from_data(parsed.width, parsed.height, false, Image.FORMAT_RF, parsed.samples.to_byte_array())
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or not data.call("load_elevation_bytes", bytes, 1.0):
		last_read_error = str(data.call("error_message"))
		if last_read_error.is_empty():
			last_read_error = "Cannot read elevation layer: " + path
		return null
	last_read_error = ""
	return Image.create_from_data(data.call("elevation_width"), data.call("elevation_height"), false, Image.FORMAT_RF, data.call("elevation_samples_m").to_byte_array())

static func _read_elevation_data(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {"ok": false, "error": "Cannot open elevation layer: " + path}
	file.big_endian = false
	if file.get_length() < 12 or file.get_buffer(4).get_string_from_ascii() != "CYLH":
		return {"ok": false, "error": "Elevation layer must start with CYLH and contain its header: " + path}
	var width = file.get_32()
	var height = file.get_32()
	if width < 2 or height < 2 or width > 32768 or height > 32768 or width * height > 536870912:
		return {"ok": false, "error": "Elevation dimensions are invalid or exceed 536,870,912 samples: %s (%d x %d)" % [path, width, height]}
	if file.get_length() != 12 + width * height * 4:
		return {"ok": false, "error": "Elevation byte count does not match its dimensions: " + path}
	var samples := PackedFloat32Array()
	samples.resize(width * height)
	var index := 0
	while index < samples.size():
		var byte_count := mini(65536, (samples.size() - index) * 4)
		var chunk := file.get_buffer(byte_count)
		if chunk.size() != byte_count:
			return {"ok": false, "error": "Elevation data ended unexpectedly: " + path}
		for offset in range(0, byte_count, 4):
			var value: float = chunk.decode_float(offset)
			if not is_finite(value) or value < 0.0 or value > 1.0:
				return {"ok": false, "error": "Elevation samples must be finite normalized values from 0 to 1: " + path}
			samples[index] = value
			index += 1
	return {"ok": true, "width": width, "height": height, "samples": samples}

static func write_elevation(path: String, image: Image) -> Error:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return FileAccess.get_open_error()
	var copy = image.duplicate() as Image
	copy.convert(Image.FORMAT_RF)
	f.store_buffer("CYLH".to_ascii_buffer())
	f.store_32(copy.get_width())
	f.store_32(copy.get_height())
	f.store_buffer(copy.get_data())
	f.flush()
	return f.get_error()

func load_elevation(path: String) -> bool:
	if _rust_data == null:
		var parsed := _read_elevation_data(path)
		if not parsed.get("ok", false):
			last_error = str(parsed.get("error", "Invalid elevation layer: " + path))
			return false
		elevation_grid_u = parsed.width
		elevation_grid_v = parsed.height
		grid_u = elevation_grid_u
		grid_v = elevation_grid_v
		elevation_data = parsed.samples
		for i in elevation_data.size():
			elevation_data[i] *= elevation_variance
		elevation_dirty = false
		last_error = ""
		return true
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or not _rust_data.call("load_elevation_bytes", bytes, elevation_variance):
		last_error = str(_rust_data.call("error_message"))
		if last_error.is_empty():
			last_error = "Cannot read elevation layer: " + path
		return false
	elevation_grid_u = _rust_data.call("elevation_width")
	elevation_grid_v = _rust_data.call("elevation_height")
	grid_u = elevation_grid_u
	grid_v = elevation_grid_v
	elevation_data = _rust_data.call("elevation_samples_m")
	elevation_dirty = false
	last_error = ""
	return true


func load_terrain(path: String) -> bool:
	if _rust_data == null:
		var img = MapAssetLoaderClass.load_image(path, 536870912)
		if not img or img.get_width() < 2 or img.get_height() < 2 or img.get_width() * img.get_height() > 536870912:
			last_error = "Biome layer is missing, malformed, or exceeds 536,870,912 pixels: " + path
			return false
		img.convert(Image.FORMAT_L8)
		var data = img.get_data()
		for id in data:
			if not biome_by_id.has(id):
				last_error = "Biome layer contains an ID absent from map_config.json: %d (%s)" % [id, path]
				return false
		terrain_grid_u = img.get_width()
		terrain_grid_v = img.get_height()
		terrain_data = data
		terrain_dirty = false
		last_error = ""
		return true
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or not _rust_data.call("load_biome_png_bytes", bytes, _valid_biome_ids()):
		last_error = str(_rust_data.call("error_message"))
		if last_error.is_empty():
			last_error = "Cannot read biome layer: " + path
		return false
	terrain_grid_u = _rust_data.call("biome_width")
	terrain_grid_v = _rust_data.call("biome_height")
	terrain_data = _rust_data.call("biome_samples")
	terrain_dirty = false
	last_error = ""
	return true


func create_elevation_image() -> Image:
	var normalized = elevation_data.duplicate()
	for i in normalized.size():
		normalized[i] /= elevation_variance
	return Image.create_from_data(elevation_grid_u, elevation_grid_v, false, Image.FORMAT_RF, normalized.to_byte_array())

func create_terrain_image() -> Image:
	return Image.create_from_data(terrain_grid_u, terrain_grid_v, false, Image.FORMAT_L8, terrain_data)

func create_terrain_type_id_image() -> Image:
	return Image.create_from_data(terrain_grid_u, terrain_grid_v, false, Image.FORMAT_R8, terrain_data)

func save_elevation(path: String) -> bool:
	return write_elevation(path, create_elevation_image()) == OK

func save_terrain(path: String) -> bool:
	return create_terrain_image().save_png(path) == OK

static func sample_image(img: Image, u: float, v: float) -> float:
	var x = fposmod(u, 1.0) * img.get_width()
	var y = clampf(v, 0, 1) * (img.get_height() - 1)
	var x0 = int(floor(x)) % img.get_width()
	var x1 = (x0 + 1) % img.get_width()
	var y0 = int(floor(y))
	var y1 = mini(y0 + 1, img.get_height() - 1)
	return lerpf(lerpf(img.get_pixel(x0, y0).r, img.get_pixel(x1, y0).r, x - floor(x)), lerpf(img.get_pixel(x0, y1).r, img.get_pixel(x1, y1).r, x - floor(x)), y - floor(y))

func get_elevation(theta: float, z: float, length_m: float) -> float:
	if _rust_data != null and _rust_data.call("elevation_width") >= 2:
		return _rust_data.call("sample_elevation", theta, z, length_m)
	if elevation_data.is_empty():
		return 0
	var x = fposmod(theta, TAU) / TAU * elevation_grid_u
	var y = clampf(z / length_m + 0.5, 0, 1) * (elevation_grid_v - 1)
	var x0 = int(floor(x)) % elevation_grid_u
	var x1 = (x0 + 1) % elevation_grid_u
	var y0 = int(floor(y))
	var y1 = mini(y0 + 1, elevation_grid_v - 1)
	return lerpf(lerpf(elevation_data[y0 * elevation_grid_u + x0], elevation_data[y0 * elevation_grid_u + x1], x - floor(x)), lerpf(elevation_data[y1 * elevation_grid_u + x0], elevation_data[y1 * elevation_grid_u + x1], x - floor(x)), y - floor(y))

func get_biome_id(theta: float, z: float, length_m: float) -> int:
	if _rust_data != null and _rust_data.call("biome_width") >= 2:
		return _rust_data.call("sample_biome_id", theta, z, length_m)
	if terrain_data.is_empty():
		return -1
	var x = int(round(fposmod(theta, TAU) / TAU * terrain_grid_u)) % terrain_grid_u
	var y = clampi(int(round((z / length_m + 0.5) * (terrain_grid_v - 1))), 0, terrain_grid_v - 1)
	return terrain_data[y * terrain_grid_u + x]

func get_biome(theta: float, z: float, length_m: float) -> Dictionary:
	return biomes.get(biome_by_id.get(get_biome_id(theta, z, length_m), ""), {})

func get_terrain_type(theta: float, z: float, length_m: float) -> int:
	return get_biome_id(theta, z, length_m)
