shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, diffuse_burley, specular_disabled;

// Atmospheric Cloud Layer for O'Neill Cylinder (~1.25 km overhead)
// Render Priority = 4
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
uniform float coriolis_spin_direction = 1.0;      // +1.0 for CCW, -1.0 for CW
uniform vec2 cloud_deck_offset = vec2(0.0, 0.0); // Continuous monotonic (u_offset, v_offset)

// Pre-baked seamless cloud noise texture
uniform sampler2D cloud_noise_tex : hint_default_transparent, filter_linear_mipmap, repeat_enable;

// Cloud Albedo Reflectance
uniform vec4 cloud_color_day : source_color = vec4(0.85, 0.86, 0.88, 1.0);
uniform vec4 cloud_color_storm : source_color = vec4(0.20, 0.22, 0.26, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.45, 0.48, 0.52, 1.0);
uniform vec4 dust_tint : source_color = vec4(0.90, 0.84, 0.72, 1.0);

uniform vec4 air_color : source_color = vec4(0.52, 0.72, 0.88, 1.0);
uniform float air_density : hint_range(0.0, 3.0) = 1.0;
uniform float air_distance_min = 200.0;
uniform float air_distance_max = 18000.0;

uniform sampler2D axial_light_lut : hint_default_white, filter_linear, repeat_disable;
uniform float axial_light_enabled = 1.0;
uniform float global_light_intensity = 3.5;

varying vec3 world_pos;
varying vec3 local_normal;
varying vec2 v_mesh_uv;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_normal = normalize(NORMAL);
	v_mesh_uv = UV;
}

void fragment() {
	// 0. Single-layer shell culling: eliminate far-side transparent tube circular cross-section interference
	vec3 radial_norm = normalize(vec3(world_pos.x, world_pos.y, 0.0));
	vec3 cam_to_frag = world_pos - CAMERA_POSITION_WORLD;
	float cam_r = length(CAMERA_POSITION_WORLD.xy);
	float cloud_r = cylinder_radius - cloud_altitude;

	if (cam_r >= cloud_r) {
		// Camera is outside cloud cylinder (on ground looking up): only render near canopy facing camera
		if (dot(radial_norm, cam_to_frag) > 0.0) {
			discard;
		}
	} else {
		// Camera is inside cloud cylinder (in flight looking down/out): only render inner shell facing axis
		if (dot(radial_norm, cam_to_frag) < 0.0) {
			discard;
		}
	}

	// 1. Unified rigid Coriolis atmospheric coordinate flow
	float u_flow = v_mesh_uv.x + cloud_deck_offset.x;
	float v_flow = v_mesh_uv.y + cloud_deck_offset.y;

	vec2 cloud_coords = vec2(u_flow * 4.0, v_flow * 2.0);

	// 2. High-speed pre-baked texture sampling
	float cloud_shape = texture(cloud_noise_tex, cloud_coords).r;

	// Optical depth & soft volumetric alpha
	float cov_remap = clamp(cloud_coverage, 0.0, 1.0);
	if (cov_remap <= 0.001) {
		discard;
	}

	float threshold = (1.0 - (cov_remap * 0.90)) * 0.85;
	float wisp = clamp((cloud_shape - threshold) / max(cloud_softness, 0.05), 0.0, 1.0);
	float wisp_smooth = smoothstep(0.0, 1.0, wisp);

	float thick_norm = clamp(cloud_thickness / 300.0, 0.3, 1.6);
	float opt_depth = wisp_smooth * cloud_density * thick_norm * (0.35 + cov_remap * 0.65);

	// End cap soft edge fading
	float z_half = cylinder_length * 0.5;
	float endcap_fade = 1.0 - smoothstep(z_half * 0.70, z_half * 0.95, abs(world_pos.z));
	opt_depth *= endcap_fade;

	if (opt_depth < 0.002) {
		discard;
	}

	float final_alpha = clamp(1.0 - exp(-opt_depth * 3.5), 0.0, 0.98);

	// 3. Reflective Cloud Albedo (Zero Emission - Lighting matches scene light dynamically)
	float cov_factor = smoothstep(0.30, 0.95, cloud_coverage);
	float thick_factor = clamp((cloud_thickness - 150.0) / 550.0, 0.0, 1.0);
	float storm_factor = clamp(cov_factor * 0.50 + thick_factor * 0.35 + (cov_factor * thick_factor) * 0.40, 0.0, 1.0);

	vec3 base_cloud_col = mix(cloud_color_day.rgb, cloud_color_storm.rgb, storm_factor);
	vec3 base_shadow_col = mix(cloud_shadow_color.rgb, cloud_color_storm.rgb * 0.6, storm_factor);

	float cloud_highlight = smoothstep(0.35, 0.90, wisp_smooth);
	vec3 cloud_albedo = mix(base_cloud_col * base_shadow_col, base_cloud_col, cloud_highlight);

	if (dust_density > 0.02) {
		cloud_albedo = mix(cloud_albedo, cloud_albedo * dust_tint.rgb, dust_density * 0.35);
	}

	// 4. Atmospheric aerial distance perspective and underwater column attenuation
	float dist_to_cam = length(world_pos - CAMERA_POSITION_WORLD);
	float water_r = cylinder_radius - 20.0;
	bool is_cam_underwater = (cam_r > water_r);

	if (is_cam_underwater) {
		// Water column depth attenuation and aquatic blue/cyan optical fog when submerged
		float water_visibility = 180.0;
		float water_fog = 1.0 - exp(-dist_to_cam / water_visibility);
		vec3 deep_water_fog = vec3(0.015, 0.18, 0.38);
		cloud_albedo = mix(cloud_albedo, deep_water_fog, water_fog * 0.94);
		cloud_albedo = mix(cloud_albedo, vec3(0.03, 0.28, 0.48), 0.25);
	} else {
		float air_factor = clamp((dist_to_cam - air_distance_min) / max(air_distance_max - air_distance_min, 1.0), 0.0, 1.0);
		float air_scatter = 1.0 - exp(-air_factor * 1.8);
		float fog_blend = clamp(air_scatter * air_density, 0.0, 1.0);
		cloud_albedo = mix(cloud_albedo, air_color.rgb, fog_blend * 0.40);
	}

	ALBEDO = cloud_albedo;
	ALPHA = final_alpha;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	EMISSION = vec3(0.0);
}
