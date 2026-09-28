class_name PlayerController
extends CharacterBody3D

const CylinderParticleEmitter = preload("res://scripts/cylinder_particle_emitter.gd")

signal telemetry_updated(data: Dictionary)

@export_category("Cylinder Dimensions (8 km dia x 18 km length)")
@export var cylinder_radius: float = 4000.0
@export var cylinder_length: float = 18000.0

@export_category("Movement & Gravity")
@export var walk_speed: float = 3.2
@export var sprint_speed: float = 7.2
@export var fly_speed: float = 75.0
@export var acceleration: float = 18.0
@export var air_control: float = 5.0
@export var base_gravity: float = 9.5
@export var jump_velocity: float = 6.2
@export var max_walkable_slope_deg: float = 45.0
@export var horizon_alignment_speed: float = 20.0
@export var attitude_flatten_speed: float = 3.0

@export_category("Wobble Dynamics")
@export var wobble_frequency_min: float = 1.0
@export var wobble_frequency_max: float = 16.0
@export var wobble_damping_min: float = 0.25
@export var wobble_damping_max: float = 1.0

@export_category("Mouse Look")
@export var mouse_sensitivity: float = 0.0025
@export var touch_sensitivity: float = 0.004

@export_category("Spawn Location")
@export var preferred_spawn_theta: float = -PI * 0.5
@export var preferred_spawn_z: float = 0.0
@export var min_elevation_above_sea: float = 2.0

var is_flying: bool = false
var is_sprinting: bool = true
var mobile_sprint_active: bool = true

# Jump and vertical kinematics
var vertical_velocity: float = 0.0
var jump_cooldown_timer: float = 0.0

# Virtual input state (for keyboard or mobile touch controls)
var input_axis: Vector2 = Vector2.ZERO
var joystick_override: bool = false
var fly_vertical_axis: float = 0.0
var jump_requested: bool = false

# Active look tracking
var look_control_timer: float = 0.0

# Wobble / Horizon roll state
var wobble_roll: float = 0.0        # Radians (left/right tilt)
var wobble_velocity: float = 0.0    # Angular velocity (rad/s)
var stride_phase: float = 0.0       # Phase for footstep roll sway

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# Internal look angles
var pitch: float = 0.0

func _ready() -> void:
	# Standard drag / touch controls: default mouse to visible so dragging anywhere on screen rotates
	# and dragging the virtual joystick moves only
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Ensure camera far distance covers the 18 km cylinder and end caps (30 km total)
	if camera:
		camera.near = 0.2
		camera.far = 40000.0

	# Collision recovery across terrain seams and 26 km end cap dishes
	safe_margin = 0.08
	max_slides = 6
	floor_snap_length = 0.15
	floor_max_angle = deg_to_rad(max_walkable_slope_deg)
	floor_constant_speed = true
	floor_stop_on_slope = true
	floor_block_on_wall = true
	wall_min_slide_angle = 0.0

	# Spawn accurately onto inner cylinder terrain
	reset_to_spawn()

func _input(event: InputEvent) -> void:
	# Traditional PC mouse look only active if mouse is explicitly captured
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look_input(Vector2(event.relative.x, event.relative.y) * mouse_sensitivity)

	# Toggle mouse capture with ESC or F1
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_F1):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Toggle fly mode
	if event.is_action_pressed("fly_toggle"):
		toggle_fly_mode()

	# Reset position
	if event.is_action_pressed("reset_position"):
		reset_to_spawn()

	# Hotkeys: T (wobble test), C (deploy campfire), L (deploy lamp post), P (launch particle), G (vertical toss), I (toggle target inspector)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			wobble_impulse(22.0)
		elif event.keycode == KEY_I:
			var hud = get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
			if hud and hud.has_method("toggle_looking_at"):
				hud.toggle_looking_at()
		elif event.keycode == KEY_C and not is_flying:
			deploy_campfire()
		elif event.keycode == KEY_L:
			deploy_lamp_post()
		elif event.keycode == KEY_P:
			launch_aimed_particle()
		elif event.keycode == KEY_G:
			launch_vertical_particle()

	# Movement key release
	if event.is_action_released("move_forward") or event.is_action_released("move_backward") or event.is_action_released("move_left") or event.is_action_released("move_right"):
		if not (Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_backward") or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")):
			if not joystick_override:
				input_axis = Vector2.ZERO

