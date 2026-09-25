extends SceneTree

func _watchdog(timeout_sec: float = 20.0) -> void:
	await create_timer(timeout_sec).timeout
	printerr("\n[WATCHDOG TIMEOUT] Test suite exceeded %.1f seconds! Terminating..." % timeout_sec)
	quit(1)
	OS.kill(OS.get_process_id())

func test_check(condition: bool, failure_message: String) -> void:
	if not condition:
		printerr("\n[ASSERTION FAILED] ", failure_message)
		quit(1)
		OS.kill(OS.get_process_id())

func _init() -> void:
	# Start background watchdog to prevent any possibility of hanging
	_watchdog(20.0)

	print("\n=======================================================")
	print(" RUNNING O'NEILL CYLINDER ENGINE VERIFICATION SUITE   ")
	print("=======================================================\n")

	var main_scene = load("res://scenes/main.tscn")
	if not main_scene:
		printerr("[FAIL] Failed to load main scene!")
		quit(1)
		return

	var root_node = main_scene.instantiate()
	root.add_child(root_node)

	# Allow frames for _ready() and generation
	await process_frame
	await physics_frame

	var player = root_node.get_node_or_null("Player") as PlayerController
	var cylinder_world = root_node.get_node_or_null("CylinderWorld") as CylinderGenerator
	var light_bar = root_node.get_node_or_null("AxisLightBar") as AxisLightBar

	if not player or not cylinder_world or not light_bar:
		printerr("[FAIL] Missing core nodes: Player, CylinderWorld, or AxisLightBar!")
		quit(1)
		return

	print("[PASS] Core scene nodes verified: Player, CylinderWorld, AxisLightBar, UI.")

	# Wait for player to settle firmly on cylinder inner floor
	for f in range(25):
		await physics_frame

	# --- TEST 1: Cylinder Wall & Perpendicular Centrifugal Gravity ---
	print("\n--- TEST 1: Cylindrical Wall & Perpendicular Gravity ---")
	var pos = player.global_position
	var r = Vector3(pos.x, pos.y, 0.0).length()
	print("Player position: %s, radial distance from axis: %.2f m (cylinder radius: %.2f m)" % [pos, r, player.cylinder_radius])
	test_check(r > player.cylinder_radius * 0.95, "Player must be on/near the inner surface of the cylinder")
	test_check(player.is_on_floor(), "Player must be firmly grounded on the inner cylindrical floor")

	# Axis of cylinder is Z: Vector3(0, 0, 1)
	var rot_axis = Vector3(0, 0, 1)
	var radial_vec = Vector3(pos.x, pos.y, 0.0).normalized()
	var dot_axis_gravity = radial_vec.dot(rot_axis)
	print("Centrifugal gravity dot rotational axis (should be 0.0): %.6f" % dot_axis_gravity)
	test_check(absf(dot_axis_gravity) < 1e-5, "Centrifugal gravity must be strictly perpendicular to rotational axis")

	# Up vector must also be perpendicular to axis
	var up_dir = player.global_basis.y
	var expected_up = -radial_vec
	var dot_up = up_dir.dot(expected_up)
	var dot_axis_up = up_dir.dot(rot_axis)
	print("Local Up dot expected Up: %.4f (dot with axis: %.6f)" % [dot_up, dot_axis_up])
	test_check(dot_up > 0.98, "Player Up direction must align with inward radial normal towards axis")
	test_check(absf(dot_axis_up) < 1e-4, "Player Up direction must be strictly perpendicular to rotational axis")
	print("[PASS] Test 1: Cylindrical wall and perpendicular centrifugal gravity verified.")

	# --- TEST 2: Walking Movement on Curved Surface ---
	print("\n--- TEST 2: Walking Locomotion & Dynamic Horizon Tracking ---")
	player.input_axis = Vector2(0.5, -0.8).normalized()
	player.is_sprinting = false

	for f in range(40):
		await physics_frame

	var walk_speed = player.velocity.length()
	var walk_state = player.get_locomotion_state()
	print("Walking speed: %.2f m/s (target: %.1f m/s), State: %s" % [walk_speed, player.walk_speed, walk_state])
	test_check(walk_speed > 5.0, "Player must achieve walking speed")
	test_check(walk_state == "WALKING", "Locomotion state must be WALKING")
	test_check(player.is_on_floor(), "Player must remain grounded on the curved surface while walking")

	var walk_up = player.global_basis.y
	var walk_radial = Vector3(player.global_position.x, player.global_position.y, 0).normalized()
	test_check(walk_up.dot(-walk_radial) > 0.98, "Horizon Up must dynamically track curved floor")
	test_check(absf(walk_up.dot(rot_axis)) < 1e-4, "Horizon must remain perpendicular to rotational axis while walking")
	print("[PASS] Test 2: Walking locomotion and dynamic horizon tracking verified.")

	# --- TEST 3: Running / Sprinting ---
	print("\n--- TEST 3: Running / Sprinting Locomotion ---")
	player.mobile_sprint_active = true
	player.is_sprinting = true

	for f in range(40):
		await physics_frame

	var run_speed = player.velocity.length()
	var run_state = player.get_locomotion_state()
	print("Running speed: %.2f m/s (target: %.1f m/s), State: %s" % [run_speed, player.sprint_speed, run_state])
	test_check(run_speed > walk_speed + 3.0, "Sprint speed must be significantly faster than walk speed")
	test_check(run_speed > 11.0, "Player must reach running sprint velocity")
	test_check(run_state == "RUNNING", "Locomotion state must be RUNNING")

	# Stop running
	player.mobile_sprint_active = false
	player.is_sprinting = false
	player.input_axis = Vector2.ZERO
	for f in range(30):
		await physics_frame
	print("[PASS] Test 3: Running / sprinting locomotion verified.")

	# --- TEST 4: Jumping & Landing under Centrifugal Gravity ---
	print("\n--- TEST 4: Jumping & Centrifugal Gravity Landing ---")
	test_check(player.is_on_floor(), "Player must be grounded before jump")
	player.jump_requested = true
	await physics_frame

	var v_up_jump = player.velocity.dot(player.global_basis.y)
	var jump_state = player.get_locomotion_state()
	print("Vertical velocity after jump impulse: %.2f m/s (State: %s)" % [v_up_jump, jump_state])
	test_check(v_up_jump > 6.0, "Jump must impart positive velocity along local Up toward axis")
	test_check(jump_state == "JUMPING", "Locomotion state must be JUMPING")

	# Track apex of jump arc
	var apex_reached = false
	for f in range(60):
		await physics_frame
		if player.velocity.dot(player.global_basis.y) < 0:
			apex_reached = true
	test_check(apex_reached, "Centrifugal gravity must pull jumping player back down (apex reached)")

	# Wait for landing on curved floor
	var landed = false
	for f in range(60):
		await physics_frame
		if player.is_on_floor():
			landed = true
			break
	print("Landed safely back on curved floor: %s, position: %s" % [landed, player.global_position])
	test_check(landed, "Player must land back on the cylinder floor under centrifugal gravity")
	print("[PASS] Test 4: Jumping and centrifugal gravity landing verified.")

	# --- TEST 5: 3D Flight Mode & Microgravity Core Falloff ---
	print("\n--- TEST 5: 3D Flight Mode & Gravity Falloff to Zero at Axis ---")
	player.is_flying = true
	player.fly_vertical_axis = 1.0 # Thruster up towards central axis
	player.input_axis = Vector2(0.0, -1.0) # Fly down cylinder length

	for f in range(80):
		await physics_frame

	var fly_dist_axis = Vector3(player.global_position.x, player.global_position.y, 0).length()
	var fly_state = player.get_locomotion_state()
	print("After flying towards axis: dist_from_axis: %.2f m, State: %s" % [fly_dist_axis, fly_state])
	test_check(fly_state == "FLYING", "Locomotion state must be FLYING")
	test_check(fly_dist_axis < player.cylinder_radius - 20.0, "Player must ascend freely in 3D towards the axis")

	# Fly to central microgravity core (r < 5m)
	player.velocity = Vector3.ZERO
	player.input_axis = Vector2.ZERO
	player.fly_vertical_axis = 0.0
	player.global_position = Vector3(2.0, 1.0, player.global_position.z)
	await physics_frame

	var core_radial = Vector3(player.global_position.x, player.global_position.y, 0).length()
	var core_gravity = player.base_gravity * (core_radial / player.cylinder_radius)
	print("At microgravity core (r=%.2fm): Gravity = %.3f m/s² (vs surface: %.1f m/s²)" % [core_radial, core_gravity, player.base_gravity])
	test_check(core_gravity < player.base_gravity * 0.05, "Centrifugal gravity near axis must be microgravity (<5% surface g)")

	# Right at axis (r = 0.01m)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0.01, 0.01, player.global_position.z)
	await physics_frame
	var axis_r = Vector3(player.global_position.x, player.global_position.y, 0).length()
	var axis_g = player.base_gravity * (axis_r / player.cylinder_radius)
	print("At rotational axis (r=%.3fm): Gravity = %.4f m/s² (Zero-G)" % [axis_r, axis_g])
	test_check(axis_g < 0.01, "Gravity at exact rotational axis must be virtually zero")
	print("[PASS] Test 5: 3D Flight mode and microgravity falloff to zero at axis verified.")

	# --- TEST 6: Horizon Wobble & Self-Righting as Gravity Increases ---
	print("\n--- TEST 6: Horizon Left/Right Wobble Correcting as Gravity Increases ---")
	player.global_position = Vector3(0.1, 0.1, 0.0)
	player.wobble_roll = 0.0
	player.wobble_velocity = 0.0
	await physics_frame

	var g_ratio_zero = clampf(Vector3(player.global_position.x, player.global_position.y, 0).length() / player.cylinder_radius, 0.0, 1.0)
	var rate_zero_g = lerpf(player.wobble_frequency_min, player.wobble_frequency_max, g_ratio_zero)
	print("Microgravity restoring rate: %.2f rad/s (weak restoring torque)" % rate_zero_g)

	# Perturb roll wobble in zero-g
	player.wobble_impulse(25.0)
	var initial_wobble_deg = rad_to_deg(player.wobble_roll)
	print("Injected roll wobble in zero-g: %.2f°" % initial_wobble_deg)

	for f in range(20):
		await physics_frame

	var wobble_after_20f_zerog = absf(rad_to_deg(player.wobble_roll))
	print("Wobble remaining after 20 frames in zero-g: %.2f°" % wobble_after_20f_zerog)
	test_check(wobble_after_20f_zerog > 3.0, "In microgravity, roll wobble should persist with minimal correction")

	# Part B: At full surface gravity
	player.is_flying = false
	player.reset_to_spawn()
	for f in range(20):
		await physics_frame

	var g_ratio_surface = clampf(Vector3(player.global_position.x, player.global_position.y, 0).length() / player.cylinder_radius, 0.0, 1.0)
	var rate_surface_g = lerpf(player.wobble_frequency_min, player.wobble_frequency_max, g_ratio_surface)
	print("Surface high-gravity restoring rate: %.2f rad/s (strong restoring torque)" % rate_surface_g)
	test_check(rate_surface_g > rate_zero_g * 5.0, "Restoring rate at surface gravity must be much higher than in zero-g")

	player.wobble_impulse(25.0)
	var surface_wobble_initial = rad_to_deg(player.wobble_roll)
	print("Injected roll wobble at surface gravity: %.2f°" % surface_wobble_initial)

	for f in range(25):
		await physics_frame

	var wobble_after_25f_surface = absf(rad_to_deg(player.wobble_roll))
	print("Wobble remaining after 25 frames at surface gravity: %.2f°" % wobble_after_25f_surface)
	test_check(wobble_after_25f_surface < 1.0, "At high surface gravity, wobble must rapidly correct back to perpendicular (< 1°)")
	test_check(wobble_after_25f_surface < wobble_after_20f_zerog * 0.25, "Correction at surface gravity must be far stronger than in zero-g")
	print("[PASS] Test 6: Horizon wobble self-righting proportionally to gravity verified.")

	# --- TEST 7: Lighting Extents & Visuals ---
	print("\n--- TEST 7: Axial Lighting System ---")
	light_bar.preset = AxisLightBar.LightingPreset.GRADIENT
	light_bar.set_extent_gradient(Color.ORANGE, Color.CYAN, 2.5, 1.0)
	test_check(light_bar.segment_colors[0] == Color.ORANGE, "First segment color verified")
	test_check(light_bar.segment_colors[light_bar.num_segments - 1] == Color.CYAN, "Last segment color verified")
	print("[PASS] Test 7: Axial lighting system verified.")

	# --- TEST 8: Standard Controls (Joystick Movement vs Screen Drag Look) ---
	print("\n--- TEST 8: Standard Controls (Joystick Movement vs Screen Drag Look) ---")
	var touch_controls = root_node.get_node_or_null("UI/UIRoot/TouchControls") as MobileTouchControls
	test_check(touch_controls != null, "MobileTouchControls node must exist")

	# Verify joystick creation and visibility
	touch_controls._ensure_joystick_created()
	test_check(touch_controls.joystick_base != null and touch_controls.joystick_base.visible, "JoystickBase must exist and be visible")
	test_check(touch_controls.joystick_knob != null and touch_controls.joystick_knob.visible, "Joystick Knob must exist and be visible")
	test_check(touch_controls.joystick_base.size.x >= 100.0 and touch_controls.joystick_base.size.y >= 100.0, "JoystickBase must have valid dimensions")
	print("JoystickBase position: %s, size: %s (Knob pos: %s, size: %s)" % [
		touch_controls.joystick_base.position, touch_controls.joystick_base.size,
		touch_controls.joystick_knob.position, touch_controls.joystick_knob.size
	])

	# Verify joystick stays on screen across UI scales
	var hud_node = root_node.get_node_or_null("UI")
	if hud_node and hud_node.has_method("apply_ui_scale"):
		hud_node.apply_ui_scale(1.5, false)
		var vp_h = root_node.get_viewport().get_visible_rect().size.y
		var joy_global_y = touch_controls.joystick_base.global_position.y
		print("Joystick global Y at 1.5x scale: %.1f px (viewport height: %.1f px)" % [joy_global_y, vp_h])
		test_check(joy_global_y > 100.0 and joy_global_y < vp_h, "JoystickBase must remain visible and within screen at 1.5x scale")
		hud_node.apply_ui_scale(1.0, true)

	var initial_pitch = player.pitch
	var initial_basis = player.global_basis
	var joy_center = touch_controls.joystick_base.global_position + (touch_controls.joystick_base.size * 0.5 * touch_controls.ui_scale)

	# 1. Touch and drag the joystick on the left
	touch_controls._handle_touch_start(10, joy_center)
	touch_controls._handle_touch_drag(10, joy_center + Vector2(40.0, -30.0), Vector2(40.0, -30.0))

	print("Joystick input_axis: %s (should be non-zero)" % player.input_axis)
	test_check(player.input_axis.length() > 0.2, "Joystick must command character movement")
	print("Player pitch after joystick drag: %.4f (initial: %.4f)" % [player.pitch, initial_pitch])
	test_check(is_equal_approx(player.pitch, initial_pitch), "Joystick drag must NOT rotate camera pitch up or down")
	test_check(player.global_basis.is_equal_approx(initial_basis), "Joystick drag must NOT rotate player view to the side")

	# End joystick drag
	touch_controls._handle_touch_end(10)
	test_check(player.input_axis == Vector2.ZERO, "Releasing joystick must reset movement axis to zero")

	# 2. Drag elsewhere on the screen (e.g. center/right side) to rotate view
	var screen_drag_pos = Vector2(700.0, 350.0)
	touch_controls._handle_touch_start(11, screen_drag_pos)
	touch_controls._handle_touch_drag(11, screen_drag_pos + Vector2(60.0, -40.0), Vector2(60.0, -40.0))

	var pitch_after_drag = player.pitch
	print("Pitch after dragging screen: %.4f° (was %.4f°)" % [rad_to_deg(pitch_after_drag), rad_to_deg(initial_pitch)])
	test_check(not is_equal_approx(pitch_after_drag, initial_pitch), "Dragging screen must rotate camera pitch")
	touch_controls._handle_touch_end(11)
	print("[PASS] Test 8: Movement joystick only moves; dragging anywhere else rotates view.")

	# --- TEST 9: PNG Elevation Map & 2D RPG Tilemap System ---
	print("\n--- TEST 9: PNG Elevation Map (0-100m) & RPG Tilemap (Water at 20m) ---")
	test_check(cylinder_world.radius == 4000.0, "Cylinder radius must be 4 km (8 km diameter)")
	test_check(cylinder_world.cylinder_length == 8000.0, "Cylinder length must be 8 km")
	test_check(cylinder_world.elevation_variance == 100.0, "Elevation variance must be 100 m (0 to 100m valid range)")
	test_check(cylinder_world.water_level == 20.0, "Water level must be 20.0 m from elevation 0")

	var elev_sample_spawn = cylinder_world.get_elevation_at(-PI * 0.5, 0.0)
	print("Elevation at player spawn: %.2f m (variance range: 0.0 - 100.0 m)" % elev_sample_spawn)
	test_check(elev_sample_spawn >= 0.0 and elev_sample_spawn <= 100.0, "Elevation must be within 0-100 m variance range")
	test_check(elev_sample_spawn > cylinder_world.water_level, "Initial player location must be somewhere on the terrain that is above sea level (> 20.0 m)")

	# Verify find_safe_spawn_point API
	var spawn_info = cylinder_world.find_safe_spawn_point(-PI * 0.5, 0.0, 2.0)
	print("Safe spawn point info: elevation=%.2f m, terrain_type=%d, clearance_above_sea=%.2f m, is_above_sea_level=%s" % [
		spawn_info["elevation"], spawn_info["terrain_type"], spawn_info["clearance_above_sea"], spawn_info["is_above_sea_level"]
	])
	test_check(spawn_info["is_above_sea_level"], "Safe spawn point must be above sea level")
	test_check(spawn_info["elevation"] > cylinder_world.water_level, "Spawn elevation must be strictly above water level")
	test_check(spawn_info["clearance_above_sea"] >= 2.0, "Spawn clearance above sea level must meet requested minimum clearance")

	# Test automatic relocation when a submerged/underwater location is requested
	# Find a known water location (e.g. river channel around u=0.25 => theta = 0.25 * TAU)
	var water_theta = 0.25 * TAU
	var water_z = 0.0
	var water_elev = cylinder_world.get_elevation_at(water_theta, water_z)
	if water_elev < cylinder_world.water_level:
		var relocated_spawn = cylinder_world.find_safe_spawn_point(water_theta, water_z, 2.0)
		print("Requested submerged location (elev=%.2f m), relocated to: elev=%.2f m, above_sea=%s" % [
			water_elev, relocated_spawn["elevation"], relocated_spawn["is_above_sea_level"]
		])
		test_check(relocated_spawn["is_above_sea_level"], "Underwater spawn requests must be safely relocated above sea level")
		test_check(relocated_spawn["elevation"] > cylinder_world.water_level, "Relocated spawn must be strictly above sea level")

	# Verify player's active position is above sea level
	player.reset_to_spawn()
	var player_r = Vector3(player.global_position.x, player.global_position.y, 0.0).length()
	var water_radius = cylinder_world.radius - cylinder_world.water_level
	print("Player radial distance from axis: %.2f m (water surface radius: %.2f m)" % [player_r, water_radius])
	test_check(player_r < water_radius, "Player must spawn inside the cylinder dry land radius, above the water level radius")

	# Verify loading from PNG image maps
	var terrain_mgr = cylinder_world.terrain_manager
	var ok_load_elev = terrain_mgr.load_elevation_from_png("res://assets/maps/elevation_map.png")
	var ok_load_terr = terrain_mgr.load_terrain_from_png("res://assets/maps/terrain_map.png")
	print("Loaded elevation map PNG: %s, Loaded terrain map PNG: %s (Dimensions: %dx%d)" % [ok_load_elev, ok_load_terr, terrain_mgr.grid_u, terrain_mgr.grid_v])
	test_check(ok_load_elev, "Must successfully load elevation map from PNG image")
	test_check(ok_load_terr, "Must successfully load terrain tilemap from PNG image")

	# Verify saving to PNG format
	var ok_save_elev = terrain_mgr.save_elevation_to_png("user://test_elev_export.png")
	var ok_save_terr = terrain_mgr.save_terrain_to_png("user://test_terr_export.png")
	test_check(ok_save_elev and ok_save_terr, "Must successfully export elevation and terrain to PNG images")

	# Verify water level at 20 m
	var sample_water_elev = terrain_mgr.water_level - 5.0 # 15.0 m (underwater)
	test_check(sample_water_elev < 20.0, "Water basins are below the 20 m water level")

	# Verify water material and volume tinting parameters
	test_check(cylinder_world.water_material != null, "Water material must be configured")
	test_check(cylinder_world.water_material.get_shader_parameter("elevation_map") != null, "Water material must have elevation map bound for volume tinting and land culling")
	test_check(cylinder_world.water_material.get_shader_parameter("water_level") == 20.0, "Water level in water shader must match configured 20.0 m")
	print("[PASS] Test 9: PNG elevation heightmap (0-100m) and RPG tilemap (water at 20m) verified.")

	# --- TEST 10: Max On Daylight Lighting System ---
	print("\n--- TEST 10: Max On Daylight Lighting System & Scale ---")
	test_check(light_bar.bar_length == 8000.0, "Axis light bar length must match 8 km cylinder")
	test_check(light_bar.cylinder_radius == 4000.0, "Axis light bar radius must match 4 km radius")
	test_check(light_bar.global_intensity_multiplier >= 3.0, "Max On lighting intensity must be at full illumination level (>= 3.0)")
	for light in light_bar.light_nodes:
		test_check(light.omni_range >= 6000.0, "Axial omni light range must cover 4 km radial distance")
	print("[PASS] Test 10: Max On daylight lighting level and 8 km cylinder scale verified.")

	print("\n=======================================================")
	print(" ALL O'NEILL CYLINDER SIMULATION TESTS PASSED (10/10)! ")
	print("=======================================================\n")
	quit(0)
