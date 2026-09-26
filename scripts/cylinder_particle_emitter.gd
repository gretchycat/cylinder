class_name CylinderParticleEmitter
extends Node3D

signal particle_launched(particle_id: int, origin: Vector3, velocity: Vector3)
signal particle_landed(particle_id: int, impact_pos: Vector3, flight_time: float)

@export_category("Cylinder Habitat Physics")
@export var cylinder_radius: float = 4000.0
@export var cylinder_length: float = 18000.0
@export var base_gravity: float = 9.5
@export var spin_direction: int = 1 # +1 for CCW, -1 for CW
@export var air_drag_coefficient: float = 0.0 # 0.0 = vacuum rotating frame, >0 = aerodynamic drag

@export_category("Particle Properties")
@export var max_particles: int = 3500
@export var particle_lifetime: float = 80.0
@export var trail_lifetime: float = 90.0
@export var max_trail_points: int = 300
@export var bounciness: float = 0.35
@export var max_bounces: int = 1

@export_category("Visuals & Trajectory Rendering")
@export var show_trajectories: bool = true
@export var show_particles: bool = true
@export var default_particle_color: Color = Color(0.25, 0.90, 1.0, 1.0)
@export var impact_marker_color: Color = Color(1.0, 0.45, 0.2, 0.95)

@export_category("Continuous Stream / Rain Generator")
@export var rain_stream_enabled: bool = false
@export var rain_stream_rate: float = 45.0 # particles per second
@export var rain_stream_altitude: float = 1250.0 # meters above floor (cloud base)

class ParticleData:
	var id: int = 0
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var age: float = 0.0
	var is_active: bool = true
	var is_rain: bool = false
	var bounces_remaining: int = 0
	var trail: Array[Vector3] = []
	var color: Color = Color.WHITE
	var size: float = 2.5
	var flight_time: float = 0.0
	var impact_pos: Vector3 = Vector3.ZERO
	var has_landed: bool = false
	var landed_age: float = 0.0

var particles: Array[ParticleData] = []
var next_particle_id: int = 1
var rain_stream_accum: float = 0.0

# Visual nodes
var trail_mesh_instance: MeshInstance3D = null
var trail_mesh: ImmediateMesh = null
var particle_multimesh_instance: MultiMeshInstance3D = null
var particle_multimesh: MultiMesh = null
var terrain_manager = null

func _ready() -> void:
	add_to_group("particle_emitter")
	_setup_visual_nodes()
	_fetch_references()

func _fetch_references() -> void:
	var weather = get_tree().get_first_node_in_group("weather_system") as WeatherSystem if is_inside_tree() else null
	if weather:
		spin_direction = int(weather.spin_direction)
		base_gravity = weather.base_gravity
		cylinder_radius = weather.cylinder_radius
		cylinder_length = weather.cylinder_length

	var cylinder_world = get_tree().get_first_node_in_group("cylinder_world") as CylinderGenerator if is_inside_tree() else null
	if cylinder_world:
		terrain_manager = cylinder_world.terrain_manager

func _setup_visual_nodes() -> void:
	# 1. Trajectory line renderer using ImmediateMesh with expansive AABB to prevent frustum culling
	trail_mesh_instance = MeshInstance3D.new()
	trail_mesh_instance.name = "TrajectoryLineRenderer"
	trail_mesh = ImmediateMesh.new()
	trail_mesh_instance.mesh = trail_mesh
	trail_mesh_instance.custom_aabb = AABB(Vector3(-6000, -6000, -15000), Vector3(12000, 12000, 30000))
	trail_mesh_instance.extra_cull_margin = 15000.0

	var line_mat = StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.vertex_color_use_as_albedo = true
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	line_mat.render_priority = 11
	trail_mesh_instance.material_override = line_mat
	add_child(trail_mesh_instance)

	# 2. Particle sphere rendering via MultiMeshInstance3D for high performance
	particle_multimesh_instance = MultiMeshInstance3D.new()
	particle_multimesh_instance.name = "ParticleMultiMesh"
	particle_multimesh_instance.custom_aabb = AABB(Vector3(-6000, -6000, -15000), Vector3(12000, 12000, 30000))
	particle_multimesh_instance.extra_cull_margin = 15000.0

	particle_multimesh = MultiMesh.new()
	particle_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	particle_multimesh.use_colors = true
	particle_multimesh.instance_count = max_particles

	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 2.0
	sphere_mesh.height = 4.0
	particle_multimesh.mesh = sphere_mesh

	var p_mat = StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.vertex_color_use_as_albedo = true
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	p_mat.render_priority = 12
	particle_multimesh_instance.material_override = p_mat
	particle_multimesh_instance.multimesh = particle_multimesh
	add_child(particle_multimesh_instance)

	# Initialize all instances to invisible
	for i in range(max_particles):
		particle_multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -99999, 0)))
		particle_multimesh.set_instance_color(i, Color(0, 0, 0, 0))