func apply_look_input(delta_look: Vector2) -> void:
	look_control_timer = 0.5 # Actively controlling look angles

	# Yaw: rotate player around local Up axis
	rotate_object_local(Vector3.UP, -delta_look.x)

	# Pitch: rotate camera head around local X axis
	pitch = clampf(pitch - delta_look.y, -deg_to_rad(85.0), deg_to_rad(85.0))
	head.rotation.x = pitch

func wobble_impulse(amount_deg: float = 20.0) -> void:
	# Inject roll perturbation to demonstrate horizon self-righting
	var rad = deg_to_rad(amount_deg)
	wobble_velocity += rad * 12.0
	wobble_roll += rad * 0.5
	wobble_roll = clampf(wobble_roll, -deg_to_rad(45.0), deg_to_rad(45.0))

func get_locomotion_state() -> String:
	if is_flying:
		return "FLYING"
	if not is_on_floor() or jump_cooldown_timer > 0.0:
		var v_up = velocity.dot(global_basis.y)
		return "JUMPING" if v_up > 0.3 else "FALLING"
	if is_sprinting and velocity.length() > 0.5:
		return "RUNNING"
	if velocity.length() > 0.5:
		return "WALKING"
	return "IDLE"

func _physics_process(delta: float) -> void:
	_update_input()
	_update_horizon_and_gravity(delta)

	if is_flying:
		_process_flying_movement(delta)
	else:
		_process_ground_movement(delta)

	move_and_slide()

	if not is_flying and is_on_floor() and jump_cooldown_timer <= 0.0:
		if input_axis.length_squared() < 0.01:
			velocity = -global_basis.y * 0.5
		else:
			_perform_step_glide(delta)

	_enforce_surface_and_habitat_bounds()

	_emit_telemetry(delta)

func _enforce_surface_and_habitat_bounds() -> void:
	var cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null
	if not cyl_world and get_parent():
		cyl_world = get_parent().get_node_or_null("CylinderWorld")

	var theta = atan2(global_position.y, global_position.x)
	var z = global_position.z
	var elev = 0.0
	if cyl_world and cyl_world.has_method("get_elevation_at"):
		elev = cyl_world.get_elevation_at(theta, z)

	var surface_r = cylinder_radius - elev
	var player_xy = Vector2(global_position.x, global_position.y)
	var current_r = player_xy.length()
	var max_allowed_r = surface_r - 0.90 # Player half-height 0.925m (prevents floor penetration)

	var half_len = cylinder_length * 0.5
	var abs_z = absf(z)

	# 1. End Cap Hemispherical Bulkhead containment (z < -half_len or z > half_len)
	if abs_z > half_len:
		var delta_z = abs_z - half_len
		var dome_dist = sqrt(current_r * current_r + delta_z * delta_z)
		var max_dome_r = cylinder_radius - 0.90
		if dome_dist > max_dome_r and dome_dist > 0.01:
			var scale_f = max_dome_r / dome_dist
			var clamped_xy = player_xy * scale_f
			global_position.x = clamped_xy.x
			global_position.y = clamped_xy.y
			global_position.z = (half_len + delta_z * scale_f) * (1.0 if z > 0.0 else -1.0)
			return

	# 2. Cylindrical terrain floor containment (failsafe: only if player has fallen deep through collision mesh or is flying)
	if not is_on_floor() or is_flying:
		var max_failsafe_r = surface_r - 0.70
		if current_r > max_failsafe_r:
			if current_r > 0.01:
				var clamped_xy = player_xy.normalized() * max_failsafe_r
				global_position.x = clamped_xy.x
				global_position.y = clamped_xy.y
				var inward_up = -Vector3(player_xy.x, player_xy.y, 0.0).normalized()
				var outward_vel = -velocity.dot(inward_up)
				if outward_vel > 0.0:
					velocity += inward_up * outward_vel

