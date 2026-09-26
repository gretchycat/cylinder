shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, diffuse_burley, specular_disabled;

// Atmospheric Far Cloud Layer for O'Neill Cylinder (Opposite side across axis, ~6.75 km distance)
// Render Priority = 4 (Renders after far water/terrain P0, before near clouds P5)
uniform float cylinder_radius = 4000.0;
uniform float cylinder_length = 18000.0;
uniform float cloud_altitude = 1250.0;    // Meters above ground (1.0 to 1.5 km)
uniform float cloud_thickness = 250.0;   // Vertical deck thickness in meters (50m - 800m)

// Weather & Humidity parameters
uniform float humidity_density = 14.5;    // g/m³
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_density : hint_range(0.0, 3.0) = 1.0;
uniform float cloud_softness : hint_range(0.01, 1.0) = 0.25;
uniform float dust_density : hint_range(0.0, 1.0) = 0.20;

// Coriolis & Wind flow vectors (updated by WeatherSystem)
uniform vec2 wind_velocity = vec2(0.003, 0.001); // (theta_speed, z_speed)
uniform float coriolis_spin_direction = 1.0;      // +1.0 for CCW, -1.0 for CW
uniform float time_scale = 0.05;
uniform vec2 cloud_deck_offset = vec2(0.0, 0.0); // (theta_offset_radians, z_offset_meters)

// Axial Lighting & Atmosphere synchronization
uniform vec4 cloud_color_day : source_color = vec4(0.98, 0.98, 1.0, 1.0);
uniform vec4 cloud_color_sunset : source_color = vec4(1.0, 0.65, 0.40, 1.0);
uniform vec4 cloud_color_night : source_color = vec4(0.18, 0.16, 0.32, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.55, 0.60, 0.70, 1.0);
uniform vec4 dust_tint : source_color = vec4(0.92, 0.85, 0.72, 1.0);

uniform vec4 air_color : source_color = vec4(0.52, 0.72, 0.88, 1.0);
uniform float air_density : hint_range(0.0, 3.0) = 1.25;
uniform float air_distance_min = 200.0;
uniform float air_distance_max = 18000.0;

uniform sampler2D axial_light_lut : hint_default_white, filter_linear, repeat_disable;
uniform float axial_light_enabled = 1.0;
uniform float global_light_intensity = 3.5;

varying vec3 world_pos;
varying vec3 local_normal;

// Fractional Brownian Motion noise for fluffy cumulus clouds
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);

	float a = hash(i + vec2(0.0, 0.0));
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	mat2 rot = mat2(vec2(cos(0.5), sin(0.5)), vec2(-sin(0.5), cos(0.5)));
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = rot * p * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_normal = normalize(NORMAL);
}