func _physics_process(delta: float) -> void:
	_update_physics_parameters()
	_process_continuous_rain_stream(delta)
	_integrate_particles(delta)
	_update_visuals()

func _update_physics_parameters() -> void:
	var weather = get_tree().get_first_node_in_group("weather_system") as WeatherSystem if is_inside_tree() else null
	if weather:
		spin_direction = int(weather.spin_direction)
		base_gravity = weather.base_gravity
		if weather.precipitation_rate_mmh > 0.05:
			rain_stream_enabled = true
			var intensity_norm = clampf(weather.precipitation_rate_mmh / 40.0, 0.05, 1.0)
			rain_stream_rate = lerpf(15.0, 120.0, intensity_norm)
			rain_stream_altitude = weather.cloud_altitude_m
		else:
			rain_stream_enabled = false

func get_omega() -> float:
	return sqrt(base_gravity / maxf(cylinder_radius, 1.0))

func get_omega_vector() -> Vector3:
	return Vector3(0.0, 0.0, get_omega() * float(spin_direction))

func compute_acceleration(pos: Vector3, vel: Vector3) -> Vector3:
	# 1. Centrifugal acceleration: a_cent = Omega^2 * r_perp (points radially OUTWARD)
	var omega = get_omega()
	var omega_sq = omega * omega
	var r_perp = Vector3(pos.x, pos.y, 0.0)
	var a_centrifugal = r_perp * omega_sq

	# 2. Coriolis acceleration: a_coriolis = -2 * (Omega x vel)
	var omega_z = omega * float(spin_direction)
	var a_coriolis = Vector3(
		2.0 * omega_z * vel.y,
		-2.0 * omega_z * vel.x,
		0.0
	)

	# 3. Aerodynamic drag in rotating frame
	var a_drag = Vector3.ZERO
	if air_drag_coefficient > 0.0001:
		var speed = vel.length()
		a_drag = -vel * (0.5 * air_drag_coefficient * speed)

	return a_centrifugal + a_coriolis + a_drag

