class_name WorldEditStorage
extends RefCounted
const Config = preload("res://scripts/map_config.gd")

static func save_path(references: Node) -> String:
	return Config.get_object_map_path(references.active_map_config)

static func save(references: Node, path: String = "", player: Node3D = null) -> Error:
	var saving_active_state := path.is_empty()
	var cfg: Dictionary = references.active_map_config
	if path.is_empty():
		if cfg.map_directory.begins_with("res://"):
			var directory = "user://maps/edit_%d" % Time.get_ticks_usec()
			var error = Config.copy_directory(cfg.map_directory, directory)
			if error != OK:
				return error
			cfg = cfg.duplicate(true)
			cfg.map_directory = directory
			if Config.save_document(cfg, directory) != OK:
				return ERR_CANT_CREATE
			references.active_map_config = cfg
		path = Config.get_object_map_path(cfg)
	var snapshot := _current_snapshot(references, player)
	var error := Config.write_json(path, snapshot)
	if error == OK and snapshot.has("player_spawn"):
		references.set_meta("saved_player_spawn", snapshot.player_spawn.duplicate(true))
	if error == OK and saving_active_state and references.has_method("mark_placements_saved"):
		references.mark_placements_saved()
	return error

static func player_spawn_matches_current(references: Node, player: Node3D) -> bool:
	var path := Config.get_object_map_path(references.active_map_config)
	var existing: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not existing is Dictionary:
		return false
	if not player:
		return not existing.has("player_spawn")
	return _values_equal(existing.get("player_spawn", {}), _player_spawn_record(player))

static func _values_equal(left: Variant, right: Variant) -> bool:
	if left is Dictionary or right is Dictionary:
		if not left is Dictionary or not right is Dictionary or left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _values_equal(left[key], right[key]):
				return false
		return true
	if left is Array or right is Array:
		if not left is Array or not right is Array or left.size() != right.size():
			return false
		for index in left.size():
			if not _values_equal(left[index], right[index]):
				return false
		return true
	if (left is float or left is int) and (right is float or right is int):
		# Reconstructed Godot transforms can drift slightly after a map reload.
		return absf(float(left) - float(right)) <= 0.01
	return left == right

static func _current_snapshot(references: Node, player: Node3D) -> Dictionary:
	var existing: Variant = JSON.parse_string(FileAccess.get_file_as_string(Config.get_object_map_path(references.active_map_config)))
	var snapshot: Dictionary = existing.duplicate(true) if existing is Dictionary else {}
	var objects: Array = references.get_all_placement_records() if references.has_method("get_all_placement_records") else []
	if not references.has_method("get_all_placement_records"):
		for object in references.get_children():
			if not object is SurfaceLightObject or object.is_queued_for_deletion():
				continue
			var packed: Array = []
			for vector in [object.transform.basis.x, object.transform.basis.y, object.transform.basis.z, object.transform.origin]:
				packed.append_array([vector.x, vector.y, vector.z])
			var record := {"id": object.instance_id, "asset": object.asset_id, "name": str(object.name), "transform": packed, "tint": Config.rgba(object.tint), "light_color": Config.rgba(object.light_color), "light_energy": object.light_energy, "light_range_m": object.light_range, "flicker": object.enable_flicker}
			if object.windmill_simulation != null:
				record["simulation_state"] = object.windmill_simulation.get_persistent_state()
			objects.append(record)
	snapshot["objects"] = objects
	if player:
		snapshot["player_spawn"] = _player_spawn_record(player)
	return snapshot

static func _player_spawn_record(player: Node3D) -> Dictionary:
	var position = player.global_position
	var basis = player.global_basis.orthonormalized()
	return {"position": [position.x, position.y, position.z], "basis": [basis.x.x,basis.x.y,basis.x.z,basis.y.x,basis.y.y,basis.y.z,basis.z.x,basis.z.y,basis.z.z], "pitch": player.pitch, "is_flying": player.is_flying}

static func restore(references: Node, path: String = "") -> bool:
	var restore_objects = not path.is_empty()
	if path.is_empty():
		path = save_path(references)
	var snapshot: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not snapshot is Dictionary:
		return false
	if restore_objects:
		for record in snapshot.get("objects", []):
			if not references.active_map_config.objects.model_catalog.has(record.get("asset")):
				return false
		if references.has_method("replace_placement_records"):
			if not references.replace_placement_records(snapshot.get("objects", [])):
				return false
			var streamed_spawn: Variant = snapshot.get("player_spawn", {})
			references.set_meta("saved_player_spawn", streamed_spawn if _valid_player_spawn(streamed_spawn) else {})
			return true
		for child in references.get_children():
			if child is SurfaceLightObject:
				references.remove_child(child)
				child.queue_free()
		for record in snapshot.get("objects", []):
			references.add_child(preload("res://scripts/map_object_factory.gd").create(references.active_map_config, record))
	var saved_spawn: Variant = snapshot.get("player_spawn", {})
	if snapshot.has("player_spawn") and not _valid_player_spawn(saved_spawn):
		push_warning("Ignoring invalid saved player spawn in map placements: " + path)
		saved_spawn = {}
	elif not snapshot.has("player_spawn"):
		saved_spawn = {}
	references.set_meta("saved_player_spawn", saved_spawn)
	return true

static func _valid_player_spawn(spawn: Variant) -> bool:
	if not spawn is Dictionary:
		return false
	var position: Variant = spawn.get("position", [])
	var packed_basis: Variant = spawn.get("basis", [])
	if not position is Array or position.size() != 3 or not packed_basis is Array or packed_basis.size() != 9:
		return false
	if not spawn.get("is_flying") is bool or not Config.finite_number(spawn.get("pitch")):
		return false
	for number in position + packed_basis + [spawn.pitch]:
		if not Config.finite_number(number):
			return false
	var basis := Basis(Vector3(packed_basis[0], packed_basis[1], packed_basis[2]), Vector3(packed_basis[3], packed_basis[4], packed_basis[5]), Vector3(packed_basis[6], packed_basis[7], packed_basis[8]))
	return absf(basis.determinant() - 1.0) < 0.01 and absf(float(spawn.pitch)) <= deg_to_rad(85.0)
