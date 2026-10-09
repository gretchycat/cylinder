shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 tip_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 0 = flat, 1 = vertical (linear), 2 = outward from local XZ center (radial).
uniform int gradient_mode = 0;
uniform float gradient_extent = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float wind_speed : hint_range(0.0, 10.0) = 2.4;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.22;
uniform float wind_turbulence : hint_range(0.0, 2.0) = 0.50;
uniform float max_distance : hint_range(50.0, 1000.0) = 500.0;
uniform float fade_distance : hint_range(10.0, 400.0) = 120.0;

uniform float cylinder_radius = 4000.0;
uniform float water_level = 20.0;

uniform vec4 deep_water_color : source_color;
uniform vec4 air_color : source_color = vec4(0.52, 0.72, 0.88, 1.0);
uniform float air_density : hint_range(0.0, 3.0) = 1.0;
uniform float air_distance_min = 200.0;
uniform float air_distance_max = 18000.0;
uniform float cylinder_length = 18000.0;
uniform sampler2D axial_light_lut : hint_default_white, filter_linear, repeat_disable;
uniform float axial_light_enabled = 1.0;

varying vec3 v_world_pos;
varying float v_dist_fade;
varying float v_gradient_amount;
varying vec4 v_instance_color;
varying float v_tint_weight;
varying vec4 v_vertex_color;

void vertex() {
	v_instance_color = INSTANCE_CUSTOM;
	v_vertex_color = COLOR;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Clutter gradients are fixed in model space
	if (gradient_mode == 1) {
		v_gradient_amount = clamp(VERTEX.y / max(gradient_extent, 0.001), 0.0, 1.0);
	} else if (gradient_mode == 2) {
		v_gradient_amount = clamp(length(VERTEX.xz) / max(gradient_extent, 0.001), 0.0, 1.0);
	} else {
		v_gradient_amount = 0.0;
	}

	// Model-defined per-vertex tint weight mask (COLOR.a). Vertices with alpha 0.0 stay untinted
	// (retaining model's vertex RGB), while vertices with alpha 1.0 receive full instance palette tinting.
	// If gradient_mode > 0 and COLOR.a is uniform 1.0, fall back to v_gradient_amount.
	if (gradient_mode > 0 && COLOR.a >= 0.99) {
		v_tint_weight = v_gradient_amount;
	} else {
		v_tint_weight = COLOR.a;
	}

	// Camera distance fade factor: 1.0 (near/solid) down to 0.0 (far/transparent)
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float d = length(v_world_pos - cam_pos);
	if (d >= max_distance) {
		VERTEX = vec3(0.0);
		v_dist_fade = 0.0;
	} else {
		v_dist_fade = clamp((max_distance - d) / max(fade_distance, 1.0), 0.0, 1.0);
	}

	// Wind sway affects geometry when wind_strength is active (VERTEX.y > 0.05)
	if (wind_strength > 0.001 && VERTEX.y > 0.05) {
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

	vec3 gradient_col = mix(base_color.rgb, tip_color.rgb, v_gradient_amount);
	vec3 mesh_albedo = v_vertex_color.rgb * gradient_col;
	vec3 instance_tint = mix(vec3(1.0), v_instance_color.rgb, v_tint_weight);
	vec4 tex_sample = texture(albedo_texture, UV);

	vec3 col = clamp(mesh_albedo * instance_tint * tex_sample.rgb, vec3(0.0), vec3(0.85));
	float alpha = tex_sample.a;
	if (alpha * smooth_fade < dither_threshold) {
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
		float fog_factor = clamp(water_fog * 0.88, 0.0, 0.92);
		col = col * (1.0 - fog_factor);
		EMISSION = deep_water_fog * fog_factor;
	} else {
		// Atmospheric aerial distance perspective: exact match with terrain depth haze
		vec3 fog_color = air_color.rgb;
		if (axial_light_enabled > 0.5) {
			float v_coord = clamp(v_world_pos.z / cylinder_length + 0.5, 0.0, 1.0);
			vec4 light = texture(axial_light_lut, vec2(v_coord, 0.5));
			fog_color *= light.rgb * clamp(light.a, 0.0, 1.5);
		}
		float fog = clamp((1.0 - exp(-max(cam_dist - air_distance_min, 0.0) / max(air_distance_max - air_distance_min, 1.0) * 2.8)) * air_density, 0.0, 1.0);
		col = mix(col, fog_color, fog);
	}

	ALBEDO = col;
	ROUGHNESS = roughness;
	METALLIC = metallic;

	// Ensure double-sided foliage receives ambient/point lighting regardless of
	// card winding.  FRONT_FACING is tied to raster winding, which can leave
	// some crossed-card blades dark when their outer face is reversed.  Orient
	// the interpolated normal toward the camera instead, giving both sides of a
	// thin foliage card the same useful lighting response.
	NORMAL = normalize(NORMAL);
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	
	// Translucent backlight approximation for thin foliage when wind_strength > 0
	if (wind_strength > 0.001) {
		BACKLIGHT = col * 0.05;
	}
}