func _integrate_particles(delta: float) -> void:
	var half_len = cylinder_length * 0.5
	var i = particles.size() - 1

	while i >= 0:
		var p = particles[i]
		p.age += delta

		if p.has_landed:
			p.landed_age += delta
			var max_landed = 0.55 if p.is_rain else 60.0
			if p.landed_age >= max_landed or p.age >= trail_lifetime:
				particles.remove_at(i)
				i -= 1
				continue

		# Remove expired particles
		if p.age >= trail_lifetime:
			particles.remove_at(i)
			i -= 1
			continue

		if p.is_active:
			p.flight_time += delta

			# Velocity Verlet numerical integration:
			var a1 = compute_acceleration(p.position, p.velocity)
			var new_pos = p.position + (p.velocity * delta) + (0.5 * a1 * delta * delta)
			var a2 = compute_acceleration(new_pos, p.velocity + a1 * delta)
			p.velocity += 0.5 * (a1 + a2) * delta
			p.position = new_pos

			# Record trajectory trail point
			if p.trail.is_empty() or p.trail.back().distance_squared_to(p.position) > 4.0:
				p.trail.append(p.position)
				var max_pts = 6 if p.is_rain else max_trail_points
				if p.trail.size() > max_pts:
					p.trail.remove_at(0)

			# Surface collision check with cylinder terrain / end caps
			var r_curr = Vector2(p.position.x, p.position.y).length()
			var elev = 0.0
			var theta = atan2(p.position.y, p.position.x)
			if terrain_manager:
				elev = terrain_manager.get_elevation(theta, p.position.z, cylinder_length)

			var surface_r = cylinder_radius - elev

			# Check inner floor collision
			var hit_surface = false
			var norm = Vector3(-cos(theta), -sin(theta), 0.0)

			if r_curr >= surface_r:
				hit_surface = true
				var p_dir = Vector2(p.position.x, p.position.y).normalized()
				p.position.x = p_dir.x * (surface_r - 0.05)
				p.position.y = p_dir.y * (surface_r - 0.05)

			# Check end cap bulkheads
			if abs(p.position.z) >= half_len:
				hit_surface = true
				norm = Vector3(0, 0, -signf(p.position.z))
				p.position.z = signf(p.position.z) * (half_len - 0.1)

			if hit_surface:
				if p.bounces_remaining > 0:
					p.bounces_remaining -= 1
					# Reflect velocity off surface normal with restitution
					var v_dot_n = p.velocity.dot(norm)
					if v_dot_n < 0.0:
						p.velocity = (p.velocity - (1.0 + bounciness) * v_dot_n * norm) * bounciness
				else:
					# Landed and settled on surface
					p.is_active = false
					p.has_landed = true
					p.impact_pos = p.position
					p.velocity = Vector3.ZERO
					p.landed_age = 0.0
					particle_landed.emit(p.id, p.impact_pos, p.flight_time)

		i -= 1

func _process_continuous_rain_stream(delta: float) -> void:
	if not rain_stream_enabled or rain_stream_rate <= 0.01:
		return

	rain_stream_accum += delta * rain_stream_rate
	var target_player = get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null
	var player_z = target_player.global_position.z if target_player else 0.0
	var player_theta = atan2(target_player.global_position.y, target_player.global_position.x) if target_player else -PI * 0.5

	var r_cloud = cylinder_radius - rain_stream_altitude

	while rain_stream_accum >= 1.0:
		rain_stream_accum -= 1.0

		# Distribute droplets from cloud base down through the entire atmospheric column
		var spawn_r = lerpf(r_cloud, cylinder_radius - 10.0, randf())
		var spawn_theta = player_theta + randf_range(-0.45, 0.45)
		var spawn_z = player_z + randf_range(-450.0, 450.0)

		var cos_t = cos(spawn_theta)
		var sin_t = sin(spawn_theta)
		var origin = Vector3(spawn_r * cos_t, spawn_r * sin_t, spawn_z)

		# Initial downward condensation fall velocity directed radially outward (+r direction toward ground)
		var out_dir = Vector3(cos_t, sin_t, 0.0)
		var spin_sign = float(spin_direction)
		var tangent_dir = Vector3(-sin_t, cos_t, 0.0) * spin_sign

		# Droplet terminal fall speed and retrograde Coriolis tilt
		var fall_speed = randf_range(16.0, 32.0)
		var coriolis_drift = -2.0 * get_omega() * fall_speed * 0.45
		var v_init = (out_dir * fall_speed) + (tangent_dir * coriolis_drift) + Vector3(0, 0, randf_range(-0.8, 0.8))

		launch_particle(origin, v_init, {
			"color": Color(0.80, 0.93, 1.0, 0.90),
			"size": randf_range(2.5, 4.5),
			"bounces": 0,
			"is_rain": true
		})

func launch_particle(origin: Vector3, velocity_world: Vector3, custom_data: Dictionary = {}) -> int:
	if particles.size() >= max_particles:
		# Evict oldest landed rain particle first if available
		var evicted_idx = -1
		for idx in range(particles.size()):
			var item = particles[idx]
			if item.is_rain and item.has_landed:
				evicted_idx = idx
				break
		if evicted_idx >= 0:
			particles.remove_at(evicted_idx)
		else:
			particles.remove_at(0)

	var p = ParticleData.new()
	p.id = next_particle_id
	next_particle_id += 1

	p.position = origin
	p.velocity = velocity_world
	p.age = 0.0
	p.is_active = true
	p.is_rain = custom_data.get("is_rain", false)
	p.bounces_remaining = custom_data.get("bounces", max_bounces)
	p.color = custom_data.get("color", default_particle_color)
	p.size = custom_data.get("size", 2.5)
	p.trail = [origin]

	particles.append(p)
	particle_launched.emit(p.id, origin, velocity_world)
	return p.id

