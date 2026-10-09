@tool
class_name ReferenceObjects
extends Node3D

@export_category("Cylinder Dimensions (8 km dia x 18 km length)")
var cylinder_radius: float = 0
var cylinder_length: float = 0
var object_map_path: String = ""

const DebugConsole = preload("res://scripts/debug_console.gd")
const MapConfigClass = preload("res://scripts/map_config.gd")
const EditStorage = preload("res://scripts/world_edit_storage.gd")

var active_map_config: Dictionary = {}
var surface_light_selection_timer: float = 0.0
var placement_records: Array = []
var live_placements: Dictionary = {}
var placement_stream_timer: float = 0.0
var placement_stream_center := Vector2.ZERO
var has_placement_stream_center := false

# Generated maps can contain thousands of placements. Keep the map data intact,
# but instantiate only nearby objects so loading a map does not allocate every
# imported model and light at once (particularly important on Android).
const PLACEMENT_STREAM_RADIUS_M := 850.0
const PLACEMENT_RETENTION_RADIUS_M := 1250.0
const MAX_LIVE_PLACEMENTS := 256
const PLACEMENTS_PER_TICK := 24
const PLACEMENT_STREAM_INTERVAL := 0.1

const MOBILE_LOCAL_LIGHT_BUDGET: int = 6
const FORWARD_LIGHT_LOOKAHEAD_MULTIPLIER: float = 8.0

func _ready() -> void:
	add_to_group("reference_objects")
	active_map_config = MapConfigClass.load_map_config(MapConfigClass.active_map())
	# Ensure DebugConsole exists in the scene
	if not get_node_or_null("DebugConsole"):
		var console_node = DebugConsole.new()
		add_child(console_node)
	# Avoid spawning duplicate objects when running in tool mode repeatedly
	for child in get_children():
		# Keep the mobile console alive. This child was just created above and
		# used to be queued for deletion along with regenerated marker objects.
		if child is CanvasLayer and child.name == "DebugConsole":
			continue
		child.queue_free()

	spawn_all_markers()
	EditStorage.restore(self)

func _process(delta: float) -> void:
	placement_stream_timer += delta
	if placement_stream_timer >= PLACEMENT_STREAM_INTERVAL:
		placement_stream_timer = 0.0
		_update_placement_streaming()
	surface_light_selection_timer += delta
	if surface_light_selection_timer < 0.25:
		return
	surface_light_selection_timer = 0.0
	_update_nearest_surface_lights()

