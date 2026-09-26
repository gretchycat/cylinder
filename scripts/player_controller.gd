class_name PlayerController
extends CharacterBody3D

const CylinderParticleEmitter = preload("res://scripts/cylinder_particle_emitter.gd")

signal telemetry_updated(data: Dictionary)

@export_category("Cylinder Dimensions (8 km dia x 18 km length)")
@export var cylinder_radius: float = 4000.0
@export var cylinder_length: float = 18000.0

@export_category("Movement & Gravity")
@export var walk_speed: float = 8.0
@export var sprint_speed: float = 20.0
@export var fly_speed: float = 80.0
@export var acceleration: float = 16.0
@export var air_control: float = 5.0
@export var base_gravity: float = 9.5
@export var jump_velocity: float = 8.5
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
var is_sprinting: bool = false
var mobile_sprint_active: bool = false

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

	# Ensure camera far distance covers the 18 km cylinder and end caps (26 km total)
	if camera:
		camera.far = 40000.0

	# Ultra-forgiving collision recovery across terrain seams and 26 km end cap dishes
	safe_margin = 0.15
	max_slides = 8
	floor_snap_length = 1.5
	floor_max_angle = deg_to_rad(89.5)
	floor_constant_speed = true
	floor_stop_on_slope = false
	floor_block_on_wall = false
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

	# Hotkeys: T (wobble test), C (deploy campfire), L (deploy lamp post), P (launch particle), G (vertical toss)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			wobble_impulse(22.0)
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
	if not is_on_floor():
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

	if not is_flying and is_on_floor():
		_perform_step_glide(delta)

	_emit_telemetry()

func _update_input() -> void:
	# Keyboard input
	var forward = Input.get_action_strength("move_forward")
	var back = Input.get_action_strength("move_backward")
	var left = Input.get_action_strength("move_left")
	var right = Input.get_action_strength("move_right")

	var kb_axis = Vector2(right - left, back - forward)
	if kb_axis.length_squared() > 0.01:
		input_axis = kb_axis.normalized()

	# Combine keyboard Shift sprint with mobile toggle
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

	# --- Attitude Auto-Flattening When Taking Steps ---
	if look_control_timer > 0.0:
		look_control_timer = maxf(0.0, look_control_timer - delta)

	var is_actively_controlling = look_control_timer > 0.0
	var is_taking_steps = is_on_floor() and not is_flying and (input_axis.length_squared() > 0.01 or velocity.length() > 0.3)

	if is_taking_steps and not is_actively_controlling:
		# Smoothly flatten pitch attitude towards horizontal level (0.0) as steps are taken
		pitch = lerpf(pitch, 0.0, clampf(attitude_flatten_speed * delta, 0.0, 1.0))
		head.rotation.x = pitch

		# Settle any residual roll wobble to flat
		wobble_roll = lerpf(wobble_roll, 0.0, clampf(attitude_flatten_speed * 2.0 * delta, 0.0, 1.0))
		wobble_velocity = lerpf(wobble_velocity, 0.0, clampf(attitude_flatten_speed * 2.0 * delta, 0.0, 1.0))

	# Apply roll wobble / attitude to camera head
	head.rotation.z = wobble_roll