func _update_input() -> void:
	# Keyboard input
	var forward = Input.get_action_strength("move_forward")
	var back = Input.get_action_strength("move_backward")
	var left = Input.get_action_strength("move_left")
	var right = Input.get_action_strength("move_right")

	var kb_axis = Vector2(right - left, back - forward)
	if kb_axis.length_squared() > 0.01:
		input_axis = kb_axis.normalized()

	# Sprint: Shift key on keyboard, or mobile sprint toggle
	is_sprinting = Input.is_action_pressed("sprint") or mobile_sprint_active

	var up_str = Input.get_action_strength("fly_up")
	var down_str = Input.get_action_strength("fly_down")
	if abs(up_str - down_str) > 0.01:
		fly_vertical_axis = up_str - down_str

	if Input.is_action_just_pressed("jump"):
		jump_requested = true

func _update_horizon_and_gravity(delta: float) -> void:
	# Cylinder axis is Z axis (x=0, y=0).
	# Radial vector from axis to player in XY plane:
	var radial = Vector3(global_position.x, global_position.y, 0.0)
	var dist_from_axis = radial.length()

	# Gravity falls off to zero at the axis: g(r) = base_g * (r / R)
	var gravity_factor = clampf(dist_from_axis / cylinder_radius, 0.0, 1.0)
	var current_gravity = base_gravity * gravity_factor

	# Up direction: points towards the axis (inward from curved surface, strictly perpendicular to Z axis)
	var target_up: Vector3
	if dist_from_axis > 0.05:
		target_up = -radial.normalized()
	else:
		# Microgravity core near axis; keep current up
		target_up = global_basis.y

	# Alignment speed scales with gravity:
	# High gravity firmly locks Up perpendicular to axis; zero-g allows drift
	var effective_align_speed = lerpf(2.0, horizon_alignment_speed, gravity_factor)
	var current_up = global_basis.y
	var rot_axis = current_up.cross(target_up)
	var rot_angle = current_up.angle_to(target_up)

	if rot_axis.length_squared() > 1e-7 and rot_angle > 1e-5:
		var q_align = Quaternion(rot_axis.normalized(), rot_angle)
		var blend = clampf(effective_align_speed * delta, 0.0, 1.0)
		var q_step = Quaternion.IDENTITY.slerp(q_align, blend)
		global_basis = Basis(q_step) * global_basis
		global_basis = global_basis.orthonormalized()

	# Set CharacterBody3D up_direction so floor detection is accurate all 360 deg
	up_direction = global_basis.y

	# --- Wobble Dynamics & Self-Righting to Perpendicular ---
	var omega_n = lerpf(wobble_frequency_min, wobble_frequency_max, gravity_factor)
	var zeta = lerpf(wobble_damping_min, wobble_damping_max, gravity_factor)
	var k_spring = omega_n * omega_n
	var c_damp = 2.0 * zeta * omega_n

	# Harmonic oscillator: d2phi/dt2 = -k*phi - c*dphi/dt
	var wobble_accel = -k_spring * wobble_roll - c_damp * wobble_velocity
	wobble_velocity += wobble_accel * delta
	wobble_roll += wobble_velocity * delta
	wobble_roll = clampf(wobble_roll, -deg_to_rad(45.0), deg_to_rad(45.0))

	# --- Look and Wobble Damping ---
	if look_control_timer > 0.0:
		look_control_timer = maxf(0.0, look_control_timer - delta)

	# Apply roll wobble / attitude to camera head (pitch is strictly controlled by player look input)
	head.rotation.z = wobble_roll