func _update_nearest_surface_lights() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var listener_position: Vector3
	if player:
		listener_position = player.global_position
	else:
		var viewport = get_viewport()
		var camera = viewport.get_camera_3d() if viewport else null
		if not camera:
			return
		listener_position = camera.global_position
	if not is_inside_tree():
		return

	var objects: Array[SurfaceLightObject] = []
	var forward_candidates: Array[Dictionary] = []
	var behind_candidates: Array[Dictionary] = []
	var max_distance = SurfaceLightObject.get_effective_active_light_distance()
	var player_forward = (player.global_basis * Vector3.FORWARD).normalized() if player else Vector3.ZERO
	for node in get_tree().get_nodes_in_group("surface_light_objects"):
		if not node is SurfaceLightObject:
			continue
		var light_object := node as SurfaceLightObject
		objects.append(light_object)
		light_object.is_near_camera = false
		var object_lights: Array[OmniLight3D] = []
		if light_object.omni_light:
			object_lights.append(light_object.omni_light)
		for light in object_lights:
			if not is_instance_valid(light):
				continue
			var offset_to_light = light.global_position - listener_position
			var distance_sq = offset_to_light.length_squared()
			var within_user_range = max_distance > 0.0 and distance_sq <= max_distance * max_distance
			var is_in_front = not player or distance_sq < 0.001 or player_forward.dot(offset_to_light.normalized()) > 0.0
			var activation_range = light.omni_range * FORWARD_LIGHT_LOOKAHEAD_MULTIPLIER if is_in_front else light.omni_range
			if not within_user_range or distance_sq > activation_range * activation_range:
				light.visible = false
				continue
			var candidate = {"light": light, "owner": light_object, "distance_sq": distance_sq}
			if is_in_front:
				forward_candidates.append(candidate)
			else:
				behind_candidates.append(candidate)

	var by_distance = func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance_sq"]) < float(b["distance_sq"])
	forward_candidates.sort_custom(by_distance)
	behind_candidates.sort_custom(by_distance)

	var selected_lights: Array[Dictionary] = []
	if ProjectSettings.get_setting("rendering/renderer/rendering_method", "mobile") == "mobile":
		for candidate in forward_candidates:
			if selected_lights.size() >= MOBILE_LOCAL_LIGHT_BUDGET:
				break
			selected_lights.append(candidate)
		for candidate in behind_candidates:
			if selected_lights.size() >= MOBILE_LOCAL_LIGHT_BUDGET:
				break
			selected_lights.append(candidate)
	else:
		selected_lights.append_array(forward_candidates)
		selected_lights.append_array(behind_candidates)

	for candidate in selected_lights:
		var light := candidate["light"] as OmniLight3D
		var light_object := candidate["owner"] as SurfaceLightObject
		light_object.set_surface_light_active(light, true)
	for candidate in forward_candidates + behind_candidates:
		var light := candidate["light"] as OmniLight3D
		if not light.visible:
			continue
		var is_selected := false
		for selected in selected_lights:
			if selected["light"] == light:
				is_selected = true
				break
		if not is_selected:
			light.visible = false

	# Ensure sources outside their own range or the nearest-light budget stay off.
	for light_object in objects:
		if not light_object.is_near_camera:
			if light_object.omni_light:
				light_object.omni_light.visible = false

func _get_terrain_elevation(theta: float, z: float) -> float:
	var cyl_world = get_parent().get_node_or_null("CylinderWorld") if get_parent() else null
	if not cyl_world:
		cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null
	if cyl_world and cyl_world.has_method("get_elevation_at"):
		return cyl_world.get_elevation_at(theta, z)
	return 0.0

func _get_model_path(type: SurfaceLightObject.ObjectType, tree_variant_idx: int = -1) -> String:
	return MapConfigClass.get_object_model_path(active_map_config, int(type), tree_variant_idx)

const STREAM_CHUNK_SIZE_M := 500.0
var spatial_chunks: Dictionary = {} # Vector2i(cx, cz) -> Array[Dictionary]

func _pos_to_spatial_chunk_key(surf_pos: Vector2) -> Vector2i:
	var r := maxf(cylinder_radius, 1.0)
	var l := maxf(cylinder_length, 1.0)
	var u := fposmod(surf_pos.x + PI, TAU) * r
	var z_m := surf_pos.y + l * 0.5
	var cx := int(floor(u / STREAM_CHUNK_SIZE_M))
	var cz := int(floor(z_m / STREAM_CHUNK_SIZE_M))
	return Vector2i(cx, cz)

func _rebuild_spatial_chunks() -> void:
	spatial_chunks.clear()
	var r := maxf(cylinder_radius, 1.0)
	var l := maxf(cylinder_length, 1.0)
	var num_chunks_x := int(ceil((TAU * r) / STREAM_CHUNK_SIZE_M))
	var num_chunks_z := int(ceil(l / STREAM_CHUNK_SIZE_M))

	for record_variant in placement_records:
		if not record_variant is Dictionary:
			continue
		var record: Dictionary = record_variant
		var pos := _record_surface_position(record)
		var u := fposmod(pos.x + PI, TAU) * r
		var z_m := pos.y + l * 0.5
		var cx := posmod(int(floor(u / STREAM_CHUNK_SIZE_M)), max(1, num_chunks_x))
		var cz := clampi(int(floor(z_m / STREAM_CHUNK_SIZE_M)), 0, max(0, num_chunks_z - 1))
		var key := Vector2i(cx, cz)
		if not spatial_chunks.has(key):
			spatial_chunks[key] = [] as Array[Dictionary]
		(spatial_chunks[key] as Array).append(record)

