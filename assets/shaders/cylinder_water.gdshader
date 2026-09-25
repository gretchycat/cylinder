shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.14, 0.58, 0.82, 0.62);
uniform vec4 deep_color : source_color = vec4(0.02, 0.16, 0.38, 0.90);
uniform sampler2D elevation_map : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float cylinder_radius = 3980.0;
uniform float cylinder_length = 8000.0;
uniform float water_level = 20.0;
uniform float max_elevation = 100.0;
uniform float wave_speed : hint_range(0.0, 5.0) = 0.5;
uniform float roughness : hint_range(0.0, 1.0) = 0.06;
uniform float specular : hint_range(0.0, 1.0) = 0.92;

uniform vec4 air_color : source_color = vec4(0.52, 0.72, 0.88, 1.0);
uniform float air_density : hint_range(0.0, 1.0) = 0.65;
uniform float air_distance_min = 200.0;
uniform float air_distance_max = 8000.0;

varying vec3 world_pos;
varying vec2 map_uv;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float angle = atan(world_pos.y, world_pos.x);
	if (angle < 0.0) {
		angle += 6.28318530718;
	}
	float u = angle / 6.28318530718;
	float v = clamp((world_pos.z + cylinder_length * 0.5) / cylinder_length, 0.0, 1.0);
	map_uv = vec2(u, v);
}

void fragment() {
	// Sample terrain elevation at this cylinder coordinate
	float terrain_elev = texture(elevation_map, map_uv).r * max_elevation;

	// Water volume definition: only exist in basins, lakes, and river channels below sea level
	if (terrain_elev >= water_level + 0.2) {
		discard;
	}

	// Physical water column depth (from water level down to seabed)
	float water_depth = clamp(water_level - terrain_elev, 0.0, water_level);
	float depth_norm = clamp(water_depth / 16.0, 0.0, 1.0);

	// Distance from camera to eliminate far-field moire patterns
	float dist_to_cam = length(world_pos - CAMERA_POSITION_WORLD);
	// Smoothly attenuate wave ripples from full intensity at 0..50m to zero at > 250m
	float ripple_atten = clamp(1.0 - (dist_to_cam - 50.0) / 200.0, 0.0, 1.0);

	// Low-frequency scrolling surface waves (smooth, gentle, anti-aliased)
	float arc_dist = map_uv.x * (6.28318530718 * cylinder_radius);
	vec2 uv1 = vec2(arc_dist, world_pos.z) * 0.03 + vec2(TIME * 0.03 * wave_speed, TIME * 0.015 * wave_speed);
	vec2 uv2 = vec2(arc_dist * 0.7 - world_pos.z * 0.5, world_pos.z * 0.7 + arc_dist * 0.4) * 0.025 - vec2(TIME * 0.02 * wave_speed, TIME * 0.025 * wave_speed);

	float r1 = sin(uv1.x * 2.5 + uv1.y * 1.8);
	float r2 = cos(uv2.x * 3.0 - uv2.y * 2.2);
	vec3 ripple_norm = normalize(vec3((r1 * 0.10) * ripple_atten, (r2 * 0.10) * ripple_atten, 1.0));

	// Tint the volume where the water exists: shallow translucent aqua to deep oceanic blue
	vec3 volume_water_color = mix(shallow_color.rgb, deep_color.rgb, depth_norm);

	// Fresnel effect for realistic surface reflectivity at glancing angles
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.5);
	vec3 final_color = mix(volume_water_color, vec3(0.85, 0.95, 1.0), fresnel * 0.35);

	// Depth-dependent volume opacity: shoreline is transparent, deep water is rich and dense
	float base_alpha = mix(shallow_color.a, deep_color.a, depth_norm);
	float final_alpha = clamp(base_alpha + fresnel * 0.25, 0.35, 0.95);

	// Atmospheric aerial perspective: tint distant views across the 8 km cylinder
	float air_factor = clamp((dist_to_cam - air_distance_min) / max(air_distance_max - air_distance_min, 1.0), 0.0, 1.0);
	float air_scatter = 1.0 - exp(-air_factor * 1.8);
	final_color = mix(final_color, air_color.rgb, air_scatter * air_density);
	final_alpha = mix(final_alpha, 0.98, air_scatter * air_density * 0.7);

	ALBEDO = final_color;
	NORMAL = ripple_norm;
	ALPHA = final_alpha;
	ROUGHNESS = mix(roughness, 0.03, 1.0 - ripple_atten); // Perfectly calm mirror finish at distance
	SPECULAR = specular;
	METALLIC = 0.05;
}
