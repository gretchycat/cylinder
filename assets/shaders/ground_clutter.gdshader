shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 base_color : source_color = vec4(0.35, 0.72, 0.22, 1.0);
uniform vec4 tip_color : source_color = vec4(0.55, 0.88, 0.32, 1.0);
// 0 = flat, 1 = vertical (linear), 2 = outward from local XZ center (radial).
uniform int gradient_mode = 0;
uniform float gradient_extent = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float wind_speed : hint_range(0.0, 10.0) = 2.4;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.22;
uniform float wind_turbulence : hint_range(0.0, 2.0) = 0.50;
uniform float max_distance : hint_range(50.0, 1000.0) = 500.0;
uniform float fade_distance : hint_range(10.0, 400.0) = 120.0;
uniform bool is_flower = false;
uniform bool is_mushroom = false;
uniform bool is_stone = false;

uniform float cylinder_radius = 4000.0;
uniform float water_level = 20.0;

uniform vec4 deep_water_color : source_color;
uniform vec4 air_color : source_color = vec4(0.52, 0.72, 0.88, 1.0);
uniform float air_density : hint_range(0.0, 3.0) = 1.0;
uniform float air_distance_min = 200.0;
uniform float air_distance_max = 18000.0;

varying vec3 v_world_pos;
varying float v_dist_fade;
varying float v_gradient_amount;
varying vec4 v_instance_color;

void vertex() {
	v_instance_color = INSTANCE_CUSTOM;
	// Rotate only each flower's petal head around its own axis. The per-instance
	// angle comes from MultiMesh custom data, so flowers still share one mesh.
	if (is_flower && COLOR.a > 0.65) {
		vec3 head_up = normalize(vec3(0.24, 0.96, -0.12));
		vec3 head_right = normalize(vec3(1.0, 0.0, 0.0) - head_up * head_up.x);
		vec3 head_forward = normalize(cross(head_up, head_right));
		vec3 head_center = vec3(0.0, gradient_extent * 0.86, 0.0);
		vec3 relative_vertex = VERTEX - head_center;
		float head_angle = INSTANCE_CUSTOM.x;
		float angle_cos = cos(head_angle);
		float angle_sin = sin(head_angle);
		float right_offset = dot(relative_vertex, head_right);
		float forward_offset = dot(relative_vertex, head_forward);
		float up_offset = dot(relative_vertex, head_up);
		float normal_right = dot(NORMAL, head_right);
		float normal_forward = dot(NORMAL, head_forward);
		float normal_up = dot(NORMAL, head_up);
		VERTEX = head_center
			+ head_right * (right_offset * angle_cos - forward_offset * angle_sin)
			+ head_forward * (right_offset * angle_sin + forward_offset * angle_cos)
			+ head_up * up_offset;
		NORMAL = normalize(
			head_right * (normal_right * angle_cos - normal_forward * angle_sin)
			+ head_forward * (normal_right * angle_sin + normal_forward * angle_cos)
			+ head_up * normal_up
		);
	}
	// Clutter gradients are fixed in model space, so evaluate them once per
	// vertex and interpolate across fragments instead of doing a radial length
	// (or mode branch) for every covered pixel.
	if (gradient_mode == 1) {
		v_gradient_amount = clamp(VERTEX.y / max(gradient_extent, 0.001), 0.0, 1.0);
	} else if (gradient_mode == 2) {
		v_gradient_amount = clamp(length(VERTEX.xz) / max(gradient_extent, 0.001), 0.0, 1.0);
	} else {
		v_gradient_amount = 0.0;
	}
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

	vec4 col = mix(base_color, tip_color, v_gradient_amount);

	col *= v_instance_color;
	if (col.a * smooth_fade < dither_threshold) {
		discard;
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
		vec3 deep_water_fog = deep_water_color.rgb;
		col.rgb = mix(col.rgb, deep_water_fog, water_fog * 0.94);
		col.rgb = mix(col.rgb, deep_water_color.rgb, 0.25);
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