func _process_ground_movement(delta: float) -> void:
	var current_up = global_basis.y
	var radial = Vector3(global_position.x, global_position.y, 0.0)
	var dist_from_axis = radial.length()
	var gravity_factor = clampf(dist_from_axis / cylinder_radius, 0.0, 1.0)
	var current_gravity = base_gravity * gravity_factor

	if jump_cooldown_timer > 0.0:
		jump_cooldown_timer = maxf(0.0, jump_cooldown_timer - delta)

	var is_grounded = is_on_floor() and jump_cooldown_timer <= 0.0
	var input_len = input_axis.length()

	# 1. Handle Jump Initiation (standing still or moving)
	if jump_requested and (is_on_floor() or jump_cooldown_timer > 0.0):
		jump_requested = false
		vertical_velocity = jump_velocity
		jump_cooldown_timer = 0.20 # 200ms upward liftoff window
		floor_snap_length = 0.0
		var cur_v_up = velocity.dot(current_up)
		var cur_v_h = velocity - current_up * cur_v_up
		velocity = cur_v_h + current_up * vertical_velocity
		return

	# 2. Rock-solid motionless stop when grounded with no input (zero slope/downhill drift)
	if is_grounded and input_len < 0.01:
		vertical_velocity = -0.5
		velocity = -current_up * 0.5
		floor_snap_length = 0.15
		jump_requested = false
		return

	# 3. Base movement direction in player's local horizontal frame (tangent to cylinder surface)
	var flat_move_dir = (global_basis.x * input_axis.x + global_basis.z * input_axis.y)
	flat_move_dir = (flat_move_dir - current_up * flat_move_dir.dot(current_up))
	if flat_move_dir.length_squared() > 1e-5:
		flat_move_dir = flat_move_dir.normalized()
	else:
		flat_move_dir = Vector3.ZERO

	# Grade / Slope steepness speed scaling
	var floor_norm = get_floor_normal() if is_grounded and get_floor_normal().length_squared() > 0.5 else current_up
	var slope_angle = current_up.angle_to(floor_norm)
	var uphill_component = -flat_move_dir.dot(floor_norm)

	var grade_speed_mult = 1.0
	if is_grounded and flat_move_dir != Vector3.ZERO:
		if uphill_component > 0.01:
			# Uphill: forward progress relates to steepness of the grade (steeper = slower, never trapped)
			var sin_slope = sin(slope_angle)
			grade_speed_mult = clampf(1.0 - (sin_slope * uphill_component * 0.70), 0.25, 1.0)
		elif uphill_component < -0.01:
			# Downhill: slight natural acceleration
			var sin_slope = sin(slope_angle)
			grade_speed_mult = clampf(1.0 + (sin_slope * (-uphill_component) * 0.15), 1.0, 1.20)

	var move_speed = sprint_speed if is_sprinting else walk_speed
	var target_speed = move_speed * grade_speed_mult
	var target_h_vel = flat_move_dir * (target_speed * input_len)

	# Decompose current velocity into vertical (along current_up) and planar (horizontal)
	var cur_v_up = velocity.dot(current_up)
	var cur_v_h = velocity - current_up * cur_v_up

	var accel = acceleration if is_grounded else air_control
	var new_v_h = cur_v_h.lerp(target_h_vel, clampf(accel * delta, 0.0, 1.0))

	if is_grounded:
		# Maintain ground contact on walkable slopes (<= 45°) without downward slope drift
		vertical_velocity = -0.5
		floor_snap_length = 0.15
		jump_requested = false
	else:
		# Airborne or on steep non-walkable slope (> 45°): apply gravity toward floor
		vertical_velocity -= current_gravity * delta
		floor_snap_length = 0.0

		# If contacting a steep slope (> 45°), accelerate downhill along the slope surface
		if is_on_wall():
			var wall_norm = get_wall_normal()
			var wall_slope_angle = current_up.angle_to(wall_norm)
			if wall_slope_angle > deg_to_rad(max_walkable_slope_deg):
				var downhill_dir = (-current_up - wall_norm * (-current_up.dot(wall_norm)))
				if downhill_dir.length_squared() > 1e-4:
					downhill_dir = downhill_dir.normalized()
					var slide_accel = current_gravity * sin(wall_slope_angle) * 1.5
					new_v_h += downhill_dir * (slide_accel * delta)

	velocity = new_v_h + current_up * vertical_velocity

