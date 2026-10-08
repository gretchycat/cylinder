extends SceneTree

const MapConfig = preload("res://scripts/map_config.gd")

func _watchdog(timeout_sec: float = 60.0) -> void:
	await create_timer(timeout_sec).timeout
	printerr("\n[WATCHDOG TIMEOUT] Headless profiling script exceeded %.1f seconds!" % timeout_sec)
	quit(1)
	OS.kill(OS.get_process_id())

func _init() -> void:
	MapConfig.active_map_file = "user://profile_performance_active_%d.txt" % Time.get_ticks_usec()
	_watchdog(90.0)

	print("\n=======================================================")
	print(" HEADLESS PERFORMANCE & SUBSYSTEM PROFILER             ")
	print("=======================================================\n")

	var main_scene = load("res://scenes/main.tscn")
	if not main_scene:
		printerr("[FAIL] Failed to load main scene!")
		quit(1)
		return

	var root_node = main_scene.instantiate()
	root.add_child(root_node)

	# Initial warm up
	for i in range(10):
		await process_frame
		await physics_frame

	var player = root_node.get_node_or_null("Player") as PlayerController
	var clutter_mgr = root_node.get_node_or_null("ClutterManager") as ClutterManager
	var weather_sys = root_node.get_node_or_null("WeatherSystem") as WeatherSystem
	var cylinder_world = root_node.get_node_or_null("CylinderWorld") as CylinderGenerator

	print("[SYSTEM STATUS]")
	print("  Player Node:      %s" % ("Found" if player else "Missing"))
	print("  Clutter Manager:  %s" % ("Found" if clutter_mgr else "Missing"))
	print("  Weather System:   %s" % ("Found" if weather_sys else "Missing"))
	print("  Cylinder World:   %s" % ("Found" if cylinder_world else "Missing"))

	print("\n[PHASE 1: IDLE PROFILING (100 FRAMES)]")
	var idle_process_times: Array[float] = []
	var idle_physics_times: Array[float] = []
	
	for f in range(100):
		await physics_frame
		await process_frame
		idle_process_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		idle_physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)

	_print_time_stats("Idle Process Time (ms)", idle_process_times)
	_print_time_stats("Idle Physics Time (ms)", idle_physics_times)

	print("\n[PHASE 2: LOCOMOTION & CHUNK MOVING PROFILING (200 FRAMES)]")
	var move_process_times: Array[float] = []
	var move_physics_times: Array[float] = []
	var clutter_build_times: Array[float] = []
	
	if player:
		player.input_axis = Vector2(1.0, 0.5).normalized()
		player.is_sprinting = true

	var total_clutter_instances: int = 0
	var active_chunks_count: int = 0
	if clutter_mgr:
		active_chunks_count = clutter_mgr.active_chunks.size()
		for chunk in clutter_mgr.active_chunks.values():
			if is_instance_valid(chunk) and chunk.has_meta("clutter_placed_instances"):
				total_clutter_instances += int(chunk.get_meta("clutter_placed_instances"))

	for f in range(200):
		var t_start = Time.get_ticks_usec()
		await physics_frame
		await process_frame
		var frame_cost = (Time.get_ticks_usec() - t_start) / 1000.0

		move_process_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		move_physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)

	if clutter_mgr:
		active_chunks_count = clutter_mgr.active_chunks.size()
		total_clutter_instances = 0
		for chunk in clutter_mgr.active_chunks.values():
			if is_instance_valid(chunk) and chunk.has_meta("clutter_placed_instances"):
				total_clutter_instances += int(chunk.get_meta("clutter_placed_instances"))

	_print_time_stats("Moving Process Time (ms)", move_process_times)
	_print_time_stats("Moving Physics Time (ms)", move_physics_times)

	print("\n[RESOURCE & OVERHEAD SNAPSHOT]")
	print("  Node Count in SceneTree:    %d" % int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	print("  Total Objects (C++ Engine): %d" % int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	print("  Active 3D Physics Objects:  %d" % int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)))
	print("  3D Collision Pairs:         %d" % int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
	print("  Clutter Active Chunks:      %d" % active_chunks_count)
	print("  Clutter Placed Instances:   %d" % total_clutter_instances)
	print("  Static Memory Allocation:   %.2f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)))

	print("\n[PHASE 3: ISOLATED SUBSYSTEM micro-BENCHMARKS]")
	_benchmark_clutter_generation(clutter_mgr)
	_benchmark_physics_raycasts(player)
	_benchmark_particle_emitter(root_node)

	print("\n=======================================================")
	print(" PROFILING COMPLETE                                    ")
	print("=======================================================\n")
	quit(0)

func _benchmark_clutter_generation(clutter_mgr: ClutterManager) -> void:
	if not clutter_mgr:
		print("  [Clutter Benchmark] Skipped (No ClutterManager found)")
		return

	print("  [Clutter Benchmark] Testing single chunk generation cost...")
	var t0 = Time.get_ticks_usec()
	var chunk = clutter_mgr._build_chunk(10, 10, 100, 4000.0, 18000.0)
	var t1 = Time.get_ticks_usec()
	var cost_ms = (t1 - t0) / 1000.0
	var instances = chunk.get_meta("clutter_placed_instances") if chunk.has_meta("clutter_placed_instances") else 0
	print("    -> Single Chunk Build Time: %.3f ms (Generated %d clutter instances)" % [cost_ms, instances])
	if chunk:
		chunk.free()

func _benchmark_physics_raycasts(player: PlayerController) -> void:
	if not player or not player.is_inside_tree():
		print("  [Physics Benchmark] Skipped (No Player node)")
		return

	print("  [Physics Benchmark] Running 1,000 centrifugal surface raycasts...")
	var space_state = player.get_world_3d().direct_space_state
	var pos = player.global_position
	var t0 = Time.get_ticks_usec()
	var hits = 0
	for i in range(1000):
		var ray_query = PhysicsRayQueryParameters3D.create(pos, pos + Vector3(0, -100, 0))
		var res = space_state.intersect_ray(ray_query)
		if not res.is_empty():
			hits += 1
	var t1 = Time.get_ticks_usec()
	var duration_ms = (t1 - t0) / 1000.0
	print("    -> 1,000 Direct Space Physics Raycasts: %.3f ms (%.3f us/raycast)" % [duration_ms, (t1 - t0) / 1000.0])

func _benchmark_particle_emitter(root_node: Node) -> void:
	var weather_sys = root_node.get_node_or_null("WeatherSystem") as WeatherSystem
	if not weather_sys:
		print("  [Particle Benchmark] Skipped (No WeatherSystem found)")
		return

	print("  [Particle Benchmark] Profiling weather system CPU step cost...")
	var t0 = Time.get_ticks_usec()
	weather_sys._process(0.016)
	var t1 = Time.get_ticks_usec()
	print("    -> Weather System Process Step: %.3f ms" % [(t1 - t0) / 1000.0])

func _print_time_stats(label: String, values: Array[float]) -> void:
	if values.is_empty():
		return
	var sum = 0.0
	var max_val = -1.0
	var min_val = 999999.0
	for v in values:
		sum += v
		if v > max_val: max_val = v
		if v < min_val: min_val = v
	var avg = sum / values.size()
	print("  %-28s | Avg: %6.2f ms | Min: %6.2f ms | Max: %6.2f ms" % [label, avg, min_val, max_val])
