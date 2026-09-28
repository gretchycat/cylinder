shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 base_color : source_color = vec4(0.35, 0.72, 0.22, 1.0);
uniform vec4 tip_color : source_color = vec4(0.55, 0.88, 0.32, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float wind_speed : hint_range(0.0, 10.0) = 2.4;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.22;
uniform float wind_turbulence : hint_range(0.0, 2.0) = 0.50;
uniform float max_distance : hint_range(50.0, 1000.0) = 500.0;
uniform float fade_distance : hint_range(10.0, 400.0) = 120.0;
uniform bool is_flower = false;
uniform bool is_stone = false;

uniform float cylinder_radius = 4000.0;
uniform float water_level = 20.0;

uniform vec4 air_color : source_color = vec4(0.52, 0.72, 0.88, 1.0);
uniform float air_density : hint_range(0.0, 3.0) = 1.0;
uniform float air_distance_min = 200.0;
uniform float air_distance_max = 18000.0;

varying vec3 v_world_pos;
varying float v_dist_fade;
varying vec4 v_instance_color;

void vertex() {
	v_instance_color = COLOR;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Camera distance fade factor: 1.0 (near/solid) down to 0.0 (far/transparent)
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float d = length(v_world_pos - cam_pos);
	v_dist_fade = clamp((max_distance - d) / max(fade_distance, 1.0), 0.0, 1.0);

	// Wind sway only affects the top of the vegetation (VERTEX.y > 0.05)
	if (!is_stone && VERTEX.y > 0.05) {
		float height_factor = clamp(VERTEX.y * 0.8, 0.0, 1.0);
		float time_offset = TIME * wind_speed + (v_world_pos.x + v_world_pos.z) * 0.15;
		
		float sway_x = sin(time_offset) * wind_strength;
		float sway_z = cos(time_offset * 1.3 + sin(time_offset * 0.7)) * (wind_strength * wind_turbulence);
		
		VERTEX.x += sway_x * height_factor;
		VERTEX.z += sway_z * height_factor;
	}
}

void fragment() {
	if (v_dist_fade <= 0.001) {
		discard;
	}

	// 4x4 Bayer Dither Matrix for continuous, sorting-artifact-free distance opacity dissolve
	const mat4 bayer_matrix = mat4(
		vec4( 1.0,  9.0,  3.0, 11.0) / 17.0,
		vec4(13.0,  5.0, 15.0,  7.0) / 17.0,
		vec4( 4.0, 12.0,  2.0, 10.0) / 17.0,
		vec4(16.0,  8.0, 14.0,  6.0) / 17.0
	);
	ivec2 pixel_coord = ivec2(FRAGCOORD.xy) % 4;
	float dither_threshold = bayer_matrix[pixel_coord.x][pixel_coord.y];

	// Smooth cubic ease for gradual distance opacity transition
	float smooth_fade = smoothstep(0.0, 1.0, v_dist_fade);
	if (smooth_fade < dither_threshold) {
		discard;
	}

	vec4 col = base_color;
	
	// Blend tip color based on vertical UV or mesh height
	if (!is_stone) {
		float height_blend = clamp(UV.y, 0.0, 1.0);
		col = mix(base_color, tip_color, height_blend);
	}

	// Instance color modulation
	if (v_instance_color.a > 0.01) {
		if (is_flower) {
			// Flower petals inherit instance blossom color
			col = mix(col, v_instance_color, v_instance_color.a);
		} else {
			// Vegetation/stone subtle tint variation
			col.rgb *= v_instance_color.rgb;
		}
	}

	// Camera underwater check: looking through water column onto land/clutter
	float cam_dist = length(v_world_pos - INV_VIEW_MATRIX[3].xyz);
	float cam_r = length(INV_VIEW_MATRIX[3].xy);
	float water_r = cylinder_radius - water_level;
	bool is_camera_underwater = cam_r > water_r;

	if (is_camera_underwater) {
		// Water column depth attenuation and aquatic blue/cyan optical fog
		float water_visibility = 180.0;
		float water_fog = 1.0 - exp(-cam_dist / water_visibility);
		vec3 deep_water_fog = vec3(0.015, 0.18, 0.38);
		col.rgb = mix(col.rgb, deep_water_fog, water_fog * 0.94);
		col.rgb = mix(col.rgb, vec3(0.03, 0.28, 0.48), 0.25);
	} else {
		// Atmospheric aerial distance perspective: harmonize with terrain depth haze
		float air_factor = clamp((cam_dist - air_distance_min) / max(air_distance_max - air_distance_min, 1.0), 0.0, 1.0);
		float air_scatter = 1.0 - exp(-air_factor * 1.8);
		col.rgb = mix(col.rgb, air_color.rgb, air_scatter * air_density * 0.5);
	}

	ALBEDO = col.rgb;
	ROUGHNESS = roughness;
	METALLIC = is_stone ? 0.04 : 0.0;
	
	// Translucent backlight approximation for thin foliage
	if (!is_stone) {
		BACKLIGHT = col.rgb * 0.35;
	}
}
