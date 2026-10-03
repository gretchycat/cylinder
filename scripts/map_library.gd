class_name MapLibrary
extends RefCounted

const Config = preload("res://scripts/map_config.gd")
const MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
const MAX_FILES = 4096

static func validate_package(directory: String) -> String:
	var doc = Config.load_map_config(directory)
	if doc.is_empty():
		return Config.last_error
	# User models are data-only GLBs. Never load scripts or scenes from an archive.
	for catalog in [doc.objects.model_catalog, doc.ground_clutter.models]:
		for entry in catalog.values():
			if not entry.scene_path.begins_with("res://") and entry.scene_path.get_extension().to_lower() != "glb":
				return "Imported models must be self-contained GLB files"
	var error = Config.validate_assets(doc)
	if not error.is_empty():
		return error
	var checked = {}
	for catalog in [doc.objects.model_catalog, doc.ground_clutter.models]:
		for entry in catalog.values():
			var path: String = Config.resolve_map_asset_path(doc, entry.scene_path)
			if path.begins_with("res://") or checked.has(path):
				continue
			checked[path] = true
			var model = preload("res://scripts/map_asset_loader.gd").instantiate_model(path)
			if model == null:
				return "Invalid self-contained model: " + str(entry.scene_path)
			model.free()
	var terrain = preload("res://scripts/terrain_manager.gd").new()
	terrain.configure(doc)
	if not terrain.load_layers(Config.get_elevation_map_path(doc), Config.get_terrain_map_path(doc)):
		return terrain.last_error
	return ""

static func export_map(directory: String, path: String) -> Error:
	Config.last_error = validate_package(directory)
	if not Config.last_error.is_empty():
		return ERR_INVALID_DATA
	var zip = ZIPPacker.new()
	var error = zip.open(path)
	if error != OK:
		return Config.copy_failure("create map archive", path, error)
	error = _pack_tree(zip, directory, "")
	var close_error = zip.close()
	if error == OK:
		error = close_error
	if error != OK:
		return Config.copy_failure("write map archive", path, error)
	return OK

static func _pack_tree(zip: ZIPPacker, directory: String, prefix: String) -> Error:
	var dir = DirAccess.open(directory)
	if not dir:
		return ERR_CANT_OPEN
	for file in dir.get_files():
		if file.begins_with(".") or file.ends_with(".tmp") or file.ends_with(".import"):
			continue
		var input = FileAccess.open(directory.path_join(file), FileAccess.READ)
		if not input:
			return FileAccess.get_open_error()
		var error = zip.start_file(prefix + file)
		if error != OK:
			return error
		error = zip.write_file(input.get_buffer(input.get_length()))
		if error != OK:
			return error
		error = zip.close_file()
		if error != OK:
			return error
	for child in dir.get_directories():
		var error = _pack_tree(zip, directory.path_join(child), prefix + child + "/")
		if error != OK:
			return error
	return OK

## Inspect ZIP directory sizes before ZIPReader allocates decompressed entries.
## Map archives use ordinary single-disk ZIP; ZIP64 and encryption are rejected.
static func _archive_bounds(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return "Cannot open map archive"
	var length = file.get_length()
	if length < 22 or length > MAX_ARCHIVE_BYTES:
		return "Invalid map archive size (maximum 512 MiB)"
	file.seek(maxi(0, length - 65557))
	var tail = file.get_buffer(mini(length, 65557))
	var end = -1
	for i in range(tail.size() - 22, -1, -1):
		if tail.decode_u32(i) == 0x06054b50 and i + 22 + tail.decode_u16(i + 20) == tail.size():
			end = i
			break
	if end < 0:
		return "Invalid ZIP directory"
	var count = tail.decode_u16(end + 10)
	var offset = tail.decode_u32(end + 16)
	if tail.decode_u16(end + 4) != 0 or tail.decode_u16(end + 6) != 0 or count != tail.decode_u16(end + 8) or count > MAX_FILES or offset == 0xffffffff:
		return "Unsupported ZIP archive (single disk, at most 4096 files)"
	file.seek(offset)
	var total = 0
	for i in count:
		var header = file.get_buffer(46)
		if header.size() != 46 or header.decode_u32(0) != 0x02014b50:
			return "Invalid ZIP entry"
		if header.decode_u16(8) & 1:
			return "Encrypted map archives are not supported"
		total += header.decode_u32(24)
		if total > MAX_ARCHIVE_BYTES:
			return "Map archive exceeds 512 MiB when unpacked"
		file.seek(file.get_position() + header.decode_u16(28) + header.decode_u16(30) + header.decode_u16(32))
	return ""

static func import_map(path: String) -> String:
	Config.last_error = _archive_bounds(path)
	if not Config.last_error.is_empty():
		return ""
	var zip = ZIPReader.new()
	var error = zip.open(path)
	if error != OK:
		Config.copy_failure("open map archive", path, error)
		return ""
	var files = zip.get_files()
	if files.size() > MAX_FILES or not "map_config.json" in files:
		Config.last_error = "Archive must contain map_config.json at its root (maximum 4096 files)"
		zip.close()
		return ""
	var seen = {}
	for file in files:
		if not Config.relative_path(file.trim_suffix("/")) or file.trim_suffix("/").simplify_path() != file.trim_suffix("/") or file.to_lower() in seen:
			Config.last_error = "Invalid or duplicate archive path: " + file
			zip.close()
			return ""
		if file == ".map_ready":
			Config.last_error = "Archive cannot contain internal library markers"
			zip.close()
			return ""
		seen[file.to_lower()] = true
		if file.get_extension().to_lower() in ["gd", "gdc", "cs", "tscn", "scn", "tres", "res", "gdextension"]:
			Config.last_error = "Map archives cannot contain scripts or Godot scene resources"
			zip.close()
			return ""
	var directory = Config.new_user_directory("import")
	var total = 0
	for file in files:
		if file.ends_with("/"):
			continue
		var bytes = zip.read_file(file)
		total += bytes.size()
		if total > MAX_ARCHIVE_BYTES:
			Config.last_error = "Map archive exceeds 512 MiB"
			break
		error = DirAccess.make_dir_recursive_absolute(directory.path_join(file).get_base_dir())
		if error != OK:
			Config.copy_failure("create import directory", directory, error)
			break
		var output = FileAccess.open(directory.path_join(file), FileAccess.WRITE)
		if not output:
			Config.copy_failure("extract map file", file, FileAccess.get_open_error())
			break
		output.store_buffer(bytes)
		output.flush()
		error = output.get_error()
		output.close()
		if error != OK:
			Config.copy_failure("extract map file", file, error)
			break
	zip.close()
	if Config.last_error.is_empty():
		Config.last_error = validate_package(directory)
	if not Config.last_error.is_empty():
		# An incomplete import must never appear in the map picker.
		DirAccess.remove_absolute(directory.path_join("map_config.json"))
		return ""
	var doc = Config.load_map_config(directory)
	doc.world_id = Config.new_map_id()
	doc.erase("template_revision")
	if Config.save_document(doc, directory) != OK or Config.publish_map(directory) != OK:
		return ""
	return directory