func launch_relative_to_surface(origin: Vector3, v_tangent: float, v_up: float, v_axial: float, custom_data: Dictionary = {}) -> int:
	# Local surface basis vectors:
	# UP: Inward toward rotational axis (-cos, -sin, 0)
	# TANGENT: Prograde in spin direction (-sin, cos, 0) * spin_direction
	# AXIAL: Along cylinder length (0, 0, 1)
	var r_vec = Vector2(origin.x, origin.y)
	var theta = atan2(r_vec.y, r_vec.x) if r_vec.length_squared() > 1.0 else -PI * 0.5
	var spin_sign = float(spin_direction)

	var up_vec = Vector3(-cos(theta), -sin(theta), 0.0)
	var tangent_vec = Vector3(-sin(theta), cos(theta), 0.0) * spin_sign
	var axial_vec = Vector3(0.0, 0.0, 1.0)

	var v_world = (up_vec * v_up) + (tangent_vec * v_tangent) + (axial_vec * v_axial)
	return launch_particle(origin, v_world, custom_data)

func predict_trajectory(origin: Vector3, initial_vel: Vector3, steps: int = 160, dt: float = 0.06) -> PackedVector3Array:
	var points = PackedVector3Array()
	var pos = origin
	var vel = initial_vel
	points.append(pos)

	var half_len = cylinder_length * 0.5

	for s in range(steps):
		var a1 = compute_acceleration(pos, vel)
		var new_pos = pos + (vel * dt) + (0.5 * a1 * dt * dt)
		var a2 = compute_acceleration(new_pos, vel + a1 * dt)
		vel += 0.5 * (a1 + a2) * dt
		pos = new_pos
		points.append(pos)

		var r = Vector2(pos.x, pos.y).length()
		var theta = atan2(pos.y, pos.x)
		var elev = terrain_manager.get_elevation(theta, pos.z, cylinder_length) if terrain_manager else 0.0
		if r >= cylinder_radius - elev or abs(pos.z) >= half_len:
			break

	return points