func _perform_step_glide(delta: float) -> void:
	if not is_on_floor() or is_flying or input_axis.length_squared() < 0.01 or not is_on_wall() or jump_cooldown_timer > 0.0:
		return

	var current_up = global_basis.y
	var flat_dir = (global_basis.x * input_axis.x + global_basis.z * input_axis.y)
	flat_dir = (flat_dir - current_up * flat_dir.dot(current_up))
	if flat_dir.length_squared() < 1e-5:
		return
	flat_dir = flat_dir.normalized()

	# Clear terrain polygon seams and elevation micro-steps up to 45 cm
	var step_height = 0.45
	var step_up = current_up * step_height
	var forward_dist = (sprint_speed if is_sprinting else walk_speed) * delta * 1.5
	var step_forward = flat_dir * forward_dist

	var t_step = global_transform
	if not test_move(t_step, step_up):
		t_step.origin += step_up
		if not test_move(t_step, step_forward):
			t_step.origin += step_forward
			var col = KinematicCollision3D.new()
			if test_move(t_step, -step_up * 1.5, col):
				if col.get_normal().dot(current_up) > 0.1:
					global_position = t_step.origin + col.get_travel()

func _process_flying_movement(delta: float) -> void:
	jump_requested = false

	# Fly in 3D camera direction
	var cam_basis = camera.global_basis
	var fly_dir = (cam_basis.x * input_axis.x + cam_basis.z * input_axis.y + global_basis.y * fly_vertical_axis)
	if fly_dir.length_squared() > 1.0:
		fly_dir = fly_dir.normalized()

	var target_vel = fly_dir * fly_speed
	if is_sprinting:
		target_vel *= 2.5 # High-speed flight across 8km cylinder

	velocity = velocity.lerp(target_vel, 8.0 * delta)

func toggle_fly_mode() -> void:
	is_flying = not is_flying
	if is_flying:
		var v_up = velocity.dot(global_basis.y)
		if v_up < 0.0:
			velocity -= global_basis.y * v_up

func get_spawn_points() -> Array:
	var target_path = "res://assets/maps/default/object_map.json"
	if not FileAccess.file_exists(target_path):
		target_path = "res://assets/maps/object_map.json"
	if not FileAccess.file_exists(target_path):
		return []
	var f = FileAccess.open(target_path, FileAccess.READ)
	if not f:
		return []
	var json = JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return []
	var data = json.data
	if data is Dictionary and data.has("spawn_points"):
		return data["spawn_points"] as Array
	return []

func reset_to_spawn() -> void:
	var spawn_pts = get_spawn_points()
	var default_pt = null
	for pt in spawn_pts:
		if pt is Dictionary and pt.get("is_default", false):
			default_pt = pt
			break
	if not default_pt and spawn_pts.size() > 0:
		default_pt = spawn_pts[0]

	if default_pt:
		teleport_to_spawn_data(default_pt)
		return

	var cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null
	if not cyl_world and get_parent():
		cyl_world = get_parent().get_node_or_null("CylinderWorld")

	if cyl_world and cyl_world.has_method("find_safe_spawn_point"):
		var spawn_info = cyl_world.find_safe_spawn_point(preferred_spawn_theta, preferred_spawn_z, min_elevation_above_sea)
		global_position = spawn_info["position"]
		global_basis = spawn_info["basis"]
	else:
		# Fallback if no CylinderWorld is present
		var surface_r = cylinder_radius
		if cyl_world and cyl_world.has_method("get_surface_radius_at"):
			surface_r = cyl_world.get_surface_radius_at(preferred_spawn_theta, preferred_spawn_z)
		elif cyl_world and cyl_world.has_method("get_elevation_at"):
			surface_r = cylinder_radius - cyl_world.get_elevation_at(preferred_spawn_theta, preferred_spawn_z)

		var spawn_r = surface_r - 1.80
		global_position = Vector3(spawn_r * cos(preferred_spawn_theta), spawn_r * sin(preferred_spawn_theta), preferred_spawn_z)
		var up = Vector3(-cos(preferred_spawn_theta), -sin(preferred_spawn_theta), 0.0)
		var back = Vector3(0.0, 0.0, 1.0)
		var right = up.cross(back).normalized()
		global_basis = Basis(right, up, back).orthonormalized()

	pitch = 0.0
	wobble_roll = 0.0
	wobble_velocity = 0.0
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	vertical_velocity = 0.0
	jump_cooldown_timer = 0.0
	is_sprinting = mobile_sprint_active