void fragment() {
	// Near / Far hemispherical partition based on camera radial azimuth
	vec2 cam_xy = CAMERA_POSITION_WORLD.xy;
	float cam_len = length(cam_xy);
	float side_dot = -1.0;
	if (cam_len > 1.0) {
		side_dot = dot(normalize(world_pos.xy), cam_xy / cam_len);
	}
	if (side_dot > 0.20) {
		discard; // Far pass only renders far hemisphere across axis (side_dot <= 0.20)
	}
	float seam_blend = smoothstep(0.20, -0.20, side_dot);

	float angle = atan(world_pos.y, world_pos.x);
	if (angle < 0.0) {
		angle += 6.28318530718;
	}

	// 1. Helical coordinate flow driven by Coriolis circulation from end caps
	float z_norm = world_pos.z / (cylinder_length * 0.5); // -1.0 at South Cap to +1.0 at North Cap
	float z_dist = world_pos.z;

	// Coriolis spiral distortion: rising humid air turns prograde (+theta) or retrograde (-theta)
	float coriolis_shear = -z_norm * 0.45 * coriolis_spin_direction;
	float flow_theta = angle + coriolis_shear + cloud_deck_offset.x + (wind_velocity.x * coriolis_spin_direction) * (TIME * time_scale);
	float flow_z = ((z_dist + cloud_deck_offset.y) * 0.0006) + wind_velocity.y * (TIME * time_scale);

	// Scale UV with cloud thickness: thicker clouds have more billowing internal structures
	float thickness_freq_mult = mix(0.85, 1.4, clamp(cloud_thickness / 400.0, 0.0, 2.0));
	vec2 uv_cloud1 = vec2(flow_theta * 4.0 * thickness_freq_mult, flow_z * 3.0 * thickness_freq_mult);
	vec2 uv_cloud2 = vec2(flow_theta * 8.0 - flow_z * 2.0, flow_z * 7.0 + flow_theta * 1.5) * thickness_freq_mult;

	// 2. Multi-scale cloud density computation
	float n1 = fbm(uv_cloud1);
	float n2 = fbm(uv_cloud2 + vec2(TIME * 0.005 * coriolis_spin_direction, 0.0));
	float cloud_shape = mix(n1, n2, 0.35);

	// Cloud cover and thickness influence on condensation threshold
	float thickness_boost = clamp(cloud_thickness / 300.0, 0.2, 2.0);
	float threshold = (1.0 - (cloud_coverage * 0.95)) * 0.82;

	float raw_alpha = smoothstep(threshold, threshold + cloud_softness, cloud_shape);
	float density = raw_alpha * cloud_density * thickness_boost * seam_blend;

	// End cap boundary fading (dissipates softly into clear air hundreds of meters before cylinder ends)
	float z_half = cylinder_length * 0.5;
	float endcap_fade = 1.0 - smoothstep(z_half * 0.65, z_half * 0.90, abs(world_pos.z));
	density *= endcap_fade;

	if (density < 0.005) {
		discard;
	}

	// 3. Volumetric Solar & Axial Light Sampling
	float t_z = clamp((world_pos.z + cylinder_length * 0.5) / cylinder_length, 0.0, 1.0);
	vec3 axial_col = vec3(1.0);
	float axial_lum = 1.0;

	if (axial_light_enabled > 0.5) {
		vec4 axial_light = texture(axial_light_lut, vec2(t_z, 0.5));
		axial_col = axial_light.rgb;
		axial_lum = clamp(axial_light.a, 0.0, 1.5);
	}

	// Blend cloud illumination based on axial diurnal cycle
	vec3 day_tint = cloud_color_day.rgb * axial_col;
	vec3 night_tint = cloud_color_night.rgb;
	vec3 illuminated_cloud = mix(night_tint, day_tint, clamp(axial_lum, 0.0, 1.0));

	// Incorporate atmospheric dust scattering into cloud illumination
	if (dust_density > 0.02) {
		illuminated_cloud = mix(illuminated_cloud, illuminated_cloud * dust_tint.rgb, dust_density * 0.45);
	}

	// Light scattering through cloud tops vs underbellies
	float cloud_top_light = smoothstep(threshold + 0.08, threshold + 0.38, cloud_shape);
	vec3 final_cloud_rgb = mix(illuminated_cloud * cloud_shadow_color.rgb, illuminated_cloud * 1.15, cloud_top_light);

	// 4. Atmospheric aerial perspective across cylinder diameter (~6.75 km distance)
	float dist_to_cam = length(world_pos - CAMERA_POSITION_WORLD);
	float air_factor = clamp((dist_to_cam - air_distance_min) / max(air_distance_max - air_distance_min, 1.0), 0.0, 1.0);
	float air_scatter = 1.0 - exp(-air_factor * 2.8);
	float fog_blend = clamp(air_scatter * air_density, 0.0, 1.0);
	vec3 target_air_color = air_color.rgb * mix(vec3(1.0), axial_col, 0.65);
	final_cloud_rgb = mix(final_cloud_rgb, target_air_color, fog_blend * 0.65);

	ALBEDO = final_cloud_rgb;
	ALPHA = clamp(density * 0.88, 0.0, 0.96);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
