class_name PlayerController
extends CharacterBody3D

signal telemetry_updated(data: Dictionary)

@export_category("Cylinder Dimensions (8 km x 8 km)")
@export var cylinder_radius: float = 4000.0
@export var cylinder_length: float = 8000.0

@export_category("Movement & Gravity")
@export var walk_speed: float = 8.0
@export var sprint_speed: float = 20.0
@export var fly_speed: float = 80.0
@export var acceleration: float = 16.0
@export var air_control: float = 5.0
@export var base_gravity: float = 12.0
@export var jump_velocity: float = 8.5
@export var horizon_alignment_speed: float = 20.0

@export_category("Wobble Dynamics")
@export var wobble_frequency_min: float = 1.0
@export var wobble_frequency_max: float = 16.0
@export var wobble_damping_min: float = 0.25
@export var wobble_damping_max: float = 1.0

@export_category("Mouse Look")
@export var mouse_sensitivity: float = 0.0025
@export var touch_sensitivity: float = 0.004

var is_flying: bool = false
var is_sprinting: bool = false
var mobile_sprint_active: bool = false

# Virtual input state (for keyboard or mobile touch controls)
var input_axis: Vector2 = Vector2.ZERO
var fly_vertical_axis: float = 0.0
var jump_requested: bool = false

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

	# Ensure camera far distance covers the 8 km cylinder
	if camera:
		camera.far = 25000.0

	# Floor snapping for high-speed sprinting over 100m elevation hills and slopes
	floor_snap_length = 2.5
	floor_max_angle = deg_to_rad(65.0)

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

	# Wobble test key (T)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			wobble_impulse(22.0)

func apply_look_input(delta_look: Vector2) -> void:
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

	# Stride excitation when walking / running on the ground
	var stride_excitation: float = 0.0
	var speed = velocity.length()
	if is_on_floor() and not is_flying and speed > 0.3:
		var step_freq = 18.0 if is_sprinting else 11.5
		stride_phase += step_freq * delta
		var sway_amplitude = deg_to_rad(3.5 if is_sprinting else 1.6)
		stride_excitation = sin(stride_phase) * sway_amplitude * k_spring
	else:
		stride_phase = lerpf(stride_phase, 0.0, 5.0 * delta)

	# Harmonic oscillator: d2phi/dt2 = -k*phi - c*dphi/dt + excitation
	var wobble_accel = -k_spring * wobble_roll - c_damp * wobble_velocity + stride_excitation
	wobble_velocity += wobble_accel * delta
	wobble_roll += wobble_velocity * delta
	wobble_roll = clampf(wobble_roll, -deg_to_rad(45.0), deg_to_rad(45.0))

	# Apply roll wobble to camera head
	head.rotation.z = wobble_roll

func _process_ground_movement(delta: float) -> void:
	var current_up = global_basis.y
	var radial = Vector3(global_position.x, global_position.y, 0.0)
	var dist_from_axis = radial.length()
	var gravity_factor = clampf(dist_from_axis / cylinder_radius, 0.0, 1.0)
	var current_gravity = base_gravity * gravity_factor

	# Separate velocity into vertical (along local up) and tangent (along ground)
	var v_up = velocity.dot(current_up)
	var v_tangent = velocity - current_up * v_up

	# Movement direction in player's local ground plane
	var move_speed = sprint_speed if is_sprinting else walk_speed
	var move_dir = (global_basis.x * input_axis.x + global_basis.z * input_axis.y)
	move_dir = (move_dir - current_up * move_dir.dot(current_up)).normalized() * input_axis.length()

	var target_v_tangent = move_dir * move_speed
	var accel = acceleration if is_on_floor() else air_control
	v_tangent = v_tangent.lerp(target_v_tangent, accel * delta)

	# Gravity and floor sticking
	if not is_on_floor():
		v_up -= current_gravity * delta
	else:
		# Stick firmly to the curved surface and hills
		if v_up < 0.0:
			v_up = -maxf(3.0, move_speed * 0.25)

	# Jump handling
	if jump_requested:
		jump_requested = false
		if is_on_floor():
			v_up = jump_velocity

	velocity = v_tangent + current_up * v_up

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
	# Bottom of cylinder at z = 0, facing -Z
	var surface_r = cylinder_radius
	var cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null
	if not cyl_world and get_parent():
		cyl_world = get_parent().get_node_or_null("CylinderWorld")
	if cyl_world and cyl_world.has_method("get_surface_radius_at"):
		surface_r = cyl_world.get_surface_radius_at(-PI * 0.5, 0.0)
	elif cyl_world and cyl_world.has_method("get_elevation_at"):
		surface_r = cylinder_radius - cyl_world.get_elevation_at(-PI * 0.5, 0.0)

	# Capsule has height 1.8m (half-height 0.9m)
	var spawn_r = surface_r - 0.92

	global_position = Vector3(0.0, -spawn_r, 0.0)
	global_basis = Basis.IDENTITY # At (0, -R, 0), local Up is +Y
	pitch = 0.0
	wobble_roll = 0.0
	wobble_velocity = 0.0
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO

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

	var telemetry = {
		"is_flying": is_flying,
		"is_sprinting": is_sprinting,
		"is_on_floor": is_on_floor(),
		"is_in_water": is_in_water,
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
	telemetry_updated.emit(telemetry)
