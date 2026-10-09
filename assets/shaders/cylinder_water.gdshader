shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx, fog_disabled;


uniform vec3 extinction_rgb;
uniform vec4 reflection_color : source_color;
uniform vec4 foam_color : source_color;
uniform vec4 caustic_color : source_color;
uniform vec4 overcast_color : source_color;
uniform vec4 shallow_color : source_color = vec4(0.08, 0.55, 0.78, 0.38);
uniform vec4 deep_color : source_color = vec4(0.015, 0.18, 0.38, 0.72);
uniform sampler2D elevation_map : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec2 elevation_map_size;
uniform float cylinder_radius = 3980.0;
uniform float cylinder_length = 18000.0;
uniform float water_level = 20.0;
uniform float max_elevation = 100.0;
uniform float wave_speed : hint_range(0.0, 5.0) = 0.65;
uniform float roughness : hint_range(0.0, 1.0) = 0.05;
uniform float specular : hint_range(0.0, 1.0) = 0.95;

uniform vec4 air_color : source_color = vec4(0.52, 0.72, 0.88, 1.0);
uniform float air_density : hint_range(0.0, 3.0) = 1.25;
uniform float air_distance_min = 200.0;
uniform float air_distance_max = 18000.0;

uniform sampler2D axial_light_lut : hint_default_white, filter_linear, repeat_disable;
uniform float axial_light_enabled = 1.0;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_thickness : hint_range(50.0, 800.0) = 250.0;
uniform float precipitation_rate = 0.0;
uniform float is_snow_mode = 0.0;

varying vec3 world_pos;
varying vec2 map_uv;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_uv = UV;
}

// 2D to 2D pseudo-random hash
vec2 hash2D(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453123);
}

// 4-octave harmonic wave spectrum with multi-directional dispersion
vec2 get_wave_offset(vec2 pos, float time, float speed) {
	// Wave 1: Primary axial swell
	vec2 d1 = vec2(0.35, 0.94);
	float f1 = dot(d1, pos) * 0.022 + time * 0.45 * speed;
	vec2 n1 = d1 * cos(f1) * 0.055;

	// Wave 2: Oblique crossing swell
	vec2 d2 = vec2(0.82, -0.57);
	float f2 = dot(d2, pos) * 0.048 + time * 0.72 * speed;
	vec2 n2 = d2 * cos(f2) * 0.040;

	// Wave 3: Wind-driven capillary ripple
	vec2 d3 = vec2(-0.64, 0.77);
	float f3 = dot(d3, pos) * 0.115 + time * 1.35 * speed;
	vec2 n3 = d3 * cos(f3) * 0.024;

	// Wave 4: Micro water shimmer
	vec2 d4 = vec2(0.95, 0.31);
	float f4 = dot(d4, pos) * 0.260 - time * 2.10 * speed;
	vec2 n4 = d4 * cos(f4) * 0.014;

	return n1 + n2 + n3 + n4;
}

// Procedural expanding raindrop ripples on the water surface
vec2 get_raindrop_ripples(vec2 pos, float time, float rate) {
	if (rate <= 0.05) return vec2(0.0);
	float intensity = clamp(rate / 25.0, 0.0, 1.0);
	vec2 total_ripple = vec2(0.0);

	for (float i = 0.0; i < 3.0; i += 1.0) {
		vec2 grid_uv = pos * (1.2 + i * 0.8) + vec2(i * 17.3, i * 31.7);
		vec2 cell_id = floor(grid_uv);
		vec2 cell_f = fract(grid_uv) - vec2(0.5);

		vec2 rnd = hash2D(cell_id + vec2(i * 47.1, i * 73.9));
		float period = 0.7 + rnd.x * 0.6;
		float phase = fract((time * 1.2 + rnd.y * 3.0) / period);

		float ring_radius = phase * 0.45;
		float d = length(cell_f - (rnd - vec2(0.5)) * 0.25);

		float wave = sin((d - ring_radius) * 40.0) * exp(-phase * 3.8) * exp(-abs(d - ring_radius) * 22.0);
		float ring_mask = smoothstep(0.0, 0.10, phase) * smoothstep(1.0, 0.65, phase);

		vec2 dir = normalize(cell_f + vec2(0.0001));
		total_ripple += dir * (wave * ring_mask * 0.08 * intensity);
	}
	return total_ripple;
}

