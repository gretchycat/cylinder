class_name WorldEditStorage
extends RefCounted

static func save_path(references: Node) -> String:
	var map_key := str(references.active_map_config.get("map_directory", "default"))
	return "user://world_edits_%s.json" % map_key.sha256_text().left(16)

static func save(references: Node, path: String = "", player: Node3D = null) -> Error:
	if path.is_empty():
		path = save_path(references)
	var objects: Array[Dictionary] = []
	for object in references.get_children():
		if not object is SurfaceLightObject or object.is_queued_for_deletion():
			continue
		var transform: Transform3D = object.transform
		var packed_transform: Array[float] = []
		for vector in [transform.basis.x, transform.basis.y, transform.basis.z, transform.origin]:
			packed_transform.append_array([vector.x, vector.y, vector.z])
		objects.append({
			"type": int(object.object_type), "variant": int(object.tree_variant),
			"model": object.model_scene_path, "name": str(object.name),
			"transform": packed_transform,
			"color": [object.light_color.r, object.light_color.g, object.light_color.b],
			"energy": object.light_energy, "range": object.light_range,
			"flicker": object.enable_flicker,
		})
	var snapshot := {"version": 1, "objects": objects}
	if player:
		var position := player.global_position
		var basis := player.global_basis.orthonormalized()
		snapshot["player_spawn"] = {
			"position": [position.x, position.y, position.z],
			"basis": [basis.x.x, basis.x.y, basis.x.z, basis.y.x, basis.y.y, basis.y.z, basis.z.x, basis.z.y, basis.z.z],
			"pitch": player.pitch, "is_flying": player.is_flying,
		}
	elif references.has_meta("saved_player_spawn"):
		snapshot["player_spawn"] = references.get_meta("saved_player_spawn")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error == OK and snapshot.has("player_spawn"):
		# Reset to Default Spawn should use the newly saved location immediately.
		references.set_meta("saved_player_spawn", snapshot.player_spawn.duplicate(true))
	return error

static func restore(references: Node, path: String = "") -> bool:
	if path.is_empty():
		path = save_path(references)
	if not FileAccess.file_exists(path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("version") != 1 or not data.get("objects") is Array:
		push_warning("Saved world edits are invalid; keeping the map's original objects.")
		return false
	# Validate the complete snapshot before replacing any live objects.
	for entry in data.objects:
		if not _valid_entry(entry):
			push_warning("Saved world edits contain an invalid object; keeping original objects.")
			return false
	# Optional field keeps older object-only saves compatible. ReferenceObjects
	# loads before Player._ready(), which reads this default when spawning.
	var spawn: Variant = data.get("player_spawn", {})
	references.set_meta("saved_player_spawn", spawn if _valid_player_spawn(spawn) else {})
	for child in references.get_children():
		if child is SurfaceLightObject:
			references.remove_child(child)
			child.queue_free()
	for entry in data.objects:
		var object := SurfaceLightObject.new()
		object.object_type = int(entry.type) as SurfaceLightObject.ObjectType
		object.tree_variant = int(entry.variant) as SurfaceLightObject.TreeVariant
		object.model_scene_path = str(entry.model)
		object.name = str(entry.name)
		var t: Array = entry.transform
		object.transform = Transform3D(Basis(Vector3(t[0], t[1], t[2]), Vector3(t[3], t[4], t[5]), Vector3(t[6], t[7], t[8])), Vector3(t[9], t[10], t[11]))
		object.light_color = Color(entry.color[0], entry.color[1], entry.color[2])
		object.light_energy = float(entry.energy)
		object.light_range = float(entry.range)
		object.enable_flicker = bool(entry.flicker)
		references.add_child(object)
	return true

static func _valid_entry(entry: Variant) -> bool:
	if not entry is Dictionary:
		return false
	for key in ["type", "variant", "model", "name", "transform", "color", "energy", "range", "flicker"]:
		if not entry.has(key):
			return false
	if not entry.type is float and not entry.type is int:
		return false
	if int(entry.type) < 0 or int(entry.type) >= SurfaceLightObject.ObjectType.size():
		return false
	if not entry.transform is Array or entry.transform.size() != 12 or not entry.color is Array or entry.color.size() != 3:
		return false
	for number in entry.transform + entry.color + [entry.energy, entry.range, entry.variant]:
		if (not number is float and not number is int) or not is_finite(float(number)):
			return false
	if not entry.model is String or not entry.name is String or not entry.flicker is bool:
		return false
	return entry.model.is_empty() or ResourceLoader.exists(entry.model)

static func _valid_player_spawn(spawn: Variant) -> bool:
	if not spawn is Dictionary:
		return false
	if not spawn.get("position") is Array or spawn.position.size() != 3:
		return false
	if not spawn.get("basis") is Array or spawn.basis.size() != 9:
		return false
	if not spawn.get("is_flying") is bool:
		return false
	for value in spawn.position + spawn.basis + [spawn.get("pitch")]:
		if (not value is float and not value is int) or not is_finite(float(value)):
			return false
	var b: Array = spawn.basis
	var basis := Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8]))
	return absf(basis.determinant() - 1.0) < 0.01 and absf(float(spawn.pitch)) <= deg_to_rad(85.0)