func teleport_to_spawn_data(spawn_dict: Dictionary) -> void:
	var theta: float = float(spawn_dict.get("theta", preferred_spawn_theta))
	var z: float = float(spawn_dict.get("z", preferred_spawn_z))
	var facing_yaw: float = float(spawn_dict.get("facing_yaw_rad", 0.0))
	var elev: float = float(spawn_dict.get("elevation", 0.0))

	var cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null
	if cyl_world and cyl_world.has_method("get_elevation_at"):
		var actual_elev = cyl_world.get_elevation_at(theta, z)
		if actual_elev > 0.0:
			elev = actual_elev

	var spawn_r = cylinder_radius - elev - 1.80
	global_position = Vector3(spawn_r * cos(theta), spawn_r * sin(theta), z)

	var up = Vector3(-cos(theta), -sin(theta), 0.0)
	var forward = Vector3(0.0, 0.0, 1.0) # Look +Z towards village center/fire
	var back = -forward
	var right = up.cross(back).normalized()
	var base_basis = Basis(right, up, back).orthonormalized()
	if not is_zero_approx(facing_yaw):
		base_basis = base_basis.rotated(up, facing_yaw)

	global_basis = base_basis
	pitch = 0.0
	wobble_roll = 0.0
	wobble_velocity = 0.0
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	vertical_velocity = 0.0
	jump_cooldown_timer = 0.0
	is_sprinting = mobile_sprint_active

func teleport_to_z(target_z: float, face_cap: bool = true) -> void:
	var cyl_world = get_tree().get_first_node_in_group("cylinder_world")
	var theta = atan2(global_position.y, global_position.x)
	var surface_r = cylinder_radius
	if cyl_world and cyl_world.has_method("get_elevation_at"):
		surface_r = cylinder_radius - cyl_world.get_elevation_at(theta, target_z)
	var spawn_r = surface_r - 1.80
	global_position = Vector3(spawn_r * cos(theta), spawn_r * sin(theta), target_z)
	var up = Vector3(-cos(theta), -sin(theta), 0.0)
	var forward = Vector3(0.0, 0.0, -1.0 if target_z < 0.0 else 1.0) if face_cap else Vector3(0.0, 0.0, -1.0)
	var back = -forward
	var right = up.cross(back).normalized()
	global_basis = Basis(right, up, back).orthonormalized()
	pitch = 0.0
	wobble_roll = 0.0
	wobble_velocity = 0.0
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	vertical_velocity = 0.0
	jump_cooldown_timer = 0.0
	is_sprinting = mobile_sprint_active

func deploy_campfire() -> void:
	var ref_obj = get_tree().get_first_node_in_group("reference_objects")
	if not ref_obj:
		var root_node = get_tree().current_scene
		if root_node:
			ref_obj = root_node.get_node_or_null("ReferenceObjects")
	if ref_obj and ref_obj.has_method("spawn_light_emitter"):
		var fwd = -global_basis.z
		fwd = (fwd - global_basis.y * fwd.dot(global_basis.y)).normalized()
		var target_pos = global_position + fwd * 2.5
		var theta = atan2(target_pos.y, target_pos.x)
		var z = target_pos.z
		ref_obj.spawn_light_emitter(SurfaceLightObject.ObjectType.CAMPFIRE, theta, z)
		HUD.log_event("Habitat Object -> Campfire deployed at surface position", "#ffaa44")