func _update_visuals() -> void:
	if not show_trajectories and not show_particles:
		trail_mesh.clear_surfaces()
		for i in range(max_particles):
			particle_multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -99999, 0)))
		return

	# Update MultiMesh particles
	var num_p = particles.size()
	for i in range(max_particles):
		if i < num_p and show_particles:
			var p = particles[i]
			var t: Transform3D
			var fade = 1.0

			if p.is_rain:
				if p.has_landed:
					# Landed rain drop puddle / splash ring
					fade = clampf(1.0 - (p.landed_age / 0.55), 0.0, 1.0)
					var splash_r = lerpf(p.size * 0.5, p.size * 3.5, p.landed_age / 0.55)
					t = Transform3D(Basis().scaled(Vector3(splash_r, 0.15, splash_r)), p.position)
				else:
					# In-flight falling rain droplet streak
					var scale_factor = p.size
					if p.velocity.length_squared() > 1.0:
						var v_dir = p.velocity.normalized()
						var v_up = Vector3.UP if abs(v_dir.y) < 0.9 else Vector3.FORWARD
						var b = Basis.looking_at(v_dir, v_up)
						var stretch = clampf(p.velocity.length() * 0.18, 1.5, 7.0)
						b = b.scaled(Vector3(scale_factor, scale_factor, scale_factor * stretch))
						t = Transform3D(b, p.position)
					else:
						t = Transform3D(Basis().scaled(Vector3.ONE * scale_factor), p.position)
			else:
				var scale_factor = p.size if p.is_active else p.size * 0.6
				fade = clampf(1.0 - (p.age / trail_lifetime), 0.0, 1.0)
				if p.velocity.length_squared() > 4.0:
					var v_dir = p.velocity.normalized()
					var v_up = Vector3.UP if abs(v_dir.y) < 0.9 else Vector3.FORWARD
					var b = Basis.looking_at(v_dir, v_up)
					var stretch = clampf(p.velocity.length() * 0.12, 1.0, 5.0)
					b = b.scaled(Vector3(scale_factor, scale_factor, scale_factor * stretch))
					t = Transform3D(b, p.position)
				else:
					t = Transform3D(Basis().scaled(Vector3.ONE * scale_factor), p.position)

			particle_multimesh.set_instance_transform(i, t)
			particle_multimesh.set_instance_color(i, Color(p.color.r, p.color.g, p.color.b, p.color.a * fade))
		else:
			particle_multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -99999, 0)))
			particle_multimesh.set_instance_color(i, Color(0, 0, 0, 0))

	# Update Trajectory Lines & Splashes
	trail_mesh.clear_surfaces()
	if not show_trajectories:
		return

	trail_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for p in particles:
		var pts = p.trail
		var pt_count = pts.size()

		if pt_count >= 2 and (not p.is_rain or show_trajectories):
			var fade = clampf(1.0 - (p.landed_age / 0.55 if p.is_rain and p.has_landed else p.age / trail_lifetime), 0.0, 1.0)
			for j in range(pt_count - 1):
				var seg_frac0 = float(j) / float(max(pt_count - 1, 1))
				var seg_frac1 = float(j + 1) / float(max(pt_count - 1, 1))

				var col0 = Color(p.color.r, p.color.g, p.color.b, p.color.a * fade * (0.2 + 0.8 * seg_frac0))
				var col1 = Color(p.color.r, p.color.g, p.color.b, p.color.a * fade * (0.2 + 0.8 * seg_frac1))

				trail_mesh.surface_set_color(col0)
				trail_mesh.surface_add_vertex(pts[j])
				trail_mesh.surface_set_color(col1)
				trail_mesh.surface_add_vertex(pts[j + 1])

		# Draw impact marker / splash diamond
		if p.has_landed:
			var imp = p.impact_pos
			if p.is_rain:
				var splash_prog = clampf(p.landed_age / 0.55, 0.0, 1.0)
				var splash_fade = 1.0 - splash_prog
				var splash_r = lerpf(1.5, 6.0, splash_prog)
				var c_splash = Color(0.85, 0.95, 1.0, 0.85 * splash_fade)

				# Draw ground splash cross
				trail_mesh.surface_set_color(c_splash)
				trail_mesh.surface_add_vertex(imp + Vector3(-splash_r, 0, 0))
				trail_mesh.surface_add_vertex(imp + Vector3(splash_r, 0, 0))

				trail_mesh.surface_set_color(c_splash)
				trail_mesh.surface_add_vertex(imp + Vector3(0, 0, -splash_r))
				trail_mesh.surface_add_vertex(imp + Vector3(0, 0, splash_r))
			else:
				var fade = clampf(1.0 - (p.age / trail_lifetime), 0.0, 1.0)
				var imp_r = 6.0
				var c_imp = impact_marker_color
				c_imp.a *= fade

				trail_mesh.surface_set_color(c_imp)
				trail_mesh.surface_add_vertex(imp + Vector3(-imp_r, 0, 0))
				trail_mesh.surface_add_vertex(imp + Vector3(imp_r, 0, 0))

				trail_mesh.surface_set_color(c_imp)
				trail_mesh.surface_add_vertex(imp + Vector3(0, -imp_r, 0))
				trail_mesh.surface_add_vertex(imp + Vector3(0, imp_r, 0))

				trail_mesh.surface_set_color(c_imp)
				trail_mesh.surface_add_vertex(imp + Vector3(0, 0, -imp_r))
				trail_mesh.surface_add_vertex(imp + Vector3(0, 0, imp_r))

	trail_mesh.surface_end()

func clear_all() -> void:
	particles.clear()
	_update_visuals()

func get_particle_count() -> int:
	return particles.size()

func get_active_particle_count() -> int:
	var count = 0
	for p in particles:
		if p.is_active:
			count += 1
	return count