func clear_all_placed_objects() -> void:
	placement_records.clear()
	spatial_chunks.clear()
	live_placements.clear()
	has_placement_stream_center = false
	var to_remove: Array[Node] = []
	for child in get_children():
		if child is CanvasLayer and child.name == "DebugConsole":
			continue
		to_remove.append(child)
	for child in to_remove:
		remove_child(child)
		child.free() if not is_inside_tree() else child.queue_free()

func load_object_map(path: String) -> void:
	object_map_path = path
	clear_all_placed_objects()
	spawn_all_markers()

func load_object_map_with_progress(path: String, progress_cb: Callable = Callable()) -> void:
	object_map_path = path
	clear_all_placed_objects()
	await spawn_all_markers_with_progress(progress_cb)

func spawn_all_markers() -> void:
	clear_all_placed_objects()
	await _load_and_spawn_from_json()

func spawn_all_markers_with_progress(progress_cb: Callable = Callable()) -> void:
	clear_all_placed_objects()
	await _load_and_spawn_from_json(progress_cb)

func _load_and_spawn_from_json(progress_cb: Callable = Callable()) -> bool:
	var world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null
	if world:
		active_map_config = world.active_map_config
		cylinder_radius = world.radius
		cylinder_length = world.cylinder_length
	if active_map_config.is_empty():
		return false
	object_map_path = MapConfigClass.get_object_map_path(active_map_config)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(object_map_path))
	if not data is Dictionary or not data.get("objects") is Array:
		push_error("Map placements are missing or malformed: " + object_map_path)
		return false
	var catalog: Dictionary = active_map_config.objects.model_catalog
	for i in data.objects.size():
		if i % 32 == 0 and progress_cb.is_valid():
			await progress_cb.call(0.05 + 0.9 * float(i) / maxf(data.objects.size(), 1), "Reading map placements")
		var record: Variant = data.objects[i]
		if not record is Dictionary:
			push_error("Map placement %d is not an object" % i)
			return false
		if not catalog.has(record.get("asset")):
			push_error("Unknown placement asset: " + str(record.get("asset")))
			return false
		placement_records.append(record.duplicate(true))
	_rebuild_spatial_chunks()
	var spawn_points: Array = data.get("spawn_points", [])
	if not spawn_points.is_empty() and spawn_points[0] is Dictionary:
		placement_stream_center = Vector2(float(spawn_points[0].get("theta", 0.0)), float(spawn_points[0].get("z", 0.0)))
		has_placement_stream_center = true
	elif not placement_records.is_empty():
		var first_position := _record_surface_position(placement_records[0])
		placement_stream_center = first_position
		has_placement_stream_center = true
	else:
		placement_stream_center = Vector2.ZERO
		has_placement_stream_center = true
	_update_placement_streaming(true)
	if progress_cb.is_valid():
		await progress_cb.call(1.0, "Map placements ready")
	return true

func _record_surface_position(record: Dictionary) -> Vector2:
	var packed: Variant = record.get("transform", [])
	if packed is Array and packed.size() >= 12:
		var x := float(packed[9])
		var y := float(packed[10])
		return Vector2(atan2(y, x), float(packed[11]))
	if record.has("theta") and record.has("z"):
		return Vector2(float(record.theta), float(record.z))
	return Vector2.ZERO

func _surface_distance(a: Vector2, b: Vector2) -> float:
	var arc := wrapf(a.x - b.x, -PI, PI) * maxf(cylinder_radius, 1.0)
	return Vector2(arc, a.y - b.y).length()

