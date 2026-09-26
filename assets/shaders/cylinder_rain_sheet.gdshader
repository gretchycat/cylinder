shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, unshaded;

// Rain Sheet Shader for O'Neill Cylinder Atmospheric Weather
// Renders scrolling pre-rendered raindrop / snowflake streaks on layered hexagonal sheets around the player
uniform sampler2D rain_texture : filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(3.0, 2.0);
uniform vec2 uv_scroll_offset = vec2(0.0, 0.0);
uniform vec4 rain_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rain_alpha_multiplier : hint_range(0.0, 2.0) = 1.0;

// Lighting & Intensity synchronization
uniform sampler2D axial_light_lut : hint_default_white, filter_linear, repeat_disable;
uniform float axial_light_enabled = 1.0;
uniform float global_light_intensity = 3.5;
uniform float cylinder_length = 18000.0;
uniform vec4 night_tint : source_color = vec4(0.18, 0.20, 0.32, 1.0);

// Distance fading to avoid camera near-clip popping and blend with horizon depth
uniform float near_fade_min = 0.05;
uniform float near_fade_max = 0.35;
uniform float far_fade_min = 38.0;
uniform float far_fade_max = 58.0;

varying vec3 v_world_pos;
varying float v_vert_y;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_vert_y = UV.y;
}

void fragment() {
	vec2 scrolled_uv = UV * uv_scale + uv_scroll_offset;
	vec4 tex = texture(rain_texture, scrolled_uv);

	float dist = length(v_world_pos - CAMERA_POSITION_WORLD);
	float near_fade = smoothstep(near_fade_min, near_fade_max, dist);
	float far_fade = 1.0 - smoothstep(far_fade_min, far_fade_max, dist);

	// Vertical edge feathering: fade alpha to 0 at bottom and top of sheet
	float vertical_fade = smoothstep(0.0, 0.14, v_vert_y) * (1.0 - smoothstep(0.86, 1.0, v_vert_y));

	// Volumetric Solar & Axial Light Sampling
	float t_z = clamp((v_world_pos.z + cylinder_length * 0.5) / cylinder_length, 0.0, 1.0);
	vec3 axial_col = vec3(1.0);
	float axial_lum = 1.0;

	if (axial_light_enabled > 0.5) {
		vec4 axial_light = texture(axial_light_lut, vec2(t_z, 0.5));
		axial_col = axial_light.rgb;
		axial_lum = clamp(axial_light.a, 0.0, 1.5);
	}

	float light_scale = clamp(global_light_intensity / 3.5, 0.04, 1.5);
	vec3 lit_color = mix(night_tint.rgb, axial_col.rgb, clamp(axial_lum, 0.0, 1.0)) * light_scale;

	float total_alpha = tex.a * rain_tint.a * near_fade * far_fade * rain_alpha_multiplier * vertical_fade;

	ALBEDO = tex.rgb * rain_tint.rgb * lit_color;
	ALPHA = total_alpha * clamp(light_scale * 1.35, 0.25, 1.0);
}

