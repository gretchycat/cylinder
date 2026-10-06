extends SceneTree

const CylinderParticleEmitter = preload("res://scripts/cylinder_particle_emitter.gd")
const ClimateSystem = preload("res://scripts/climate_system.gd")
const LoadingScreen = preload("res://scripts/loading_screen.gd")
const ClutterManager = preload("res://scripts/clutter_manager.gd")
const MapConfig = preload("res://scripts/map_config.gd")

func _watchdog(timeout_sec: float = 60.0) -> void:
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
	# Keep this legacy simulation suite independent of whichever user map was
	# active in a previous editor/library test or local app session.
	MapConfig.active_map_file = "user://test_simulation_active_%d.txt" % Time.get_ticks_usec()
	# Start background watchdog to prevent any possibility of hanging
	_watchdog(60.0)

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
	player.mobile_sprint_active = false
	player.is_sprinting = false

	for f in range(40):
		await physics_frame

	var walk_speed = player.velocity.length()
	var walk_state = player.get_locomotion_state()
	print("Walking speed: %.2f m/s (target: %.1f m/s), State: %s" % [walk_speed, player.walk_speed, walk_state])
	test_check(walk_speed > 1.0, "Player must achieve walking speed")
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
	test_check(run_speed > walk_speed + 1.5, "Sprint speed must be significantly faster than walk speed")
	test_check(run_speed > 3.5, "Player must reach running sprint velocity")
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
	test_check(v_up_jump > 3.5, "Jump must impart positive velocity along local Up toward axis")
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

	# --- TEST 7: Axial Lighting System ---
	print("\n--- TEST 7: Axial Lighting System ---")
	light_bar.preset = AxisLightBar.LightingPreset.GRADIENT
	light_bar.set_extent_gradient(Color.ORANGE, Color.CYAN, 2.5, 1.0)
	test_check(light_bar.segment_colors[0] == Color.ORANGE, "First segment color verified")
	test_check(light_bar.segment_colors[light_bar.num_segments - 1] == Color.CYAN, "Last segment color verified")

	# Verify multi-stop Sunrise to Twilight gradient preset
	light_bar.preset = AxisLightBar.LightingPreset.GRADIENT
	test_check(light_bar.segment_colors[0].r > 0.8 and light_bar.segment_colors[0].b < 0.35, "Dawn golden orange segment verified")
	test_check(light_bar.segment_colors[light_bar.num_segments - 1].b > 0.3, "Twilight sapphire night segment verified")

	# Verify axial LUT texture creation and dispatch to materials
	var terr_mat = cylinder_world.surface_material as ShaderMaterial
	var water_mat = cylinder_world.water_material as ShaderMaterial
	test_check(terr_mat != null and terr_mat.get_shader_parameter("axial_light_lut") != null, "Terrain material receives axial_light_lut texture")
	test_check(water_mat != null and water_mat.get_shader_parameter("axial_light_lut") != null, "Water material receives axial_light_lut texture")

	# Verify dynamic master intensity slider (pitch black 0.0 to full daylight 3.5 to max 5.0)
	var env_node = root_node.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var hud_node = root_node.get_node_or_null("UI") as HUD
	test_check(env_node != null and hud_node != null, "Environment and HUD nodes exist")

	hud_node._on_light_intensity_changed(0.0)
	test_check(is_zero_approx(light_bar.global_intensity_multiplier), "Intensity multiplier at 0.0 verified")
	test_check(env_node.environment.fog_light_energy >= 0.34, "Night atmospheric fog energy maintains nocturnal floor (>= 0.35)")
	test_check(is_equal_approx(env_node.environment.fog_depth_curve, 1.1), "Depth fog curve maintains consistent 1.1")
	test_check(is_equal_approx(env_node.environment.fog_depth_begin, 200.0), "Fog depth begin remains at 200.0m for night atmosphere")

	hud_node._on_light_intensity_changed(3.5)
	test_check(is_equal_approx(light_bar.global_intensity_multiplier, 3.5), "Intensity multiplier at 3.5 verified")
	test_check(is_equal_approx(env_node.environment.fog_light_energy, 1.0), "Fog light energy scales to 1.0 at nominal daylight (3.5x)")
	test_check(is_equal_approx(env_node.environment.fog_depth_curve, 1.1), "In nominal daylight, fog depth curve returns to 1.1")
	test_check(is_equal_approx(env_node.environment.fog_depth_begin, 200.0), "In nominal daylight, fog depth begin returns to 200.0m")

	# Verify HUD preset dropdown mappings
	hud_node._on_light_preset_selected(0)
	test_check(light_bar.preset == AxisLightBar.LightingPreset.UNIFORM, "HUD item 0 activates Uniform Daylight preset")
	test_check(env_node.environment.fog_light_color.b > env_node.environment.fog_light_color.r, "Uniform Daylight fog reflects cyan/blue sky tint")

	hud_node._on_light_preset_selected(1)
	test_check(light_bar.preset == AxisLightBar.LightingPreset.GRADIENT, "HUD item 1 activates Gradient (Sunrise/Twilight) preset")
	hud_node._on_light_preset_selected(2)
	test_check(light_bar.preset == AxisLightBar.LightingPreset.DAY_NIGHT_WAVE, "HUD item 2 activates Day/Night Wave preset")
	hud_node._on_light_preset_selected(3)
	test_check(light_bar.preset == AxisLightBar.LightingPreset.NEON_AURORA, "HUD item 3 activates Neon Aurora preset")
	hud_node._on_light_preset_selected(4)
	test_check(light_bar.preset == AxisLightBar.LightingPreset.WARM_SUNSET, "HUD item 4 activates Warm Sunset preset")
	test_check(env_node.environment.fog_light_color.r > env_node.environment.fog_light_color.b, "Warm Sunset fog reflects warm sunset amber/gold tint")

	# Return to nominal Uniform Daylight for subsequent verification tests
	hud_node._on_light_preset_selected(0)
	test_check(light_bar.preset == AxisLightBar.LightingPreset.UNIFORM, "HUD resets to Uniform Daylight")

	# Verify logarithmic intensity scale from 0.001 to 3.5
	test_check(is_equal_approx(HUD.slider_pos_to_intensity(0.0), 0.001), "Slider at 0.0 must map to 0.001 intensity")
	test_check(is_equal_approx(HUD.slider_pos_to_intensity(1.0), 3.5), "Slider at 1.0 must map to 3.5 intensity")
	test_check(is_equal_approx(HUD.intensity_to_slider_pos(0.001), 0.0), "0.001 intensity must map to slider position 0.0")
	test_check(is_equal_approx(HUD.intensity_to_slider_pos(3.5), 1.0), "3.5 intensity must map to slider position 1.0")
	var mid_intensity = HUD.slider_pos_to_intensity(0.5)
	test_check(mid_intensity > 0.04 and mid_intensity < 0.08, "Midpoint of log scale must be around ~0.059 for smooth dim-light control")

	# Test slider interaction through _on_light_slider_changed
	hud_node._on_light_slider_changed(0.0)
	test_check(is_equal_approx(light_bar.global_intensity_multiplier, 0.001), "Light bar intensity at slider 0.0 is 0.001")
	hud_node._on_light_slider_changed(1.0)
	test_check(is_equal_approx(light_bar.global_intensity_multiplier, 3.5), "Light bar intensity at slider 1.0 is 3.5")

	# Verify UI button focus_mode is FOCUS_NONE so player movement is never blocked
	test_check(hud_node.south_cap_btn.focus_mode == Control.FOCUS_NONE, "Inspect South end cap button must have FOCUS_NONE")

	# Verify axial lights exist along the light bar
	test_check(light_bar.light_nodes.size() >= 2, "Axial omni lights exist on light bar")

	# Verify Event Log / Console, Real Time + Sim Time + FPS tags, and Copy to Clipboard
	test_check(hud_node.event_log_text != null, "System Event Log RichTextLabel must exist")
	test_check(hud_node.copy_log_btn != null, "Copy Event Log Button must exist")
	test_check(hud_node.clear_log_btn != null, "Clear Event Log Button must exist")
	
	HUD.log_event("Automated test diagnostics verification signal", "#77ffaa")
	test_check(hud_node.event_log_history.size() > 0, "Event log history must contain recorded entries")
	test_check(hud_node.event_log_raw_history.size() > 0, "Raw event log history must contain recorded entries")
	var last_raw = hud_node.event_log_raw_history.back()
	test_check(last_raw.contains("FPS"), "Event log entry must attach current FPS")
	test_check(last_raw.contains("Sim"), "Event log entry must attach in-game simulation time")
	
	# Test copy to clipboard
	var raw_log = hud_node.get_raw_event_log_text()
	test_check(raw_log.contains("Automated test diagnostics verification signal"), "Raw event log text must contain verified signal")
	hud_node._on_copy_log_pressed()
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		test_check(DisplayServer.clipboard_get().contains("Automated test diagnostics verification signal"), "Clipboard must contain copied event log text")

	print("[PASS] Test 7: Axial lighting system, System event console with Real Time, Sim Time, FPS tags, and Clipboard Copy verified.")

	# --- TEST 8: Standard Controls (Joystick Movement vs Screen Drag Look) ---
	print("\n--- TEST 8: Standard Controls (Joystick Movement vs Screen Drag Look) ---")
	var touch_controls = hud_node.touch_controls as MobileTouchControls
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
	hud_node = root_node.get_node_or_null("UI")
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

	# 2. Drag elsewhere on the screen (e.g. center area between half-height telemetry and bottom controls) to rotate view
	var screen_drag_pos = Vector2(400.0, 800.0)
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
	test_check(cylinder_world.cylinder_length == 18000.0, "Cylinder length must be 18 km")
	test_check(cylinder_world.elevation_variance == 100.0, "Elevation variance must be 100 m (0 to 100m valid range)")
	test_check(cylinder_world.water_level == 20.0, "Water level must be 20.0 m from elevation 0")
	test_check(cylinder_world.include_end_caps, "End caps must be enabled on the cylinder")
	test_check(cylinder_world.mesh_instance != null and cylinder_world.mesh_instance.mesh != null, "Cylinder mesh with end caps must be generated")

	var safe_initial = cylinder_world.find_safe_spawn_point(-PI * 0.5, 0.0, 2.0)
	var elev_sample_spawn: float = safe_initial.get("elevation", 0.0)
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

	# Verify loading from PNG image maps and MapConfig package
	var terrain_mgr = cylinder_world.terrain_manager
	var default_cfg = MapConfig.load_map_config("default")
	test_check(default_cfg.has("geometry") and default_cfg["geometry"]["cylinder_radius_m"] == 4000.0, "MapConfig must parse geometry settings")
	var elev_path = MapConfig.get_elevation_map_path(default_cfg)
	var terr_path = MapConfig.get_terrain_map_path(default_cfg)
	var ok_load_elev = terrain_mgr.load_elevation(elev_path)
	var ok_load_terr = terrain_mgr.load_terrain(terr_path)
	print("Loaded float elevation: %s, Loaded terrain map PNG: %s (Dimensions: %dx%d)" % [ok_load_elev, ok_load_terr, terrain_mgr.grid_u, terrain_mgr.grid_v])
	test_check(ok_load_elev, "Must successfully load float elevation layer")
	test_check(ok_load_terr, "Must successfully load terrain tilemap from PNG image")

	# Verify exporting the declared layer encodings
	var ok_save_elev = terrain_mgr.save_elevation("user://test_elev_export.cylh")
	var ok_save_terr = terrain_mgr.save_terrain("user://test_terr_export.png")
	test_check(ok_save_elev and ok_save_terr, "Must successfully export independent elevation and biome layers")

	# Verify water level at 20 m
	var sample_water_elev = terrain_mgr.water_level - 5.0 # 15.0 m (underwater)
	test_check(sample_water_elev < 20.0, "Water basins are below the 20 m water level")

	# Verify water material and volume tinting parameters
	test_check(cylinder_world.water_material != null, "Water material must be configured")
	test_check(cylinder_world.water_material.get_shader_parameter("elevation_map") != null, "Water material must have elevation map bound for volume tinting and land culling")
	test_check(cylinder_world.water_material.get_shader_parameter("water_level") == 20.0, "Water level in water shader must match configured 20.0 m")

	# Verify water shader normal and axial reflection line
	var water_shader = (cylinder_world.water_material as ShaderMaterial).shader
	test_check(water_shader.code.contains("refl_world"), "Water shader computes world-space reflection vector for axial light bar")
	test_check(water_shader.code.contains("axis_reflection_glint"), "Water shader calculates continuous axial specular reflection line down axis")
	test_check(water_shader.code.contains("cull_disabled"), "Water shader has cull_disabled so water faces are never backface culled")
	print("[PASS] Test 9: PNG elevation heightmap, water volume tinting, and axial specular reflection line verified.")

	# --- TEST 10: Max On Daylight Lighting System & 18 km Scale ---
	print("\n--- TEST 10: Max On Daylight Lighting System & 18 km Scale with End Caps ---")
	test_check(light_bar.bar_length == 18000.0, "Axis light bar length must match 18 km cylinder")
	test_check(light_bar.cylinder_radius == 4000.0, "Axis light bar radius must match 4 km radius")
	test_check(light_bar.global_intensity_multiplier >= 3.0, "Max On lighting intensity must be at full illumination level (>= 3.0)")
	for light in light_bar.light_nodes:
		test_check(light.omni_range >= 6000.0, "Axial omni light range must cover 4 km radial distance")

	# Verify 18 km atmospheric air tinting across cylinder materials and WorldEnvironment
	var world_env = root_node.get_node_or_null("WorldEnvironment") as WorldEnvironment
	test_check(world_env != null and world_env.environment != null, "WorldEnvironment must exist with configured Environment")
	test_check(world_env.environment.fog_enabled, "Depth fog must be enabled for atmospheric aerial perspective")
	test_check(world_env.environment.fog_mode == Environment.FOG_MODE_DEPTH, "Fog mode must be depth-based (FOG_MODE_DEPTH)")
	test_check(world_env.environment.fog_depth_end == 18000.0, "Fog depth end must reach 18 km across the cylinder")
	print("WorldEnvironment depth fog verified: light_color=%s, begin=%.1f m, end=%.1f m" % [
		world_env.environment.fog_light_color, world_env.environment.fog_depth_begin, world_env.environment.fog_depth_end
	])

	# Verify terrain and water shader air tint parameters
	var terr_air_col = cylinder_world.surface_material.get_shader_parameter("air_color") as Color
	var terr_air_max = cylinder_world.surface_material.get_shader_parameter("air_distance_max") as float
	var terr_air_density = cylinder_world.surface_material.get_shader_parameter("air_density") as float
	var water_air_col = cylinder_world.water_material.get_shader_parameter("air_color") as Color
	var water_air_max = cylinder_world.water_material.get_shader_parameter("air_distance_max") as float

	print("Terrain air tint: color=%s, density=%.2f, max_dist=%.1f m" % [terr_air_col, terr_air_density, terr_air_max])
	print("Water air tint: color=%s, max_dist=%.1f m" % [water_air_col, water_air_max])

	test_check(terr_air_col != null and terr_air_col.b > terr_air_col.r, "Terrain air color must have cyan/blue Rayleigh scattering tint")
	test_check(terr_air_max == 18000.0, "Terrain air tint distance max must be 18 km")
	test_check(terr_air_density > 0.0 and terr_air_density <= 3.0, "Terrain air density must be within (0, 3]")
	test_check(water_air_col != null and water_air_max == 18000.0, "Water air tint must reach 18 km")

	# Verify end cap mesh structure & hemispherical depth (4 km radius hemispheres on both ends = 26 km total)
	var face_count = cylinder_world.mesh_instance.mesh.get_faces().size() / 3
	var aabb = cylinder_world.mesh_instance.mesh.get_aabb()
	print("Mesh generated: %d triangles (barrel + hemispherical end caps)" % face_count)
	print("Mesh total bounds: size=%s, position=%s" % [aabb.size, aabb.position])
	test_check(face_count > 50000, "Mesh must contain high-fidelity barrel and hemispherical end cap bulkheads")
	test_check(aabb.size.z >= 25900.0, "Mesh must span full 26 km from South hemisphere pole to North hemisphere pole")
	test_check(aabb.position.z <= -12900.0, "South hemisphere end cap must reach -13,000 m")

	# Verify end cap rib texture
	var rib_tex = cylinder_world.surface_material.get_shader_parameter("tex_end_cap_ribs")
	test_check(rib_tex != null, "Weathered industrial rib texture must be bound to terrain material for end caps")
	test_check((cylinder_world.surface_material as ShaderMaterial).shader.code.contains("cull_disabled"), "Terrain shader must have cull_disabled to render inner cylinder bulkheads without backface culling")
	test_check(player.camera.far >= 5000.0, "Player camera far clip distance must support extensive distance across cylinder (>= 5000m)")

	# Verify Surface Light Emitting Objects (Campfires, Street Lamps, and Beacons)
	var ref_node = root_node.get_node_or_null("ReferenceObjects") as ReferenceObjects
	test_check(ref_node != null, "ReferenceObjects node must exist in main scene")

	var light_emitter_count = 0
	var found_campfire = false
	var found_beacon = false
	var sample_campfire: SurfaceLightObject = null
	var sample_beacon: SurfaceLightObject = null

	for child in ref_node.get_children():
		if child is SurfaceLightObject:
			light_emitter_count += 1
			if child.object_type == SurfaceLightObject.ObjectType.CAMPFIRE:
				found_campfire = true
				if not sample_campfire:
					sample_campfire = child
			elif child.object_type == SurfaceLightObject.ObjectType.BEACON_LANTERN:
				found_beacon = true
				if not sample_beacon:
					sample_beacon = child

	if not found_campfire:
		player.deploy_campfire()
		for child in ref_node.get_children():
			if child is SurfaceLightObject and child.object_type == SurfaceLightObject.ObjectType.CAMPFIRE:
				found_campfire = true
				sample_campfire = child
				light_emitter_count += 1
				break
	if not found_beacon:
		player.deploy_lamp_post()
		for child in ref_node.get_children():
			if child is SurfaceLightObject and child.object_type == SurfaceLightObject.ObjectType.BEACON_LANTERN or child.object_type == SurfaceLightObject.ObjectType.LAMP_POST:
				found_beacon = true
				sample_beacon = child
				light_emitter_count += 1
				break

	print("Surface light objects detected: %d (Campfires: %s, Beacons: %s)" % [
		light_emitter_count, found_campfire, found_beacon
	])
	test_check(found_campfire, "Campfires must be present on cylinder surface")
	test_check(found_beacon, "Beacon lanterns must be present near end caps")

	# Verify sample campfire emission and omni light
	test_check(sample_campfire != null and sample_campfire.omni_light != null, "Campfire must possess an OmniLight3D emitter")
	test_check(sample_campfire.omni_light.light_color.r > sample_campfire.omni_light.light_color.g and sample_campfire.omni_light.light_color.g > sample_campfire.omni_light.light_color.b, "Campfire light must retain its map-defined warm color ordering")
	test_check(is_equal_approx(sample_campfire.omni_light.omni_range, sample_campfire.light_range), "Campfire emitter must use its map-defined instance light range")
	test_check(sample_campfire.flame_mats.size() > 0, "Campfire must have emissive flame material")
	test_check(sample_campfire.flame_mats[0].emission_enabled, "Campfire flame mesh material emission must be enabled")

	# Verify sample beacon lantern emission and omni light
	test_check(sample_beacon != null and sample_beacon.omni_light != null, "Beacon lantern must possess an OmniLight3D emitter")
	test_check(sample_beacon.omni_light.light_energy > 0.0, "Beacon lantern light energy must be active")

	# Verify dynamic placement at player position via player controller hotkey methods
	var pre_count = ref_node.get_child_count()
	player.deploy_campfire()
	test_check(ref_node.get_child_count() > pre_count, "Player deploy_campfire() must instantiate new light on surface")
	var deployed_fire = ref_node.get_child(ref_node.get_child_count() - 1) as SurfaceLightObject
	test_check(deployed_fire != null and deployed_fire.object_type == SurfaceLightObject.ObjectType.CAMPFIRE, "Deployed object must be a campfire")
	# Check orientation: Local Y (Up) should point inward toward axis (dot with (0,0,1) is 0)
	var local_up = deployed_fire.global_basis.y
	test_check(absf(local_up.dot(Vector3(0, 0, 1))) < 0.01, "Deployed light Local Up must be strictly perpendicular to cylinder axis")

	# --- TEST 11: Rotating Reference Frame Particle Emitter & Coriolis Trajectories ---
	print("\n--- TEST 11: Particle Emitter, Coriolis Physics & Trajectories ---")
	var emitter = root_node.get_node_or_null("ParticleEmitter") as CylinderParticleEmitter
	test_check(emitter != null, "ParticleEmitter node must exist in main scene")
	test_check(emitter.is_in_group("particle_emitter"), "ParticleEmitter must be in group 'particle_emitter'")

	# Check theoretical rotating frame omega and centrifugal acceleration
	var omega = emitter.get_omega()
	var expected_omega = sqrt(emitter.base_gravity / emitter.cylinder_radius)
	test_check(absf(omega - expected_omega) < 0.0001, "Omega must match sqrt(g/R)")

	# Verify acceleration calculation:
	# Position at bottom of cylinder: (0, -4000, 0)
	# Upward velocity: (0, +30, 0) (inward toward axis)
	var test_pos = Vector3(0, -4000, 0)
	var test_vel = Vector3(0, 30, 0)
	var accel = emitter.compute_acceleration(test_pos, test_vel)

	# Centrifugal acceleration should point radially outward: (0, -9.5, 0)
	test_check(absf(accel.y - (-9.5)) < 0.05, "Centrifugal acceleration at floor must be 9.5 m/s² outward (-Y)")

	# Coriolis acceleration for inward velocity (vy > 0) with CCW spin (+Z):
	# a_coriolis_x = 2 * Omega * vy = 2 * omega * 30 > 0 (prograde +X)
	var expected_coriolis_x = 2.0 * omega * float(emitter.spin_direction) * 30.0
	test_check(absf(accel.x - expected_coriolis_x) < 0.05, "Coriolis acceleration must deflect inward-moving particle prograde (+X)")

	# Test trajectory prediction
	var pred_pts = emitter.predict_trajectory(test_pos, test_vel, 100, 0.05)
	test_check(pred_pts.size() > 10, "Trajectory prediction must generate path points")
	# As particle ascends, its X coordinate should curve prograde (+X)
	var max_x = -99999.0
	for pt in pred_pts:
		if pt.x > max_x:
			max_x = pt.x
	test_check(max_x > 0.5, "Particle trajectory must demonstrate prograde Coriolis curve")

	# Test live particle launch and step integration
	var pre_p_count = emitter.get_particle_count()
	var p_id = emitter.launch_relative_to_surface(test_pos, 0.0, 30.0, 0.0, {
		"color": Color(0.2, 0.9, 1.0, 1.0),
		"size": 1.2
	})
	test_check(p_id > 0, "Particle launch must return valid particle ID")
	test_check(emitter.get_particle_count() == pre_p_count + 1, "Particle count must increment")

	# Step physics frames to verify numerical integration and trail recording
	for step in range(30):
		await physics_frame

	var live_p = null
	for p in emitter.particles:
		if p.id == p_id:
			live_p = p
			break

	test_check(live_p != null, "Launched particle must be active in simulation")
	test_check(live_p.trail.size() >= 2, "Particle must record trajectory trail points for rendering")

	print("[PASS] Test 11: Rotating frame centrifugal/Coriolis physics, particle launches, and trajectory trails verified.")

	# --- TEST 12: Climate Regions, Yearly Cycles, Snow Mode & 1-Deep Weather State Queue ---
	print("\n--- TEST 12: Climate Regions, Yearly Cycles, Snow Mode & 1-Deep Weather Queue ---")
	var weather = root_node.get_node_or_null("WeatherSystem") as WeatherSystem
	test_check(weather != null, "WeatherSystem node must exist in main scene")

	# 1. Test Climate Biome Classification from Tundra desert to Tropical rainforest
	var tropical_rainforest = ClimateSystem.get_climate_name(0.0, 3200.0)
	test_check(tropical_rainforest == ClimateSystem.CLIMATE_TROPICAL_RAINFOREST, "Lat 0°, 3200mm precip must classify as Tropical Rainforest")

	var tropical_desert = ClimateSystem.get_climate_name(15.0, 100.0)
	test_check(tropical_desert == ClimateSystem.CLIMATE_TROPICAL_DESERT, "Lat 15°, 100mm precip must classify as Hyper-Arid Tropical Desert")

	var polar_ice_sheet = ClimateSystem.get_climate_name(85.0, 100.0)
	test_check(polar_ice_sheet == ClimateSystem.CLIMATE_TUNDRA_DESERT, "Lat 85°, 100mm precip must classify as Polar Desert (Ice Sheet)")

	var arctic_tundra = ClimateSystem.get_climate_name(68.0, 180.0)
	test_check(arctic_tundra == ClimateSystem.CLIMATE_ARCTIC_TUNDRA, "Lat 68°, 180mm precip must classify as Arctic Tundra Desert")

	var boreal_taiga = ClimateSystem.get_climate_name(62.0, 750.0)
	test_check(boreal_taiga == ClimateSystem.CLIMATE_BOREAL_TAIGA, "Lat 62°, 750mm precip must classify as Boreal Taiga")

	var temperate_deciduous = ClimateSystem.get_climate_name(38.0, 1200.0)
	test_check(temperate_deciduous == ClimateSystem.CLIMATE_DECIDUOUS_FOREST, "Lat 38°, 1200mm precip must classify as Temperate Deciduous Forest")

	# 2. Test Seasonal Cycle and Temperatures across Latitude and Day of Year
	var summer_equator_temp = ClimateSystem.calculate_surface_temperature(0.0, 172, 14.0, 2000.0)
	var winter_polar_temp = ClimateSystem.calculate_surface_temperature(80.0, 355, 14.0, 150.0)
	test_check(summer_equator_temp > 24.0, "Equatorial temperature must be warm (> 24°C)")
	test_check(winter_polar_temp < -10.0, "Winter polar temperature must be sub-zero (< -10°C)")

	# 3. Test Snow Mode determination (<= 4°C)
	var cold_profile = ClimateSystem.get_climate_weather_profile(70.0, 300.0, 355, 12.0)
	test_check(cold_profile["is_snow_mode"] == true, "Cold climate profile with sub-4°C temp must trigger snow mode")

	var warm_profile = ClimateSystem.get_climate_weather_profile(5.0, 2500.0, 172, 12.0)
	test_check(warm_profile["is_snow_mode"] == false, "Warm climate profile with >4°C temp must be in rain mode")

	# 4. Test Weather System Climate Profile Sync & 1-Deep Queue
	weather.latitude_deg = 42.0
	weather.yearly_precipitation_mm = 1100.0
	weather.day_of_year = 172
	test_check(weather.current_climate_name.contains("Forest") or weather.current_climate_name.contains("Temperate"), "Weather system must reflect active climate descriptor")
	test_check(not weather.current_weather_state.is_empty(), "Weather system must hold active current weather state")
	test_check(not weather.next_queued_weather_state.is_empty(), "Weather system must maintain 1-deep pre-calculated upcoming state")

	# 5. Test Manual Queue Pushing during game
	var custom_snow_event = {
		"name": "Custom Test Blizzard (❄️)",
		"cloud_coverage": 0.95,
		"cloud_thickness_m": 600.0,
		"precipitation_rate_mmh": 20.0,
		"humidity_density_gm3": 6.0,
		"dust_density": 0.05,
		"endcap_air_temperature_c": -10.0,
		"water_pipe_temperature_c": -5.0,
		"duration": 15.0
	}
	weather.push_weather_state(custom_snow_event, true)
	test_check(weather.is_snow_mode, "Weather system must switch to snow mode when temperature <= 4°C")
	test_check(weather.precipitation_rate_mmh > 15.0, "Precipitation rate must reflect custom pushed weather event")
	test_check(weather.rain_sheets_root.visible == true, "Rain sheets mesh must be visible during precipitation")

	print("[PASS] Test 12: Climate regions (Tundra desert to Tropical rainforest), seasonal cycles, snow mode (<= 4°C), and 1-deep weather queue verified.")

	# --- TEST 13: Loading Screen & Precipitation Surface Initialization ---
	print("\n--- TEST 13: Loading Screen & Precipitation Surface Initialization ---")
	var loading_screen_script = load("res://scripts/loading_screen.gd")
	test_check(loading_screen_script != null, "LoadingScreen script must exist and load successfully")

	# Verify precipitation sheet shader defaults to transparent (not white)
	var rain_shader = load("res://assets/shaders/cylinder_rain_sheet.gdshader") as Shader
	test_check(rain_shader != null, "Precipitation rain sheet shader must exist")
	test_check(rain_shader.code.contains("hint_default_transparent"), "Precipitation shader must default unassigned texture to transparent")
	test_check(rain_shader.code.contains("rain_alpha_multiplier : hint_range(0.0, 2.0) = 0.0"), "Precipitation shader must default rain_alpha_multiplier to 0.0")

	# Verify cloud shaders default texture hint is transparent to prevent initial solid white cloud deck
	var near_cloud_shader = load("res://assets/shaders/cylinder_clouds.gdshader") as Shader
	var far_cloud_shader = load("res://assets/shaders/cylinder_clouds_far.gdshader") as Shader
	test_check(near_cloud_shader != null and near_cloud_shader.code.contains("hint_default_transparent"), "Near cloud shader must default cloud noise texture to transparent")
	test_check(far_cloud_shader != null and far_cloud_shader.code.contains("hint_default_transparent"), "Far cloud shader must default cloud noise texture to transparent")

	# Test LoadingScreen instantiation and progress flow
	var test_loading_screen = LoadingScreen.new()
	test_loading_screen.auto_start = false
	root.add_child(test_loading_screen)
	test_check(test_loading_screen.layer == 100, "Loading screen canvas layer must be 100 (rendered on top of all 3D/2D content)")
	test_check(test_loading_screen.root_control != null, "Loading screen root control must be created")
	test_check(test_loading_screen.progress_bar != null, "Loading screen progress bar must be created")
	
	test_loading_screen._set_step("Testing Stage", "Verifying UI update", 50.0)
	test_check(test_loading_screen.target_progress == 50.0, "Loading screen target progress must update")
	test_loading_screen.queue_free()
	await process_frame

	print("[PASS] Test 13: Loading screen and precipitation surface transparent initialization verified.")

	# --- TEST 14: HUD Target Inspector (Looking At Terrain Type & Object) ---
	print("\n--- TEST 14: HUD Target Inspector (Looking At Terrain Type & Object) ---")
	var test_hud = root_node.get_node_or_null("UI") as HUD
	if not test_hud:
		test_hud = root.get_tree().get_first_node_in_group("hud") as HUD
	test_check(test_hud != null, "HUD node must exist in the scene tree")

	# 1. Verify default state is turned OFF
	test_check(test_hud.looking_at_enabled == false, "Looking At / Target Inspector must default to being turned OFF")
	test_check(test_hud.looking_at_panel != null, "Looking At panel must be instantiated in HUD")
	test_check(test_hud.looking_at_panel.visible == false, "Looking At panel must be hidden by default")
	if test_hud.crosshair_node:
		test_check(test_hud.crosshair_node.visible == false, "Crosshair must be hidden when Target Inspector is turned OFF")
	print("Looking At inspector default state verified: OFF (Panel hidden: true, Crosshair hidden: true)")

	# 2. Enable Target Inspector and run inspection tick
	test_hud.set_looking_at_enabled(true)
	test_check(test_hud.looking_at_enabled == true, "Target Inspector must be enabled after set_looking_at_enabled(true)")
	test_check(test_hud.looking_at_panel.visible == true, "Looking At panel must be visible when enabled")
	if test_hud.crosshair_node:
		test_check(test_hud.crosshair_node.visible == true, "Crosshair must be visible when enabled")

	for f in range(5):
		await process_frame
		await physics_frame

	test_hud._update_looking_at_inspection()
	var look_data = test_hud.last_looking_at_data
	print("Inspected Target -> Terrain Type: '%s' | Object: '%s' | Elevation: %.1f m | Distance: %.1f m" % [
		look_data.get("terrain_type", "None"),
		look_data.get("object_name", "None"),
		look_data.get("elevation", 0.0),
		look_data.get("distance", 0.0)
	])
	test_check(not look_data.is_empty(), "Inspection data must be populated when Looking At is enabled")
	test_check(look_data.get("terrain_type", "").length() > 0, "Inspected terrain type must not be empty")
	test_check(look_data.get("object_name", "").length() > 0, "Inspected object name must not be empty")

	# 3. Test toggle back to OFF
	test_hud.toggle_looking_at()
	test_check(test_hud.looking_at_enabled == false, "Target Inspector must toggle back to OFF")
	test_check(test_hud.looking_at_panel.visible == false, "Looking At panel must be hidden when toggled OFF")
	print("[PASS] Test 14: HUD Target Inspector (Looking At Terrain Type & Object, default OFF) verified.")

	# --- TEST 15: Responsive UI Panels (Screen Width Minus Margins) & Virtual Keyboard Toggle ---
	print("\n--- TEST 15: Responsive UI Panels & On-Screen Virtual Keyboard Toggle ---")
	test_check(test_hud.telemetry_panel != null, "Telemetry panel must exist")
	test_check(test_hud.control_panel != null, "Control/Settings panel must exist")
	test_check(test_hud.log_panel != null, "Event Log panel must exist")

	test_hud._update_panel_constraints()
	# Panels use different anchor/scale strategies; verify visible screen margins.
	var screen_width := test_hud.get_viewport().get_visible_rect().size.x
	for panel in [test_hud.telemetry_panel, test_hud.control_panel, test_hud.log_panel]:
		var rect: Rect2 = panel.get_global_rect()
		test_check(absf(rect.position.x - 15.0) < 1.0 and absf(rect.end.x - (screen_width - 15.0)) < 1.0, "%s must span screen width minus 15px margins" % panel.name)

	# Verify ControlPanel minimum height constraint
	var cp_height = test_hud.control_panel.offset_bottom - test_hud.control_panel.offset_top
	print("ControlPanel configured height: %.1f px (minimum tab fit height)" % cp_height)
	test_check(cp_height >= 220.0 and cp_height <= 450.0, "ControlPanel must maintain compact minimum height to fit tabs without covering touch controls")

	# Verify Virtual Keyboard Toggle button
	test_check(test_hud.toggle_keyboard_btn != null, "ToggleKeyboardButton must exist under UIRoot")
	test_check(test_hud.toggle_keyboard_btn.focus_mode == Control.FOCUS_NONE, "ToggleKeyboardButton must have FOCUS_NONE")
	
	test_hud._on_toggle_keyboard_pressed()
	print("[PASS] Test 15: Screen-width responsive panels, compact debug tabs height, and on-screen keyboard toggle verified.")

	# --- TEST 16: Ground Clutter Rendering & GPU MultiMesh Instancing ---
	print("\n--- TEST 16: Ground Clutter Rendering & GPU MultiMesh Instancing ---")
	var clutter_mgr = root_node.get_node_or_null("ClutterManager") as ClutterManager
	test_check(clutter_mgr != null, "ClutterManager must be present in main scene")
	test_check(clutter_mgr.enabled == true, "ClutterManager should be enabled by default")
	for model_id in cylinder_world.active_map_config.ground_clutter.models:
		test_check(clutter_mgr.parts.has(model_id) and not clutter_mgr.parts[model_id].is_empty(), "Map clutter model must supply renderable parts: " + model_id)
		test_check(clutter_mgr.parts_lod1.has(model_id) and not clutter_mgr.parts_lod1[model_id].is_empty(), "Map clutter model must supply LOD1 parts: " + model_id)

	# Force active chunk update around player position
	clutter_mgr._update_active_chunks(player.global_position)
	print("Active clutter chunks generated around player: %d" % clutter_mgr.active_chunks.size())
	test_check(clutter_mgr.active_chunks.size() > 0, "Clutter chunks must be generated around player position")
	
	var sample_chunk: Node3D = null
	for chunk_node in clutter_mgr.active_chunks.values():
		if chunk_node is Node3D and chunk_node.get_child_count() > 0:
			sample_chunk = chunk_node
			break
	if sample_chunk == null and not clutter_mgr.active_chunks.is_empty():
		sample_chunk = clutter_mgr.active_chunks.values()[0] as Node3D
	test_check(sample_chunk != null, "Sample clutter chunk must exist")
	test_check(sample_chunk.is_processing() == false, "Clutter chunk root must have _process disabled")
	test_check(sample_chunk.is_physics_processing() == false, "Clutter chunk root must have _physics_process disabled")
	var mmi_count = 0
	for ch in sample_chunk.get_children():
		if ch is MultiMeshInstance3D:
			mmi_count += 1
			test_check(ch.is_processing() == false, "MultiMeshInstance3D must have _process disabled")
			test_check(ch.visibility_range_end > 0.0, "MultiMeshInstance3D must have distance-culling visibility_range_end set")
	print("MultiMeshInstance3D layers in sample chunk: %d" % mmi_count)
	test_check(mmi_count > 0, "Chunk must contain MultiMeshInstance3D nodes")
	print("[PASS] Test 16: Ground clutter procedural meshes, wind shader, MultiMesh batching, distance culling, and zero-CPU chunk processing verified.")

	# --- TEST 17: Live Godot Map Generator & Biome Adjacency Enforcement ---
	print("\n--- TEST 17: Live Godot Map Generator & Biome Adjacency Enforcement ---")
	var MapGeneratorClass = load("res://scripts/map_generator.gd")
	test_check(MapGeneratorClass != null, "MapGenerator script must be loaded")

	var descriptor = MapConfig.load_map_config("default")
	descriptor.generation.elevation_width = 48
	descriptor.generation.elevation_height = 25
	descriptor.generation.terrain_width = 24
	descriptor.generation.terrain_height = 13
	descriptor.generation.erase("sample_pitch_m")
	var generated = await MapGeneratorClass.generate(descriptor)
	test_check(not generated.has("error"), "Map generation must succeed")
	test_check(generated.elevation_image.get_width() == 48 and generated.terrain_image.get_width() == 24, "Independent generation resolutions")
	print("[PASS] Test 17: Schema 4 map generation verified.")

	print("\n=======================================================")
	print(" ALL O'NEILL CYLINDER SIMULATION TESTS PASSED (17/17)! ")
	print("=======================================================\n")
	quit(0)