func _player_surface_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		return placement_stream_center
	return Vector2(atan2(player.global_position.y, player.global_position.x), player.global_position.z)

var placement_scan_index: int = 0
var placement_candidates_buffer: Array[Dictionary] = []

func _update_placement_streaming(force: bool = false) -> void:
	if placement_records.is_empty() or active_map_config.is_empty():
		return
	var world := get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null
	var center := _player_surface_position() if get_tree().get_first_node_in_group("player") else placement_stream_center

	if not force and has_placement_stream_center and not live_placements.is_empty() and _surface_distance(center, placement_stream_center) < 15.0:
		return

	placement_stream_center = center
	has_placement_stream_center = true

	if spatial_chunks.is_empty() and not placement_records.is_empty():
		_rebuild_spatial_chunks()

	# 1. Despawn out-of-range live placement nodes (bounded set of live_placements <= 256)
	var live_keys := live_placements.keys().duplicate()
	for id_var in live_keys:
		var id := str(id_var)
		var live: Node = live_placements.get(id, null)
		if not is_instance_valid(live) or live.is_queued_for_deletion():
			live_placements.erase(id)
			continue
		if live is Node3D:
			var live_pos := Vector2(atan2(live.global_position.y, live.global_position.x), live.global_position.z)
			if _surface_distance(live_pos, center) > PLACEMENT_RETENTION_RADIUS_M:
				var record: Dictionary = live.get_meta("placement_record") if live.has_meta("placement_record") else {}
				if not record.is_empty():
					_capture_live_placement(record, live)
				live_placements.erase(id)
				live.queue_free()

	# 2. Query spatial hash grid chunks within streaming distance
	var r := maxf(cylinder_radius, 1.0)
	var l := maxf(cylinder_length, 1.0)
	var circ := TAU * r
	var num_chunks_x := int(ceil(circ / STREAM_CHUNK_SIZE_M))
	var num_chunks_z := int(ceil(l / STREAM_CHUNK_SIZE_M))
	var center_key := _pos_to_spatial_chunk_key(center)
	var chunk_rad := int(ceil(PLACEMENT_STREAM_RADIUS_M / STREAM_CHUNK_SIZE_M))

	var candidates: Array[Dictionary] = []

	for dz in range(-chunk_rad, chunk_rad + 1):
		var cz := center_key.y + dz
		if cz < 0 or cz >= num_chunks_z:
			continue
		for dx in range(-chunk_rad, chunk_rad + 1):
			var cx := posmod(center_key.x + dx, num_chunks_x)
			var key := Vector2i(cx, cz)
			if not spatial_chunks.has(key):
				continue
			var chunk_records: Array = spatial_chunks[key]
			for record in chunk_records:
				var id := str(record.get("id", ""))
				if id.is_empty() or live_placements.has(id):
					continue
				var distance := _surface_distance(_record_surface_position(record), center)
				if distance <= PLACEMENT_STREAM_RADIUS_M:
					candidates.append({"record": record, "distance": distance})

	if candidates.is_empty():
		return

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var spawned := 0
	for candidate in candidates:
		if live_placements.size() >= MAX_LIVE_PLACEMENTS or spawned >= PLACEMENTS_PER_TICK:
			break
		var record: Dictionary = candidate.record
		var id := str(record.get("id", ""))
		if live_placements.has(id):
			continue
		var instance = preload("res://scripts/map_object_factory.gd").create(active_map_config, record, world)
		instance.set_meta("map_stream_initial_transform", instance.transform)
		instance.set_meta("placement_record", record)
		add_child(instance)
		live_placements[id] = instance
		spawned += 1