func _process_ground_movement(delta: float) -> void:
	var current_up = global_basis.y
	var radial = Vector3(global_position.x, global_position.y, 0.0)
	var dist_from_axis = radial.length()
	var gravity_factor = clampf(dist_from_axis / cylinder_radius, 0.0, 1.0)
	var current_gravity = base_gravity * gravity_factor

	var move_speed = sprint_speed if is_sprinting else walk_speed
	var input_len = input_axis.length()

	# Base movement direction in player's local horizontal frame (tangent to cylinder surface)
	var flat_move_dir = (global_basis.x * input_axis.x + global_basis.z * input_axis.y)
	flat_move_dir = (flat_move_dir - current_up * flat_move_dir.dot(current_up))
	if flat_move_dir.length_squared() > 1e-5:
		flat_move_dir = flat_move_dir.normalized()
	else:
		flat_move_dir = Vector3.ZERO

	# Grade / Slope steepness speed scaling
	var floor_norm = get_floor_normal() if is_on_floor() and get_floor_normal().length_squared() > 0.5 else current_up
	var slope_angle = current_up.angle_to(floor_norm)
	var uphill_component = -flat_move_dir.dot(floor_norm)

	var grade_speed_mult = 1.0
	if is_on_floor() and flat_move_dir != Vector3.ZERO:
		if uphill_component > 0.01:
			# Uphill: forward progress relates to steepness of the grade (steeper = slower, never trapped)
			var sin_slope = sin(slope_angle)
			grade_speed_mult = clampf(1.0 - (sin_slope * uphill_component * 0.70), 0.25, 1.0)
		elif uphill_component < -0.01:
			# Downhill: slight natural acceleration
			var sin_slope = sin(slope_angle)
			grade_speed_mult = clampf(1.0 + (sin_slope * (-uphill_component) * 0.15), 1.0, 1.20)

	var target_speed = move_speed * grade_speed_mult
	var target_h_vel = flat_move_dir * (target_speed * input_len)

	# Decompose current velocity into vertical (along current_up) and planar (horizontal)
	var v_up_scalar = velocity.dot(current_up)
	var v_h = velocity - current_up * v_up_scalar

	var accel = acceleration if is_on_floor() else air_control
	v_h = v_h.lerp(target_h_vel, accel * delta)

	# Apply gravity along current_up
	if not is_on_floor():
		v_up_scalar -= current_gravity * delta
	else:
		# On floor: maintain continuous floor contact without accumulating unbounded downward velocity
		v_up_scalar = -maxf(2.0, current_gravity * 0.1)

	# Jump handling
	if jump_requested:
		jump_requested = false
		if is_on_floor():
			v_up_scalar = jump_velocity

	velocity = v_h + current_up * v_up_scalar

func _perform_step_glide(delta: float) -> void:
	if not is_on_floor() or is_flying or input_axis.length_squared() < 0.01:
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

func reset_to_spawn() -> void:
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

		var spawn_r = surface_r - 0.95
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

func teleport_to_z(target_z: float, face_cap: bool = true) -> void:
	var cyl_world = get_tree().get_first_node_in_group("cylinder_world")
	var theta = atan2(global_position.y, global_position.x)
	var surface_r = cylinder_radius
	if cyl_world and cyl_world.has_method("get_elevation_at"):
		surface_r = cylinder_radius - cyl_world.get_elevation_at(theta, target_z)
	var spawn_r = surface_r - 0.95
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

var last_telemetry: Dictionary = {}

func get_telemetry() -> Dictionary:
	return last_telemetry

func _emit_telemetry() -> void:
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

func launch_aimed_particle(speed: float = 35.0) -> void:
	var emitter = get_tree().get_first_node_in_group("particle_emitter") as CylinderParticleEmitter if is_inside_tree() else null
	if emitter:
		var cam_forward = -camera.global_transform.basis.z.normalized() if camera else -global_transform.basis.z.normalized()
		var spawn_pos = (camera.global_position if camera else global_position) + cam_forward * 1.5
		emitter.launch_particle(spawn_pos, cam_forward * speed, {
			"color": Color(0.2, 0.9, 1.0, 1.0),
			"size": 1.2,
			"bounces": 2
		})

func launch_vertical_particle(speed: float = 30.0) -> void:
	var emitter = get_tree().get_first_node_in_group("particle_emitter") as CylinderParticleEmitter if is_inside_tree() else null
	if emitter:
		var spawn_pos = global_position + global_basis.y * 1.8
		emitter.launch_relative_to_surface(spawn_pos, 0.0, speed, 0.0, {
			"color": Color(1.0, 0.85, 0.2, 1.0),
			"size": 1.4,
			"bounces": 2
		})