func deploy_lamp_post() -> void:
	var ref_obj = get_tree().get_first_node_in_group("reference_objects")
	if not ref_obj:
		var root_node = get_tree().current_scene
		if root_node:
			ref_obj = root_node.get_node_or_null("ReferenceObjects")
	if ref_obj and ref_obj.has_method("spawn_light_emitter"):
		var fwd = -global_basis.z
		fwd = (fwd - global_basis.y * fwd.dot(global_basis.y)).normalized()
		var target_pos = global_position + fwd * 2.5
		var theta = atan2(target_pos.y, target_pos.x)
		var z = target_pos.z
		ref_obj.spawn_light_emitter(SurfaceLightObject.ObjectType.LAMP_POST, theta, z)
		HUD.log_event("Habitat Object -> Light Post / Beacon deployed at surface position", "#ffcc44")

var last_telemetry: Dictionary = {}

var telemetry_emit_timer: float = 0.0

func _emit_telemetry(delta: float = 0.016) -> void:
	telemetry_emit_timer += delta
	if telemetry_emit_timer < 0.066:
		return
	telemetry_emit_timer = 0.0

	var radial = Vector3(global_position.x, global_position.y, 0.0)
	var dist_axis = radial.length()
	var dist_surface = max(cylinder_radius - dist_axis, 0.0)
	var grav_ratio = clampf(dist_axis / cylinder_radius, 0.0, 1.0)
	var grav_mag = base_gravity * grav_ratio
	var angle_rad = atan2(global_position.y, global_position.x)
	if angle_rad < 0.0:
		angle_rad += TAU

	var omega_n = lerpf(wobble_frequency_min, wobble_frequency_max, grav_ratio)
	var correction_rate = omega_n

	var is_in_water = dist_surface < 20.0
	var cam_pos = camera.global_position if camera else global_position
	var cam_dist_axis = Vector3(cam_pos.x, cam_pos.y, 0.0).length()
	var cam_elevation = max(cylinder_radius - cam_dist_axis, 0.0)
	var is_camera_underwater = cam_elevation < 20.0

	var telemetry = {
		"is_flying": is_flying,
		"is_sprinting": is_sprinting,
		"is_on_floor": is_on_floor(),
		"is_in_water": is_in_water,
		"is_camera_underwater": is_camera_underwater,
		"locomotion_state": get_locomotion_state(),
		"gravity_ms2": grav_mag,
		"gravity_g": grav_mag / 9.80665,
		"gravity_ratio": grav_ratio,
		"dist_from_axis": dist_axis,
		"dist_to_surface": dist_surface,
		"speed": velocity.length(),
		"pos_z": global_position.z,
		"ring_angle_deg": rad_to_deg(angle_rad),
		"wobble_deg": rad_to_deg(wobble_roll),
		"wobble_correction_rate": correction_rate,
		"pitch_deg": rad_to_deg(pitch)
	}
	last_telemetry = telemetry
	telemetry_updated.emit(telemetry)

func launch_aimed_particle(speed: float = 40.0) -> void:
	var emitter = get_tree().get_first_node_in_group("particle_emitter") as CylinderParticleEmitter if is_inside_tree() else null
	if emitter:
		var cam_forward = -camera.global_transform.basis.z.normalized() if camera else -global_transform.basis.z.normalized()
		var spawn_pos = (camera.global_position if camera else global_position) + cam_forward * 2.0
		emitter.launch_particle(spawn_pos, cam_forward * speed, {
			"color": Color(0.2, 0.95, 1.0, 1.0),
			"size": 4.0,
			"bounces": 3
		})

func launch_vertical_particle(speed: float = 35.0) -> void:
	var emitter = get_tree().get_first_node_in_group("particle_emitter") as CylinderParticleEmitter if is_inside_tree() else null
	if emitter:
		var spawn_pos = global_position + global_basis.y * 2.5
		emitter.launch_relative_to_surface(spawn_pos, 0.0, speed, 0.0, {
			"color": Color(1.0, 0.85, 0.2, 1.0),
			"size": 4.5,
			"bounces": 3
		})