func _capture_live_placement(record: Dictionary, object: Node) -> void:
	if not object is SurfaceLightObject:
		return
	var packed: Array = []
	var transform := (object as Node3D).transform
	for vector in [transform.basis.x, transform.basis.y, transform.basis.z, transform.origin]:
		packed.append_array([vector.x, vector.y, vector.z])
	var initial_transform: Variant = object.get_meta("map_stream_initial_transform") if object.has_meta("map_stream_initial_transform") else null
	if record.has("transform") or initial_transform == null or not transform.is_equal_approx(initial_transform):
		record["transform"] = packed
		# An explicit local transform is authoritative; discard redundant surface coordinates.
		record.erase("theta")
		record.erase("z")
	record["tint"] = MapConfigClass.rgba(object.tint)
	record["light_color"] = MapConfigClass.rgba(object.light_color)
	record["light_energy"] = object.light_energy
	record["light_range_m"] = object.light_range
	record["flicker"] = object.enable_flicker
	record["name"] = str(object.name)

func get_all_placement_records() -> Array:
	var known_ids: Dictionary = {}
	var removed_records: Array[Dictionary] = []
	for record_variant in placement_records:
		if not record_variant is Dictionary:
			continue
		var record: Dictionary = record_variant
		var id := str(record.get("id", ""))
		known_ids[id] = true
		if live_placements.has(id):
			var object: Node = live_placements[id]
			if is_instance_valid(object) and object.is_queued_for_deletion():
				live_placements.erase(id)
				removed_records.append(record)
			elif is_instance_valid(object):
				_capture_live_placement(record, object)
	for record in removed_records:
		placement_records.erase(record)
	# Include objects added by the in-world editor since the map was loaded.
	for child in get_children():
		if not child is SurfaceLightObject or child.is_queued_for_deletion():
			continue
		var object := child as SurfaceLightObject
		if known_ids.has(object.instance_id):
			continue
		var packed: Array = []
		var transform := object.transform
		for vector in [transform.basis.x, transform.basis.y, transform.basis.z, transform.origin]:
			packed.append_array([vector.x, vector.y, vector.z])
		placement_records.append({"id": object.instance_id, "asset": object.asset_id, "name": str(object.name), "transform": packed, "tint": MapConfigClass.rgba(object.tint), "light_color": MapConfigClass.rgba(object.light_color), "light_energy": object.light_energy, "light_range_m": object.light_range, "flicker": object.enable_flicker})
		known_ids[object.instance_id] = true
	return placement_records.duplicate(true)

func replace_placement_records(records: Array) -> bool:
	for record in records:
		if not record is Dictionary or not active_map_config.objects.model_catalog.has(record.get("asset")):
			return false
	clear_all_placed_objects()
	placement_records = records.duplicate(true)
	has_placement_stream_center = false
	_update_placement_streaming(true)
	return true

func spawn_light_emitter(
	type: SurfaceLightObject.ObjectType,
	theta: float,
	z: float,
	custom_col: Color = Color.WHITE,
	custom_range: float = -1.0,
	player_facing_fwd: Vector3 = Vector3.ZERO
) -> SurfaceLightObject:
	var elev = _get_terrain_elevation(theta, z)
	var custom_pos = Vector3.ZERO
	var cyl_world = get_parent().get_node_or_null("CylinderWorld") if get_parent() else null
	if not cyl_world:
		cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null
	if cyl_world and cyl_world.has_method("get_surface_mesh_point_and_normal"):
		var pt_info = cyl_world.get_surface_mesh_point_and_normal(theta, z)
		if not pt_info.is_empty():
			custom_pos = pt_info.get("position", Vector3.ZERO)
			elev = pt_info.get("elevation", elev)

	var player = get_tree().get_first_node_in_group("player") as Node3D
	var facing = player_facing_fwd
	if facing == Vector3.ZERO and player:
		facing = -player.global_basis.z

	var obj = SurfaceLightObject.create_on_cylinder(type, theta, z, cylinder_radius, elev, custom_col, custom_range, 0.0, Vector3.ZERO, custom_pos, -1, _get_model_path(type), facing)
	add_child(obj)
	return obj
