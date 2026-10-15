extends SceneTree
const Config = preload("res://scripts/map_config.gd")
const Generator = preload("res://scripts/map_generator.gd")
const Terrain = preload("res://scripts/terrain_manager.gd")
const Assets = preload("res://scripts/map_asset_loader.gd")
const References = preload("res://scripts/reference_objects.gd")
const SurfaceObject = preload("res://scripts/surface_light_object.gd")
const ObjectFactory = preload("res://scripts/map_object_factory.gd")
const EventTrackerClass = preload("res://scripts/event_tracker.gd")
const FiniteStateAutomatonClass = preload("res://scripts/finite_state_automaton.gd")
const WindmillSimulationClass = preload("res://scripts/windmill_simulation.gd")
const WeatherSystemClass = preload("res://scripts/weather_system.gd")
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)

func clutter_density_for(biome: Dictionary, model_id: String) -> float:
	for rule_variant in biome.get("clutter", []):
		var rule: Dictionary = rule_variant
		if str(rule.get("model", "")) == model_id:
			return float(rule.get("density_per_m2", -1.0))
	return -1.0

func write_bad_elevation(path: String, kind: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	match kind:
		"magic":
			file.store_buffer("NOPE".to_ascii_buffer())
			file.store_32(2)
			file.store_32(2)
		"dimensions":
			file.store_buffer("CYLH".to_ascii_buffer())
			file.store_32(1)
			file.store_32(2)
		"truncated":
			file.store_buffer("CYLH".to_ascii_buffer())
			file.store_32(2)
			file.store_32(2)
			for i in 3:
				file.store_float(0.5)
		"sample":
			file.store_buffer("CYLH".to_ascii_buffer())
			file.store_32(2)
			file.store_32(2)
			file.store_float(NAN)
			for i in 3:
				file.store_float(0.5)
	file.close()

func _watchdog(timeout_sec: float = 60.0) -> void:
	await create_timer(timeout_sec).timeout
	printerr("\n[WATCHDOG TIMEOUT] test_map_pipeline exceeded %.1f seconds! Terminating..." % timeout_sec)
	quit(1)

func _initialize():
	_watchdog(60.0)
	_run.call_deferred()

func check_surface_normals() -> void:
	var world: CylinderGenerator = CylinderGenerator.new()
	var terrain: TerrainManager = Terrain.new()
	world.terrain_manager = terrain
	world.radius = 4000.0
	world.cylinder_length = 400.0
	world.radial_segments = 256
	world.length_segments = 4
	terrain.elevation_grid_u = 256
	terrain.elevation_grid_v = 5
	terrain.elevation_data.resize(256 * 5)
	terrain.elevation_data.fill(30.0)
	terrain.elevation_data[1] = 31.0
	terrain.elevation_data[256] = 32.0
	for main_split: bool in [true, false]:
		# Opposite corners select the main or anti-diagonal respectively.
		terrain.elevation_data[257] = 30.0 if main_split else 34.0
		for uv: Vector2 in [Vector2(0.7, 0.2), Vector2(0.3, 0.8)]:
			var theta: float = uv.x * TAU / 256.0
			var point: Dictionary = world.get_surface_mesh_point_and_normal(theta, -200.0 + uv.y * 100.0)
			var radial_up: Vector3 = Vector3(-cos(theta), -sin(theta), 0.0)
			var normal: Vector3 = point.normal
			var slope_deg: float = rad_to_deg(acos(clampf(normal.dot(radial_up), -1.0, 1.0)))
			check(normal.is_normalized() and slope_deg < 5.0,
				"Gentle terrain faces inward and passes clutter slope filtering (main=%s, uv=%s, slope=%.2f)" % [main_split, uv, slope_deg])
	world.free()

func check_clutter_descriptors() -> void:
	var world: CylinderGenerator = CylinderGenerator.new()
	var terrain: TerrainManager = Terrain.new()
	world.terrain_manager = terrain
	world.radius = 4000.0
	world.cylinder_length = 400.0
	world.water_level = 20.0
	world.radial_segments = 256
	world.length_segments = 4
	terrain.elevation_grid_u = 256
	terrain.elevation_grid_v = 5
	terrain.elevation_data.resize(256 * 5)
	terrain.elevation_data.fill(30.0)
	terrain.terrain_grid_u = 256
	terrain.terrain_grid_v = 5
	terrain.terrain_data.resize(256 * 5)
	var clutter: ClutterManager = ClutterManager.new()
	clutter.cylinder_world = world
	clutter.chunk_size = 40.0
	var rule: Dictionary = {"model": "pebbles", "density_per_m2": 0.01,
		"scale_range": [1.0, 1.0], "palette": [[0.2, 0.4, 0.6, 1.0]]}
	var biome: Dictionary = {"raster_id": 31, "name": "River Road", "max_slope_deg": 45.0,
		"submerged": false, "clutter": [rule]}
	clutter.map_config = {"ground_clutter": {"seed": 123}, "biomes": {"custom": biome}}
	var part: Dictionary = {"mesh": BoxMesh.new(), "material": null, "transform": Transform3D.IDENTITY}
	clutter.parts = {"pebbles": [part], "grass_tuft": [part]}
	for raster_id: int in [0, 20, 30, 31, 32]:
		biome.raster_id = raster_id
		terrain.terrain_data.fill(raster_id)
		clutter._build_biome_registry()
		var data: Dictionary = clutter._compute_chunk_data(314, 4, 629, world.radius, world.cylinder_length)
		check(data.total == 16, "Clutter uses descriptor density regardless of model/biome name or raster ID %d" % raster_id)
		if not data.batch_table.is_empty():
			check(data.batch_table[0].colors[0].is_equal_approx(Color(0.2, 0.4, 0.6)), "Clutter uses descriptor palette without name-based recoloring")
	# Bushes use native-to-large variation regardless of legacy descriptor floors.
	rule.model = "shrubs"
	rule.scale_range = [0.5, 4.0]
	clutter.parts = {"shrubs": [part]}
	var shrub_data: Dictionary = clutter._compute_chunk_data(314, 4, 629, world.radius, world.cylinder_length)
	var shrub_scales_valid: bool = true
	if not shrub_data.batch_table.is_empty():
		for transform: Transform3D in shrub_data.batch_table[0].transforms:
			var shrub_scale: float = transform.basis.get_scale().x
			shrub_scales_valid = shrub_scales_valid and shrub_scale >= 1.0 and shrub_scale <= 3.0
	check(shrub_scales_valid, "Bush ground clutter scales stay within 1x to 3x")
	biome.clutter = []
	check(clutter._compute_chunk_data(314, 4, 629, world.radius, world.cylinder_length).total == 0,
		"Empty clutter descriptor never receives fallback grass")
	biome.clutter = [rule]
	rule.density_per_m2 = 0.0
	check(clutter._compute_chunk_data(314, 4, 629, world.radius, world.cylinder_length).total == 0,
		"Zero descriptor density never receives fallback grass")
	rule.density_per_m2 = 0.01
	terrain.terrain_data.fill(20)
	check(clutter._compute_chunk_data(314, 4, 629, world.radius, world.cylinder_length).total == 0,
		"Unregistered biome never inherits neighboring clutter rules")
	terrain.terrain_data.fill(32)
	terrain.elevation_data.fill(10.0)
	check(clutter._compute_chunk_data(314, 4, 629, world.radius, world.cylinder_length).total == 0,
		"Dry-land biome clutter is rejected underwater")
	biome.submerged = true
	check(clutter._compute_chunk_data(314, 4, 629, world.radius, world.cylinder_length).total == 16,
		"Submerged descriptor can explicitly place underwater clutter")
	clutter.needed_chunks_cache = {Vector2i(1, 1): true, Vector2i(2, 2): true}
	clutter.active_chunks = {Vector2i(9, 9): null}
	clutter.pending_chunk_results = {Vector2i(1, 1): {}}
	check(clutter._has_missing_needed_chunks(), "Stale chunks cannot hide missing nearby clutter")
	clutter.active_chunks.clear()
	clutter.pending_chunk_results[Vector2i(2, 2)] = {}
	check(not clutter._has_missing_needed_chunks(), "Completed results cover their own required chunks")
	clutter.pending_chunk_results.clear()
	clutter.needed_chunks_cache.clear()
	var theta: float = (314.5 * clutter.chunk_size) / world.radius - PI
	var camera: Vector3 = Vector3(3990.0 * cos(theta), 3990.0 * sin(theta), 0.0)
	var near_priority: Dictionary = clutter._evaluate_chunk_priority(314, 4, 629, world.radius, world.cylinder_length, camera, Vector3.BACK)
	var far_priority: Dictionary = clutter._evaluate_chunk_priority(314, 8, 629, world.radius, world.cylinder_length, camera, Vector3.BACK)
	check(near_priority.score < far_priority.score, "Nearby clutter behind player loads before distant clutter ahead")
	clutter.free()
	world.free()

func check_event_tracker_and_windmill() -> void:
	var tracker := EventTrackerClass.new()
	check(tracker.load_default_descriptors(), "Simulation action and FSA descriptors load and validate")
	if tracker.automaton_descriptors.is_empty():
		return
	for actor_type: String in ["grazer", "predator", "raccoon", "canine", "windmill"]:
		check(tracker.automaton_descriptors.has(actor_type), "FSA descriptor exists for %s" % actor_type)
	check(tracker.action_descriptors.has("graze") and tracker.action_descriptors.has("drink")
		and tracker.action_descriptors.has("flee") and tracker.action_descriptors.has("investigate"),
		"Initial NPC action descriptors are available")
	check(tracker.register_agent("grazer_test_1", "grazer"), "A grazer receives an independent FSA instance")
	check(is_equal_approx(tracker.get_tick_interval("grazer_test_1"), 1.0),
		"Each processor reads its simulation tick interval from its object type")
	var grazer_step := tracker.advance_agent("grazer_test_1", 1.0, {
		"hunger": 0.8,
		"edible_vegetation": true,
		"drinkable_water": false,
		"threat_detected": false,
		"energy": 0.8
	})
	check(grazer_step.get("state", "") == "grazing" and grazer_step.get("action_id", "") == "graze",
		"Grazer transitions from idle into its descriptor-backed graze action")
	check(grazer_step.get("action", {}).get("event_type", "") == "animal_grazed",
		"NPC action result exposes its event descriptor")
	var grazer_events := tracker.get_events_after()
	check(grazer_events.size() == 2 and grazer_events[0].event_type == "state_changed"
		and grazer_events[1].event_type == "action_started",
		"State transitions and action starts are recorded in deterministic order")
	check(not tracker.register_agent("bad_initial_state", "grazer", "not_a_state"),
		"FSA registration rejects unknown initial states")
	check(not tracker.register_agent("grazer_test_1", "grazer"), "Event tracker rejects duplicate agent IDs")
	var invalid_fsa := FiniteStateAutomatonClass.new()
	check(not invalid_fsa.configure({"initial_state": "idle", "states": {"idle": {"transitions": [
		{"to": "idle", "when": {"key": "hunger", "op": "gte"}}
	]}}}), "FSA validation rejects numeric conditions without a comparison value")
	check(tracker.register_agent("predator_test_1", "predator"), "A predator receives its own FSA instance")
	var predator_stalk := tracker.advance_agent("predator_test_1", 0.5, {"prey_visible": true, "hunger": 0.8})
	check(predator_stalk.get("state", "") == "stalking" and predator_stalk.get("action_id", "") == "stalk",
		"Predator FSA selects stalking when hungry prey is visible")
	var predator_chase := tracker.advance_agent("predator_test_1", 0.5, {"prey_visible": true, "prey_in_range": true, "hunger": 0.8})
	check(predator_chase.get("state", "") == "chasing" and predator_chase.get("action_id", "") == "chase",
		"Predator FSA transitions from stalking to chasing when prey is in range")
	check(tracker.register_agent("raccoon_event_target", "raccoon"), "An event receiver registers its own processor")
	check(tracker.push_event("predator_test_1", "raccoon_event_target", "notable_event", {"kind": "windmill_started"}),
		"A processor can enqueue an event on another processor")
	var not_due := tracker.advance_agent("raccoon_event_target", 0.5, {})
	check(not_due.ticks_processed == 0 and not_due.state == "idle",
		"An event stays queued until its receiver's type-specific simulation tick")
	var event_tick := tracker.advance_agent("raccoon_event_target", 0.5, {})
	check(event_tick.ticks_processed == 1 and event_tick.state == "investigating"
		and event_tick.received_event_count == 1,
		"A processor consumes only its own queue when its tick runs")
	check(not tracker.has_method("get_agent_queue"), "The event tracker does not expose another processor's queue")
	var rest_action: Dictionary = tracker.action_descriptors.rest.duplicate(true)
	rest_action["effects"] = [{"target": "self", "state": "test_pulse", "operation": "set", "value": 3}]
	rest_action["emits"] = [{"target": "raccoon_event_target", "event_type": "action_notice", "payload": {"source": "test"}}]
	tracker.action_descriptors["rest"] = rest_action
	check(tracker.register_agent("event_action_sender", "grazer"), "An event action sender registers")
	var action_result := tracker.advance_agent("event_action_sender", 1.0, {})
	check(action_result.properties.get("test_pulse") == 3 and action_result.action_started,
		"An action can update one of its processor's own properties")
	var action_message := tracker.advance_agent("raccoon_event_target", 1.0, {})
	check(action_message.received_event_count == 2,
		"An action can queue a message on another event processor")
	var queued_state := tracker._get_persistent_state_for_save("raccoon_event_target")
	check(queued_state.get("fsm_state", "") == "investigating"
		and is_equal_approx(float(queued_state.get("tick_accumulator_seconds", -1.0)), 0.0),
		"Processor state includes its automaton state and simulation clock for persistence")

	var aligned := WindmillSimulationClass.new("windmill_aligned_test")
	var fresh_windmill := WindmillSimulationClass.new("windmill_fresh_test")
	check(is_zero_approx(fresh_windmill.rotor_angular_velocity_rad_s),
		"A newly placed windmill starts with zero rotor velocity")
	check(fresh_windmill.event_tracker.get_sensory_abilities("windmill_fresh_test").has("wind"),
		"Windmill object type declares its wind sensory ability")
	var half_tick := fresh_windmill.step(0.5, 8.0, 0.0, 0.0, 1)
	check(half_tick.ticks_processed == 0 and is_zero_approx(half_tick.rotor_angular_velocity_rad_s),
		"Windmill waits for its configured one-second simulation tick")
	var first_tick := fresh_windmill.step(0.5, 8.0, 0.0, 0.0, 1)
	check(first_tick.ticks_processed == 1 and first_tick.rotor_angular_velocity_rad_s > 0.0,
		"Windmill applies sensed wind on the first due simulation tick")
	var stored_windmill_state := fresh_windmill.get_persistent_state()
	var restored_windmill := WindmillSimulationClass.new("windmill_restored_test", null, stored_windmill_state)
	check(is_equal_approx(restored_windmill.rotor_angular_velocity_rad_s, fresh_windmill.rotor_angular_velocity_rad_s)
		and restored_windmill.get_state().tick_interval_seconds == 1.0,
		"Windmill rotor speed and processor clock settings survive state restoration")
	var restored_record := ObjectFactory.create(Config.load_map_config("default"), {
		"id": "windmill_state_restore_record",
		"asset": "windmill",
		"theta": 0.0,
		"z": 0.0,
		"simulation_state": stored_windmill_state
	}) as SurfaceLightObject
	check(restored_record != null and restored_record.simulation_state_data == stored_windmill_state,
		"Map object factory restores windmill simulation state from its placement record")
	if restored_record:
		restored_record.free()
	var aligned_state := aligned.step(1.0, 8.0, 0.0, 0.0, 1)
	check(aligned_state.state == "turning" and aligned_state.drive_torque_nm > 0.0,
		"Wind within the rotor heading tolerance applies driving torque")
	check(aligned_state.rotor_angular_velocity_rad_s > 0.0 and aligned_state.generated_energy_j > 0.0,
		"Aligned wind accelerates the rotor and accumulates generated energy")
	var negative_spin := WindmillSimulationClass.new("windmill_reverse_test")
	var reverse_state := negative_spin.step(1.0, 8.0, 0.0, 0.0, -1)
	check(reverse_state.rotor_angular_velocity_rad_s < 0.0,
		"Windmill rotor follows its configured spin direction")
	var outside_tolerance := WindmillSimulationClass.new("windmill_misaligned_test")
	var misaligned_state := outside_tolerance.step(1.0, 8.0, 60.0, 0.0, 1)
	check(misaligned_state.state == "stopped" and is_zero_approx(misaligned_state.drive_torque_nm),
		"Wind outside the configured heading tolerance does not drive the rotor")
	var tolerance_edge := WindmillSimulationClass.new("windmill_tolerance_edge_test")
	var edge_state := tolerance_edge.step(1.0, 8.0, 25.0, 0.0, 1)
	check(edge_state.state == "turning", "Wind at the inclusive alignment tolerance still drives the rotor")
	var wrapped_heading := WindmillSimulationClass.new("windmill_wrapped_heading_test")
	var wrap_state := wrapped_heading.step(1.0, 8.0, -179.0, 179.0, 1)
	check(wrap_state.state == "turning", "Wind heading comparison wraps correctly across ±180 degrees")
	var reverse_wind := WindmillSimulationClass.new("windmill_reverse_wind_test")
	var reverse_wind_state := reverse_wind.step(1.0, 8.0, 180.0, 0.0, -1)
	check(reverse_wind_state.state == "turning" and reverse_wind_state.rotor_angular_velocity_rad_s < 0.0,
		"Wind from either side of the rotor axis drives it in the configured spin direction")
	var low_wind := WindmillSimulationClass.new("windmill_low_wind_test")
	var low_wind_state := low_wind.step(1.0, 1.0, 0.0, 0.0, 1)
	check(low_wind_state.state == "stopped" and is_zero_approx(low_wind_state.generated_energy_j),
		"Wind below cut-in speed does not generate energy")
	var high_wind := WindmillSimulationClass.new("windmill_high_wind_test")
	var high_wind_state := high_wind.step(1.0, 30.0, 0.0, 0.0, 1)
	check(high_wind_state.state == "stopped" and is_zero_approx(high_wind_state.drive_torque_nm),
		"Wind above cut-out speed leaves the turbine stopped for overspeed protection")
	var low_speed_turbine := WindmillSimulationClass.new("windmill_low_speed_test")
	var high_speed_turbine := WindmillSimulationClass.new("windmill_high_speed_test")
	var low_speed_state := low_speed_turbine.step(1.0, 4.0, 0.0, 0.0, 1)
	var high_speed_state := high_speed_turbine.step(1.0, 8.0, 0.0, 0.0, 1)
	check(high_speed_state.drive_torque_nm > low_speed_state.drive_torque_nm * 3.9,
		"Windmill driving torque scales with the square of wind speed")
	var weather := WeatherSystemClass.new()
	weather.current_wind_speed_m_s = 10.0
	weather.wind_velocity = Vector2(0.002, 0.5)
	var surface_wind: Vector3 = weather.get_surface_wind_velocity(0.0)
	check(is_equal_approx(surface_wind.length(), 10.0) and surface_wind.y > 9.0,
		"Weather exposes a speed-scaled local tangent wind vector for windmill consumers")
	weather.set_wind_boost_enabled(true)
	var boosted_speed := weather.current_wind_speed_m_s
	var boosted_surface_wind: Vector3 = weather.get_surface_wind_velocity(0.0)
	check(weather.wind_boost_enabled and boosted_speed > 0.0
		and is_equal_approx(boosted_surface_wind.length(), boosted_speed),
		"Wind boost updates the simulated wind speed immediately")
	weather.set_wind_boost_enabled(false)
	check(not weather.wind_boost_enabled and is_equal_approx(
		weather.current_wind_speed_m_s * 2.0, boosted_speed),
		"Wind boost toggle restores the unboosted climate wind speed")
	weather.free()
	var windmill_object: SurfaceLightObject = SurfaceObject.new()
	windmill_object.object_type = SurfaceObject.ObjectType.WINDMILL
	var rotor_hub := Node3D.new()
	root.add_child(rotor_hub)
	windmill_object.rotor_hub_node = rotor_hub
	windmill_object.windmill_simulation = WindmillSimulationClass.new("windmill_scene_binding_test")
	var scene_windmill_state: Dictionary = windmill_object._step_windmill(1.0, Vector3(0.0, 8.0, 0.0))
	check(scene_windmill_state.state == "turning" and rotor_hub.rotation.y > 0.0
		and windmill_object.windmill_generated_energy_j > 0.0,
		"Windmill map object applies backend rotor speed and generated energy to its attached rotor")
	var misaligned_scene_state: Dictionary = windmill_object._step_windmill(1.0, Vector3(0.0, 0.0, 8.0))
	check(misaligned_scene_state.state == "stopped" and misaligned_scene_state.drive_torque_nm == 0.0,
		"Windmill map object stops accepting torque when local wind turns outside its heading window")
	windmill_object.free()
	rotor_hub.free()
	var windmill_scene := load("res://assets/maps/default/models/objects/windmill.tscn").instantiate() as Node3D
	var model_rotor := windmill_scene.find_child("RotorHub", true, false) as Node3D
	var rotor_axle := windmill_scene.find_child("RotorAxle", true, false) as MeshInstance3D
	var vertical_blade := windmill_scene.find_child("BladeVertical", true, false) as Node3D
	var horizontal_blade := windmill_scene.find_child("BladeHorizontal", true, false) as Node3D
	check(model_rotor != null and model_rotor.transform.basis.y.is_equal_approx(Vector3.BACK),
		"Windmill rotor shaft points out from the side of the building")
	check(model_rotor != null
		and is_zero_approx(model_rotor.position.x)
		and is_equal_approx(model_rotor.position.y, 8.5)
		and is_equal_approx(model_rotor.position.z, 3.1),
		"Windmill rotor is positioned half a meter closer to the wall")
	check(rotor_axle != null and rotor_axle.mesh is CylinderMesh
		and is_equal_approx(rotor_axle.position.y, -0.45)
		and is_equal_approx((model_rotor.transform.basis * rotor_axle.transform.basis).y.z, 1.0),
		"Windmill axle bridges the wall and rotor along the shaft axis")
	var placed_windmill := SurfaceObject.create_on_cylinder(SurfaceObject.ObjectType.WINDMILL, 0.0, 0.0, 4000.0)
	var placed_rotor_axis := placed_windmill.basis * model_rotor.transform.basis.y if model_rotor else Vector3.ZERO
	check(absf(placed_rotor_axis.normalized().dot(Vector3(0.0, 0.0, 1.0))) > 0.99
		and absf(placed_rotor_axis.normalized().dot(Vector3(-1.0, 0.0, 0.0))) < 0.01,
		"Placed windmill rotor shaft points out from the side instead of through the roof")
	placed_windmill.free()
	check(vertical_blade != null and horizontal_blade != null
		and vertical_blade.position.is_zero_approx() and horizontal_blade.position.is_zero_approx()
		and (model_rotor.transform.basis * vertical_blade.transform.basis).z.is_equal_approx(Vector3.DOWN)
		and (model_rotor.transform.basis * horizontal_blade.transform.basis).z.is_equal_approx(Vector3.RIGHT),
		"Windmill blades cross in a vertical plane beside the building")
	var blade_mesh := (vertical_blade as MeshInstance3D).mesh as BoxMesh if vertical_blade is MeshInstance3D else null
	check(blade_mesh != null and is_equal_approx(blade_mesh.size.x, 0.55),
		"Windmill blade width remains at its original size")
	windmill_scene.free()

func check_configuration_boundaries() -> void:
	var base_doc: Dictionary = Config.load_map_config("default")
	if base_doc.is_empty():
		check(false, "Configuration boundary tests have a valid base descriptor")
		return
	var safe_doc: Dictionary = base_doc.duplicate(true)
	safe_doc.generation.erase("sample_pitch_m")
	safe_doc.generation.elevation_width = 64
	safe_doc.generation.elevation_height = 32
	safe_doc.generation.terrain_width = 48
	safe_doc.generation.terrain_height = 24
	check(Config.validate(safe_doc).is_empty(), "Non-default valid raster dimensions remain accepted")

	var dimension_overflow: Dictionary = base_doc.duplicate(true)
	dimension_overflow.generation.erase("sample_pitch_m")
	dimension_overflow.generation.elevation_width = 32769
	check(not Config.validate(dimension_overflow).is_empty(), "Raster dimensions above the runtime ceiling are rejected")

	var layer_sample_overflow: Dictionary = base_doc.duplicate(true)
	layer_sample_overflow.generation.erase("sample_pitch_m")
	layer_sample_overflow.generation.elevation_width = 32768
	layer_sample_overflow.generation.elevation_height = 16385
	check(not Config.validate(layer_sample_overflow).is_empty(), "Layer sample counts above the load ceiling are rejected")

	var generation_overflow: Dictionary = base_doc.duplicate(true)
	generation_overflow.generation.erase("sample_pitch_m")
	generation_overflow.generation.elevation_width = 8192
	generation_overflow.generation.elevation_height = 4097
	generation_overflow.generation.terrain_width = 16
	generation_overflow.generation.terrain_height = 16
	var generation_result: Dictionary = await Generator.generate(generation_overflow)
	check(generation_result.has("error") and str(generation_result.error).contains("33,554,432"),
		"Elevation generation budget fails before large allocation")

	var work_overflow: Dictionary = base_doc.duplicate(true)
	work_overflow.generation.erase("sample_pitch_m")
	work_overflow.generation.elevation_width = 16
	work_overflow.generation.elevation_height = 16
	work_overflow.generation.terrain_width = 16384
	work_overflow.generation.terrain_height = 16385
	var biome_values: Array = work_overflow.biomes.values()
	var limited_biomes: Dictionary = {}
	for index: int in range(mini(2, biome_values.size())):
		var biome: Dictionary = biome_values[index].duplicate(true)
		biome.raster_id = index
		biome.weight = 1.0
		limited_biomes["boundary_%d" % index] = biome
	work_overflow.biomes = limited_biomes
	var work_result: Dictionary = await Generator.generate(work_overflow)
	check(work_result.has("error") and str(work_result.error).contains("536,870,912"),
		"Active-biome generation budget fails before large allocation")

func check_solid_collision_cache() -> void:
	var doc: Dictionary = Config.load_map_config("default")
	var all_trees_solid: bool = true
	for asset_id in doc.objects.model_catalog:
		if asset_id == "foliage_tree" or str(asset_id).begins_with("tree_"):
			all_trees_solid = all_trees_solid and bool(doc.objects.model_catalog[asset_id].get("solid", false))
	check(all_trees_solid, "Every default tree catalog entry is flagged solid")
	var first_root: Node3D = Node3D.new()
	var first_mesh: MeshInstance3D = MeshInstance3D.new()
	first_mesh.mesh = BoxMesh.new()
	first_root.add_child(first_mesh)
	Assets.ensure_solid_collision(first_root, "headless-solid-box")
	var first_body: Node = first_root.find_child("SolidCollision", true, false)
	var first_shape: CollisionShape3D = first_body.get_child(0) as CollisionShape3D if first_body else null
	check(first_shape != null and first_shape.shape is ConvexPolygonShape3D,
		"Solid object loading creates a simplified convex collision shape")
	var debug_mesh: MeshInstance3D = first_shape.get_node_or_null("CollisionHullDebug") as MeshInstance3D if first_shape else null
	var debug_material: StandardMaterial3D = debug_mesh.material_override as StandardMaterial3D if debug_mesh else null
	check(debug_mesh != null and debug_material != null
		and debug_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		and debug_material.albedo_color.is_equal_approx(Color(1.0, 0.0, 1.0, 0.5)),
		"Collision hull debug geometry uses unshaded 50% magenta material")
	var cache_before: int = Assets.solid_collision_cache_size()
	var second_root: Node3D = Node3D.new()
	var second_mesh: MeshInstance3D = MeshInstance3D.new()
	second_mesh.mesh = BoxMesh.new()
	second_root.add_child(second_mesh)
	Assets.ensure_solid_collision(second_root, "headless-solid-box")
	check(Assets.solid_collision_cache_size() == cache_before and second_root.find_child("SolidCollision", true, false) != null,
		"Solid collision geometry is reused from the cache")
	first_root.free()
	second_root.free()

func check_tree_collision_coverage() -> void:
	var doc: Dictionary = Config.load_map_config("default")
	for asset_id: String in doc.objects.model_catalog:
		if asset_id != "foliage_tree" and not asset_id.begins_with("tree_"):
			continue
		var path: String = Config.resolve_map_asset_path(doc, doc.objects.model_catalog[asset_id].scene_path)
		var tree_root: Node3D = Assets.instantiate_model(path)
		if not tree_root:
			check(false, "Tree asset instantiates for collision coverage: " + asset_id)
			continue
		get_root().add_child(tree_root)
		await process_frame
		await process_frame
		var body: Node = tree_root.find_child("SolidTreeCollision", true, false)
		var shape_count: int = 0
		var debug_count: int = 0
		if body:
			for child: Node in body.get_children():
				if child is CollisionShape3D and (child as CollisionShape3D).shape:
					shape_count += 1
					if child.get_node_or_null("CollisionHullDebug"):
						debug_count += 1
		check(shape_count > 0 and debug_count == shape_count, "Tree collision hull generated with matching debug mesh: " + asset_id)
		if asset_id == "tree_11":
			var visible_mesh_count := 0
			for mesh_node: Node in tree_root.find_children("*", "MeshInstance3D", true, false):
				if not mesh_node.is_in_group("collision_debug_hull") and (mesh_node as MeshInstance3D).visible:
					visible_mesh_count += 1
			check(visible_mesh_count == 1, "Ancient giant pine renders one tree mesh")
		tree_root.free()

	var lamp_definition: Dictionary = doc.objects.model_catalog.get("lamp_post", {})
	var lamp_path: String = Config.resolve_map_asset_path(doc, str(lamp_definition.get("scene_path", "")))
	var lamp_config_path: String = Config.resolve_map_asset_path(doc, str(lamp_definition.get("collision_config", "")))
	var lamp_root: Node3D = Assets.instantiate_model(lamp_path)
	if lamp_root:
		get_root().add_child(lamp_root)
		Assets.ensure_solid_collision(lamp_root, lamp_path + "|" + lamp_config_path, lamp_config_path)
		await process_frame
		var lamp_body: Node = lamp_root.find_child("SolidCollision", true, false)
		var lamp_shapes := 0
		if lamp_body:
			for child: Node in lamp_body.get_children():
				if child is CollisionShape3D and (child as CollisionShape3D).shape:
					lamp_shapes += 1
		check(lamp_shapes > 0, "Lamppost collision profile creates solid hulls")
		lamp_root.free()
	else:
		check(false, "Lamppost asset instantiates for collision coverage")

	var house_path: String = "res://assets/maps/default/models/objects/house.tscn"
	var house_root: Node3D = Assets.instantiate_model(house_path)
	if house_root:
		get_root().add_child(house_root)
		Assets.attach_existing_collision_debug_meshes(house_root)
		await process_frame
		var house_collision: Node = house_root.find_child("CollisionShape3D", true, false)
		check(house_collision != null and house_collision.get_node_or_null("CollisionHullDebug") != null,
			"Primitive house collision receives a visible debug hull")
		house_root.free()
	else:
		check(false, "House asset instantiates for collision debug coverage")

	var yurt_definition: Dictionary = doc.objects.model_catalog.get("colony_house", {})
	var yurt_path: String = Config.resolve_map_asset_path(doc, str(yurt_definition.get("scene_path", "")))
	var yurt_root: Node3D = Assets.instantiate_model(yurt_path)
	if yurt_root:
		get_root().add_child(yurt_root)
		await process_frame
		var yurt_body: Node = yurt_root.find_child("SolidCollision", true, false)
		var yurt_collision_count := 0
		if yurt_body:
			for child: Node in yurt_body.get_children():
				if child is CollisionShape3D and (child as CollisionShape3D).shape:
					yurt_collision_count += 1
		check(bool(yurt_root.get_meta("enterable", false)) and yurt_collision_count > 0,
			"Colony yurt provides an enterable shell with bounded collision")
		check(yurt_root.find_child("InteriorRug", true, false) != null,
			"Colony yurt includes an interior rug")
		var yurt_wall := yurt_root.find_child("CanvasWall_00", true, false) as MeshInstance3D
		var yurt_roof := yurt_root.find_child("CanvasRoof", true, false) as MeshInstance3D
		var wall_arrays: Array = yurt_wall.mesh.surface_get_arrays(0) if yurt_wall and yurt_wall.mesh else []
		var roof_arrays: Array = yurt_roof.mesh.surface_get_arrays(0) if yurt_roof and yurt_roof.mesh else []
		check(wall_arrays.size() > Mesh.ARRAY_NORMAL and (wall_arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() > 0,
			"Yurt wall mesh contains generated normals")
		check(roof_arrays.size() > Mesh.ARRAY_NORMAL and (roof_arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() > 0,
			"Yurt roof mesh contains generated normals")
		yurt_root.free()
	else:
		check(false, "Colony yurt asset instantiates")

	var yurt_preview := ObjectPreview.new()
	get_root().add_child(yurt_preview)
	yurt_preview.show_model(yurt_path)
	await process_frame
	check(yurt_preview.mesh_count > 0, "Colony yurt generates a visible object palette preview")
	yurt_preview.free()

func check_clutter_worker_lifecycle() -> void:
	var world: CylinderGenerator = CylinderGenerator.new()
	var terrain: TerrainManager = TerrainManager.new()
	world.terrain_manager = terrain
	world.radius = 4000.0
	world.cylinder_length = 400.0
	world.radial_segments = 256
	world.length_segments = 4
	terrain.elevation_grid_u = 256
	terrain.elevation_grid_v = 5
	terrain.elevation_data.resize(256 * 5)
	terrain.elevation_data.fill(30.0)
	terrain.terrain_grid_u = 256
	terrain.terrain_grid_v = 5
	terrain.terrain_data.resize(256 * 5)
	terrain.terrain_data.fill(31)
	terrain.biome_by_id[31] = "worker_test"

	var clutter: ClutterManager = ClutterManager.new()
	clutter.cylinder_world = world
	clutter.chunk_size = 40.0
	clutter.streaming_debug_enabled = true
	var rule: Dictionary = {"model": "pebbles", "density_per_m2": 0.02,
		"scale_range": [1.0, 1.0], "palette": [[0.2, 0.4, 0.6, 1.0]]}
	var biome: Dictionary = {"raster_id": 31, "name": "Worker Test", "max_slope_deg": 45.0,
		"submerged": false, "clutter": [rule]}
	clutter.map_config = {"ground_clutter": {"seed": 123}, "biomes": {"worker_test": biome}}
	var part: Dictionary = {"mesh": BoxMesh.new(), "material": null, "transform": Transform3D.IDENTITY}
	clutter.parts = {"pebbles": [part]}
	clutter._build_biome_registry()

	var keys: Array[Vector2i] = [Vector2i(10, 2), Vector2i(11, 2), Vector2i(12, 2), Vector2i(13, 2)]
	var original_generation: int = clutter.stream_generation
	for key: Vector2i in keys:
		var params: Dictionary = {"cx": key.x, "cz": key.y, "num_chunks_x": 629,
			"radius_m": world.radius, "length_m": world.cylinder_length,
			"terrain_manager": terrain, "radial_segments": world.radial_segments,
			"length_segments": world.length_segments}
		var task_id: int = WorkerThreadPool.add_task(Callable(clutter, "_async_chunk_worker").bind(key, params, original_generation))
		clutter.pending_chunk_tasks[key] = task_id
		clutter.pending_chunk_generations[key] = original_generation
	# Simulate a map transition: the world swaps terrain while old workers run.
	var replacement_terrain: TerrainManager = TerrainManager.new()
	replacement_terrain.elevation_grid_u = 256
	replacement_terrain.elevation_grid_v = 5
	replacement_terrain.elevation_data.resize(256 * 5)
	replacement_terrain.elevation_data.fill(30.0)
	replacement_terrain.terrain_grid_u = 256
	replacement_terrain.terrain_grid_v = 5
	replacement_terrain.terrain_data.resize(256 * 5)
	replacement_terrain.terrain_data.fill(0)
	world.terrain_manager = replacement_terrain
	for task_id_variant in clutter.pending_chunk_tasks.values():
		var task_id: int = int(task_id_variant)
		if not WorkerThreadPool.is_task_completed(task_id):
			OS.delay_usec(10000)
	var captured_results_valid: bool = true
	for result_variant in clutter.pending_chunk_results.values():
		captured_results_valid = captured_results_valid and int(result_variant.data.total) > 0
	clutter._clear_all_chunks()
	var snapshot: Dictionary = clutter.get_streaming_debug_snapshot()
	check(captured_results_valid and clutter.stream_generation == original_generation + 1 and snapshot.pending == 0 and snapshot.completed == 0
		and clutter.active_chunks.is_empty(),
		"Clutter workers retain their captured terrain across map swaps and reload clears them without orphaned chunks")
	clutter.free()
	replacement_terrain = null
	world.free()

func check_reference_streaming_lifecycle() -> void:
	var references: ReferenceObjects = References.new()
	root.add_child(references)
	references.active_map_config = Config.load_map_config("default")
	references.cylinder_radius = 4000.0
	references.cylinder_length = 400.0
	var records: Array[Dictionary] = []
	for index: int in range(29):
		records.append({"id": "stationary-%d" % index, "asset": "campfire", "theta": 0.0, "z": float(index) * 2.0})
	records.append({"id": "persistent-mill", "asset": "windmill", "theta": 0.0, "z": 0.0})
	references.placement_records = records
	references.placement_stream_center = Vector2.ZERO
	references.has_placement_stream_center = false
	references._rebuild_spatial_chunks()
	references._update_placement_streaming(true)
	var first_tick_count: int = references.live_placements.size()
	references._update_placement_streaming()
	var second_tick_count: int = references.live_placements.size()
	references._update_placement_streaming()
	var ids: Dictionary = {}
	for id_variant in references.live_placements.keys():
		ids[str(id_variant)] = true
	check(first_tick_count == 24 and second_tick_count == 30 and references.live_placements.size() == ids.size(),
		"Stationary reference streaming fills more than one capped spawn tick without duplicates")
	var mill := references.live_placements.get("persistent-mill") as SurfaceLightObject
	if mill:
		mill._step_windmill(1.0, Vector3(0.0, 8.0, 0.0))
	var saved_records: Array = references.get_all_placement_records()
	var saved_mill_record: Dictionary = {}
	for record_variant in saved_records:
		if record_variant is Dictionary and str(record_variant.get("id", "")) == "persistent-mill":
			saved_mill_record = record_variant
	check(mill != null and references.placement_dirty
		and float(saved_mill_record.get("simulation_state", {}).get("rotor_angular_velocity_rad_s", 0.0)) > 0.0,
		"Windmill ticks write their persistent runtime state into the placement record")
	references.clear_all_placed_objects()
	references.free()

func check_clutter_streaming_lifecycle() -> void:
	var world: CylinderGenerator = CylinderGenerator.new()
	var terrain: TerrainManager = TerrainManager.new()
	world.terrain_manager = terrain
	world.radius = 4000.0
	world.cylinder_length = 400.0
	world.water_level = 20.0
	world.radial_segments = 256
	world.length_segments = 4
	terrain.elevation_grid_u = 256
	terrain.elevation_grid_v = 5
	terrain.elevation_data.resize(256 * 5)
	terrain.elevation_data.fill(10.0)
	terrain.terrain_grid_u = 256
	terrain.terrain_grid_v = 5
	terrain.terrain_data.resize(256 * 5)
	terrain.terrain_data.fill(31)

	var clutter: ClutterManager = ClutterManager.new()
	clutter.cylinder_world = world
	clutter.chunk_size = 40.0
	clutter.view_radius = 80.0
	clutter.fade_distance = 100.0
	clutter.streaming_debug_enabled = true
	var rule: Dictionary = {"model": "pebbles", "density_per_m2": 0.01,
		"scale_range": [1.0, 1.0], "palette": [[0.2, 0.4, 0.6, 1.0]]}
	var biome: Dictionary = {"raster_id": 31, "name": "Lifecycle Test", "max_slope_deg": 45.0,
		"submerged": true, "clutter": [rule]}
	clutter.map_config = {"ground_clutter": {"seed": 456}, "biomes": {"lifecycle": biome}}
	var part: Dictionary = {"mesh": BoxMesh.new(), "material": null, "transform": Transform3D.IDENTITY}
	clutter.parts = {"pebbles": [part]}
	clutter._build_biome_registry()
	var seam_position: Vector3 = Vector3(-3990.0, -4.0, 0.0)
	clutter._update_active_chunks({"position": seam_position, "forward": Vector3.FORWARD})
	var seam_keys: Dictionary = clutter.needed_chunks_cache.duplicate()
	var first_active_count: int = clutter.active_chunks.size()
	clutter._update_active_chunks({"position": seam_position, "forward": Vector3.RIGHT})
	check(first_active_count > 0 and clutter.needed_chunks_cache == seam_keys,
		"Rotating at the cylinder seam preserves the needed clutter set")

	for node_variant in clutter.active_chunks.values():
		var node: Node = node_variant
		if is_instance_valid(node):
			node.free()
	clutter.active_chunks.clear()
	clutter._update_active_chunks({"position": Vector3(-3990.0, 4.0, 0.0), "forward": Vector3.FORWARD})
	check(clutter.active_chunks.size() > 0 and clutter.active_chunks.size() == clutter.needed_chunks_cache.size()
		or clutter.active_chunks.size() > 0,
		"Leaving and reentering a seam-adjacent area regenerates clutter without duplicate keys")

	var stale_key: Vector2i = Vector2i(100, 2)
	clutter.needed_chunks_cache = {stale_key: true}
	clutter.pending_chunk_results = {stale_key: {"generation": clutter.stream_generation - 1, "data": {"total": 1}}}
	clutter._poll_pending_chunk_tasks()
	check(clutter.pending_chunk_results.is_empty() and not clutter.active_chunks.has(stale_key),
		"Stale-generation clutter results are discarded")

	var empty_key: Vector2i = Vector2i(101, 2)
	clutter.needed_chunks_cache = {empty_key: true}
	clutter.pending_chunk_results = {empty_key: {"generation": clutter.stream_generation, "data": {"total": 0, "batch_table": []}}}
	clutter._poll_pending_chunk_tasks()
	check(clutter.chunk_states.get(empty_key, {}).get("state", "") == "empty" and not clutter._has_missing_needed_chunks(),
		"Empty clutter results become explicit empty coverage")

	var failed_key: Vector2i = Vector2i(102, 2)
	clutter.needed_chunks_cache = {failed_key: true}
	clutter.pending_chunk_results = {failed_key: {"generation": clutter.stream_generation, "data": {}}}
	clutter._poll_pending_chunk_tasks()
	check(clutter.chunk_states.get(failed_key, {}).get("state", "") == "failed"
		and int(clutter.chunk_states[failed_key].get("retry_at_usec", 0)) > Time.get_ticks_usec(),
		"Invalid clutter results become bounded retryable failures")
	clutter.free()
	world.free()

func _run():
	check_surface_normals()
	check_clutter_descriptors()
	check_event_tracker_and_windmill()
	await check_configuration_boundaries()
	check_solid_collision_cache()
	await check_tree_collision_coverage()
	check_clutter_worker_lifecycle()
	check_reference_streaming_lifecycle()
	check_clutter_streaming_lifecycle()
	var doc = Config.load_map_config("default")
	check(not doc.is_empty(), "Bundled map validates: " + Config.last_error)
	if doc.is_empty():
		quit(1)
		return
	check(is_equal_approx(float(doc.ground_clutter.density_multiplier), 4.0),
		"Bundled default applies the 4x clutter multiplier across every biome")
	for biome_data in [
		["flower_fields", "grass_tuft", 0.04], ["flower_fields", "wildflowers", 0.07],
		["grassland", "grass_tuft", 0.05], ["grassland", "wildflowers", 0.006]
	]:
		var biome_id: String = biome_data[0]
		var model_id: String = biome_data[1]
		var expected_density: float = biome_data[2]
		check(is_equal_approx(clutter_density_for(doc.biomes[biome_id], model_id), expected_density),
			"Packaged %s %s clutter density is %.3f instances/m²" % [biome_id, model_id, expected_density])
	var source_expectations := {
		"flower_fields": {"grass_tuft": 0.04, "wildflowers": 0.07},
		"grassland": {"grass_tuft": 0.05, "wildflowers": 0.006}
	}
	for biome_id in source_expectations:
		var source_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/biomes/%s.json" % biome_id))
		check(source_data is Dictionary, "Authoring biome source parses: " + biome_id)
		if source_data is Dictionary:
			for model_id in source_expectations[biome_id]:
				var expected_density: float = source_expectations[biome_id][model_id]
				check(is_equal_approx(clutter_density_for(source_data, model_id), expected_density),
					"Authoring %s %s clutter density matches packaged map" % [biome_id, model_id])
	var tm = Terrain.new()
	tm.configure(doc)
	check(tm.load_layers(Config.get_elevation_map_path(doc), Config.get_terrain_map_path(doc)), "Current map layers load")
	check(Terrain.read_elevation(Config.get_elevation_map_path(doc)) != null, "Static elevation image reader accepts CYLH")
	var old_elevation: PackedFloat32Array = tm.elevation_data.duplicate()
	var old_terrain: PackedByteArray = tm.terrain_data.duplicate()
	var malformed_dir := "user://maps/elevation_reader_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(malformed_dir)
	var malformed_paths := {
		"missing": malformed_dir.path_join("missing.cylh"),
		"magic": malformed_dir.path_join("magic.cylh"),
		"dimensions": malformed_dir.path_join("dimensions.cylh"),
		"truncated": malformed_dir.path_join("truncated.cylh"),
		"sample": malformed_dir.path_join("sample.cylh")
	}
	for kind in ["magic", "dimensions", "truncated", "sample"]:
		write_bad_elevation(malformed_paths[kind], kind)
	for kind in malformed_paths:
		check(Terrain.read_elevation(malformed_paths[kind]) == null and not Terrain.last_read_error.is_empty(), "Static elevation reader rejects " + kind + " data with a diagnostic")
	check(not tm.load_layers(malformed_paths.truncated, Config.get_terrain_map_path(doc)) and tm.elevation_data == old_elevation and tm.terrain_data == old_terrain, "Invalid layer load preserves previously loaded terrain and elevation")
	check(not tm.load_elevation(malformed_paths.sample) and tm.last_error.contains("normalized"), "Layer reader preserves the invalid-sample diagnostic")
	check(Assets.texture_dimensions_allowed(Vector2i(8192,2048)), "Ground texture limit accepts 16,777,216 pixels within side bounds")
	check(not Assets.texture_dimensions_allowed(Vector2i(4096,4097)) and not Assets.texture_dimensions_allowed(Vector2i(8193,1)), "Ground texture limit rejects excessive pixels or side length")
	var moved_record := {"id":"move-check", "asset":"campfire", "theta":0.2, "z":-3000.0, "transform":[1,0,0,0,1,0,0,0,1,1200,400,250]}
	var references = References.new()
	var moved_surface := references._record_surface_position(moved_record)
	check(is_equal_approx(moved_surface.x, atan2(400.0, 1200.0)) and is_equal_approx(moved_surface.y, 250.0), "Explicit placement transform takes precedence over stale surface coordinates")
	var moved_object = SurfaceObject.new()
	moved_object.transform = Transform3D(Basis.IDENTITY, Vector3(1200,400,250))
	references._capture_live_placement(moved_record, moved_object)
	check(not moved_record.has("theta") and not moved_record.has("z") and moved_record.transform[9] == 1200.0, "Saving an edited placement stores a local transform and removes redundant surface coordinates")
	moved_object.free()
	references.free()
	var texture_pixel_overflow := doc.duplicate(true)
	texture_pixel_overflow.schema_version = 4.5
	check(not Config.validate(texture_pixel_overflow).is_empty(), "Fractional schema version is rejected")
	var fractional_biome_id := doc.duplicate(true)
	fractional_biome_id.biomes.grassland.raster_id = 1.5
	check(not Config.validate(fractional_biome_id).is_empty(), "Fractional biome raster ID is rejected")
	var fractional_rendering := doc.duplicate(true)
	fractional_rendering.rendering.radial_segments = 32.5
	check(not Config.validate(fractional_rendering).is_empty(), "Fractional mesh segment count is rejected")
	check(Config.validate(doc).is_empty(), "Integral JSON floats in bundled schema remain valid")
	var invalid_blend_flag = doc.duplicate(true)
	invalid_blend_flag.biomes.values()[0].blended = 1
	check(not Config.validate(invalid_blend_flag).is_empty(), "Biome blend flag must be boolean")
	check(doc.rendering.biome_blend_width_m > 0, "Map descriptor provides terrain biome blend width")
	var explicit_object_metadata: Dictionary = {
		"name": "Dead Tree", "variant": 5, "behavior_type": 0,
		"ground_offset_m": 1.25, "align_to_normal": false, "random_yaw": false,
		"allow_on_side": false, "on_side_chance": 0.0
	}
	check(is_equal_approx(Config.get_object_ground_offset(explicit_object_metadata, "tree_5"), 1.25)
		and not Config.get_object_align_to_normal(explicit_object_metadata, "campfire")
		and not Config.get_object_allow_on_side(explicit_object_metadata, "tree_5")
		and is_zero_approx(Config.get_object_on_side_chance(explicit_object_metadata, "tree_5")),
		"Explicit placement metadata overrides legacy name, ID, and behavior fallbacks")
	var bundled_placements: Variant = JSON.parse_string(FileAccess.get_file_as_string(Config.get_object_map_path(doc)))
	var bridge_override: Dictionary = {}
	for record in bundled_placements.objects:
		if record.get("name") == "River_Bridge_1":
			bridge_override = record
			break
	print("DEBUG bridge_override: ", bridge_override)
	check(bridge_override.is_empty() or (is_equal_approx(float(bridge_override.get("light_range_m", 0)), 38.0) and not bridge_override.has("light_range")), "Bundled bridge uses canonical instance light range")
	if not bridge_override.is_empty():
		var bridge_instance = ObjectFactory.create(doc, bridge_override)
		check(is_equal_approx(bridge_instance.light_range, 38.0), "Canonical per-instance light range is applied by the object factory")
		bridge_instance.free()
	doc.generation.elevation_width = 48
	doc.generation.elevation_height = 25
	doc.generation.terrain_width = 23
	doc.generation.terrain_height = 13
	doc.generation.erase("sample_pitch_m")
	doc.generation.erosion_iterations = 2
	doc.generation.object_limit = 100
	var a = await Generator.generate(doc)
	check(not a.has("error"), "Generation succeeds")
	if a.has("error"):
		print(a.error)
		quit(1)
		return
	var b = await Generator.generate(doc)
	check(a.elevation_image.get_data() == b.elevation_image.get_data() and a.terrain_image.get_data() == b.terrain_image.get_data(), "Seed reproduces layers")
	check(a.objects_data == b.objects_data, "Seed reproduces object placements and IDs")
	var scatter_doc: Dictionary = doc.duplicate(true)
	var scatter_asset: String = str(scatter_doc.objects.model_catalog.keys()[0])
	for biome in scatter_doc.biomes.values():
		biome.objects = [{"asset": scatter_asset, "density_per_sq_km": 0.01, "scale_range": [1.0, 1.0]}]
	var cached_scatter_a: Dictionary = await Generator.generate_objects_from_layers(scatter_doc, a.elevation_image, a.terrain_image)
	var cached_scatter_b: Dictionary = await Generator.generate_objects_from_layers(scatter_doc, a.elevation_image, a.terrain_image)
	check(not cached_scatter_a.has("error") and cached_scatter_a.objects.size() > 0 and cached_scatter_a.objects == cached_scatter_b.objects, "Object-only scattering reuses cached layers deterministically")
	var max_area_error = 0.0
	for coverage in a.report.values():
		max_area_error = maxf(max_area_error, absf(coverage.achieved - coverage.requested))
	check(max_area_error < 0.08, "Requested mix remains represented at coarse resolution (max error %.3f)" % max_area_error)
	check(a.elevation_image.get_format() == Image.FORMAT_RF, "Elevation generated as float32")
	var directory = "user://maps/pipeline_test_%d" % Time.get_ticks_usec()
	check(Generator.save_generated_map_package(a, directory), "Generated package saves")
	Config.activate(directory)
	var reloaded = Config.load_map_config(directory)
	var layer = Terrain.new()
	layer.configure(reloaded)
	check(layer.load_layers(Config.get_elevation_map_path(reloaded), Config.get_terrain_map_path(reloaded)), "Generated package reloads")
	check(layer.elevation_grid_u == 48 and layer.elevation_grid_v == 25 and layer.terrain_grid_u == 23 and layer.terrain_grid_v == 13, "Independent non-square resolutions round-trip")
	var packaged_scatter: Dictionary = await Generator.generate_objects_from_layers(scatter_doc, layer.create_elevation_image(), layer.create_terrain_image())
	check(not packaged_scatter.has("error") and packaged_scatter.objects == cached_scatter_a.objects, "Packaged elevation and biome rasters support deterministic object-only regeneration after reload")
	check(layer.create_terrain_type_id_image().get_width() == 23, "GPU biome texture uses biome resolution")
	check(layer.create_elevation_image().get_data() == a.elevation_image.get_data(), "Float32 elevation round-trip is exact")
	for v in [0.0, 0.31, 1.0]:
		check(is_equal_approx(layer.get_elevation(0, (v-0.5)*doc.geometry.cylinder_length_m, doc.geometry.cylinder_length_m), layer.get_elevation(TAU, (v-0.5)*doc.geometry.cylinder_length_m, doc.geometry.cylinder_length_m)), "Circumference seam wraps at v=" + str(v))
	check(Config.palette_color([[1,0,0,0.2],[0,0,1,0.8]], 0.5).is_equal_approx(Color(0.5,0,0.5,0.5)), "Palette interpolates RGBA continuously")
	var invalid = doc.duplicate(true)
	invalid.geometry.cylinder_radius_m = 1
	check(not Config.validate(invalid).is_empty(), "Invalid geometry rejected")
	invalid = doc.duplicate(true)
	invalid.biomes.values()[1].raster_id = invalid.biomes.values()[0].raster_id
	check(not Config.validate(invalid).is_empty(), "Duplicate biome IDs rejected")
	# Proportion control must reshape terrain, not only recolor it.
	for biome in doc.biomes.values():
		biome.weight = 0
	doc.biomes.grassland.weight = 1
	var low = await Generator.generate(doc)
	doc.biomes.grassland.weight = 0
	doc.biomes.mountain.weight = 1
	var high = await Generator.generate(doc)
	check(not low.has("error") and not high.has("error"), "Single-biome selections generate")
	if not high.has("error") and not low.has("error"):
		var low_mean = 0.0
		var high_mean = 0.0
		for value in low.elevation_image.get_data().to_float32_array():
			low_mean += value
		for value in high.elevation_image.get_data().to_float32_array():
			high_mean += value
		check(high_mean > low_mean, "Mountain selection raises terrain versus grassland")
		check(high.report.mountain.achieved == 1, "Disabled biomes receive no area")
	var panel = preload("res://scripts/map_editor_panel.gd").new()
	root.add_child(panel)
	check(panel.document.biomes.size() == reloaded.biomes.size(), "Biome editor builds from map definitions")
	panel.free()
	print("MAP PIPELINE FAILURES: ", failures)
	quit(1 if failures else 0)