void fragment() {
	// 0. Single-layer shell & orientation culling for inside-out cylindrical habitat
	float cam_r = length(CAMERA_POSITION_WORLD.xy);
	bool is_camera_underwater = (cam_r > cylinder_radius);

	if (!is_camera_underwater) {
		// Camera is inside habitat (on ground or in air): only render inward front faces
		if (!FRONT_FACING) {
			discard;
		}
	} else {
		// Camera is physically submerged under water: only render underside back faces
		if (FRONT_FACING) {
			discard;
		}
	}

	// Sample terrain elevation at this cylinder coordinate
	float terrain_elev = texture(elevation_map, vec2(map_uv.x + 0.5 / elevation_map_size.x, (clamp(map_uv.y, 0.0, 1.0) * (elevation_map_size.y - 1.0) + 0.5) / elevation_map_size.y)).r * max_elevation;

	// Water volume definition: only exist in basins, lakes, and river channels below sea level
	if (terrain_elev >= water_level + 0.15) {
		discard;
	}

	// Physical water column depth (from water level down to seabed)
	float water_depth = clamp(water_level - terrain_elev, 0.0, water_level);

	// Distance from camera to smoothly attenuate micro-ripples in the far field
	float dist_to_cam = length(world_pos - CAMERA_POSITION_WORLD);
	float ripple_atten = clamp(1.0 - (dist_to_cam - 60.0) / 240.0, 0.0, 1.0);
	vec3 perturbed_normal = NORMAL;

	float arc_dist = map_uv.x * (6.28318530718 * cylinder_radius);
	vec2 surface_pos = vec2(arc_dist, world_pos.z);

	if (ripple_atten > 0.001) {
		vec2 w_offset = get_wave_offset(surface_pos, TIME, wave_speed) * ripple_atten;
		vec3 ripple_perturb = TANGENT * w_offset.x + BINORMAL * w_offset.y;
		perturbed_normal = normalize(NORMAL + ripple_perturb);
	}

	// Dynamic Raindrop Surface Ripples
	float rain_atten = clamp(1.0 - (dist_to_cam - 40.0) / 180.0, 0.0, 1.0);
	if (rain_atten > 0.001 && is_snow_mode < 0.5 && precipitation_rate > 0.05) {
		vec2 rain_offset = get_raindrop_ripples(surface_pos, TIME, precipitation_rate) * rain_atten;
		vec3 rain_perturb = TANGENT * rain_offset.x + BINORMAL * rain_offset.y;
		perturbed_normal = normalize(perturbed_normal + rain_perturb);
	}

	// World-space reflection vector to calculate continuous reflection of the central axis light bar
	vec3 view_dir_world = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec3 norm_world = normalize((INV_VIEW_MATRIX * vec4(perturbed_normal, 0.0)).xyz);
	vec3 refl_world = reflect(view_dir_world, norm_world);

	float refl_xy_sq = dot(refl_world.xy, refl_world.xy);
	float axis_reflection_glint = 0.0;
	if (refl_xy_sq > 0.0001) {
		float t_closest = -dot(world_pos.xy, refl_world.xy) / refl_xy_sq;
		if (t_closest > 0.0) {
			vec2 p_closest_xy = world_pos.xy + refl_world.xy * t_closest;
			float dist_to_axis = length(p_closest_xy);
			float z_closest = world_pos.z + refl_world.z * t_closest;

			if (abs(z_closest) <= cylinder_length * 0.5 + 400.0) {
				// Continuous specular reflection line along the central light bar axis
				float line_width = 140.0;
				axis_reflection_glint = exp(-pow(dist_to_axis / line_width, 2.0));
			}
		}
	}

	// Physical Beer-Lambert optical depth absorption
	vec3 extinction = extinction_rgb;
	vec3 transmit = exp(-extinction * water_depth);
	vec3 water_body = mix(deep_color.rgb, shallow_color.rgb, transmit.r);

	// Animated Shoreline Foam Lapping
	float foam_mask = 0.0;
	if (water_depth < 2.0) {
		float wave_lap = sin(TIME * 2.2 * wave_speed - water_depth * 5.0);
		float foam_noise = sin(arc_dist * 0.12 + world_pos.z * 0.18 + TIME * 0.9) * 0.5 + 0.5;
		float foam_edge = smoothstep(0.30, 0.75, wave_lap + foam_noise * 0.50);
		float depth_falloff = 1.0 - (water_depth / 2.0);
		foam_mask = clamp(foam_edge * depth_falloff * 1.10, 0.0, 1.0);
	}

	// Exact Schlick Fresnel reflection for water-air interface (R0 = 0.02)
	float ndotv = clamp(dot(perturbed_normal, VIEW), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - ndotv, 5.0);
	vec3 sky_reflection = mix(air_color.rgb * 1.05, reflection_color.rgb, fresnel);
	vec3 final_color = mix(water_body, sky_reflection, fresnel * 0.35);

	// Foam coloring
	vec3 foam_rgb = foam_color.rgb;
	final_color = mix(final_color, foam_rgb, foam_mask * 0.75);

	// Surface water volume opacity (rich, visible water body when viewed from above)
	float depth_ratio = 1.0 - exp(-water_depth * 0.22);
	float base_alpha = mix(shallow_color.a, deep_color.a, depth_ratio);
	float final_alpha = clamp(base_alpha + fresnel * 0.20 + foam_mask * 0.40, 0.25, 0.85);

	// Axial lighting spectrum & diurnal gradient
	vec3 target_air_color = air_color.rgb;
	vec3 axial_col = vec3(1.0);
	float axial_lum = 1.0;
	if (axial_light_enabled > 0.5) {
		float t_z = clamp((world_pos.z + cylinder_length * 0.5) / cylinder_length, 0.0, 1.0);
		vec4 axial_light = texture(axial_light_lut, vec2(t_z, 0.5));
		axial_col = axial_light.rgb;
		axial_lum = clamp(axial_light.a, 0.0, 1.5);
		target_air_color = air_color.rgb * axial_col * axial_lum;
	}

	// Weather and cloud overcast dimming
	float c_norm = clamp(cloud_coverage, 0.0, 1.0);
	float cov_dim = (c_norm <= 0.50) ? mix(1.0, 0.95, c_norm / 0.50) : mix(0.95, 0.35, (c_norm - 0.50) / 0.50);
	float thick_norm = clamp((cloud_thickness - 100.0) / 700.0, 0.0, 1.0);
	float thick_dim = mix(1.0, 0.40, thick_norm);
	float weather_dim = cov_dim * thick_dim;

	// Check if viewing the water surface from below (camera underwater)
	if (is_camera_underwater) {
		// Surface light transmission & caustics when viewed from below
		float under_c1 = sin(surface_pos.x * 0.15 + TIME * 2.2 * wave_speed) * cos(surface_pos.y * 0.18 - TIME * 1.8 * wave_speed);
		float under_c2 = cos(surface_pos.x * 0.28 - TIME * 1.5 * wave_speed) * sin(surface_pos.y * 0.24 + TIME * 2.4 * wave_speed);
		float under_caustics = pow(clamp((under_c1 + under_c2) * 0.5 + 0.5, 0.0, 1.0), 2.5);
		vec3 caustic_glow = caustic_color.rgb * (under_caustics * 0.35 * clamp(axial_lum, 0.0, 1.5));

		// Light transmission from central light bar and sky through water surface
		vec3 sky_transmission = air_color.rgb * axial_col * (0.8 + 0.65 * axial_lum);
		final_color = sky_transmission + caustic_glow + axial_col * (axis_reflection_glint * 0.85);
		final_alpha = 0.05;
	} else {
		// Focused directional specular sparkle and glint (no opaque washing out)
		float sun_glint = clamp(dot(refl_world, -view_dir_world), 0.0, 1.0);
		float micro_sparkle = pow(sun_glint, 64.0) * axis_reflection_glint * ripple_atten;
		float specular_beam = pow(sun_glint, 32.0) * axis_reflection_glint * 0.35;
		final_color += axial_col * (specular_beam + micro_sparkle * 1.2) * (clamp(axial_lum, 0.0, 1.5) * weather_dim);
	}

	// Atmospheric aerial perspective across cylinder
	float air_factor = clamp((dist_to_cam - air_distance_min) / max(air_distance_max - air_distance_min, 1.0), 0.0, 1.0);
	float air_scatter = 1.0 - exp(-air_factor * 2.8);
	float fog_blend = clamp(air_scatter * air_density, 0.0, 1.0);
	final_color = mix(final_color, target_air_color, fog_blend);
	final_alpha = mix(final_alpha, 0.85, fog_blend * 0.50);

	vec3 cool_overcast_tint = overcast_color.rgb;
	float blue_shift = smoothstep(0.35, 1.0, c_norm) * 0.75;
	vec3 weather_modulation = mix(vec3(1.0), cool_overcast_tint, blue_shift) * weather_dim;

	final_color *= weather_modulation;

	ALBEDO = final_color;
	NORMAL = perturbed_normal;
	ALPHA = final_alpha;
	ROUGHNESS = mix(roughness, 0.02, 1.0 - ripple_atten);
	SPECULAR = specular * weather_dim;
	METALLIC = 0.04;
}
