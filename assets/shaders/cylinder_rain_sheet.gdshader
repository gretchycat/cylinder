shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, unshaded, fog_disabled;

// Rain Sheet Shader for O'Neill Cylinder Atmospheric Weather
// Renders scrolling pre-rendered raindrop / snowflake streaks on layered hexagonal sheets around the player
uniform sampler2D rain_texture : hint_default_transparent, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(0.25, 0.25);
uniform vec2 uv_scroll_offset = vec2(0.0, 0.0);
uniform vec4 rain_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rain_alpha_multiplier : hint_range(0.0, 2.0) = 0.0;

// Lighting & Intensity synchronization
uniform sampler2D axial_light_lut : hint_default_white, filter_linear, repeat_disable;
uniform float axial_light_enabled = 1.0;
uniform float global_light_intensity = 3.5;
uniform float cylinder_length = 18000.0;
uniform float cloud_thickness = 250.0;
uniform vec4 night_tint : source_color = vec4(0.04, 0.04, 0.06, 1.0);

// Distance fading to avoid camera near-clip popping and blend with horizon depth
uniform float near_fade_min = 0.2;
uniform float near_fade_max = 1.0;
uniform float far_fade_min = 60.0;
uniform float far_fade_max = 95.0;

varying vec3 v_world_pos;
varying float v_norm_y;
varying float v_layer_speed;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_norm_y = UV2.y;
	v_layer_speed = UV2.x > 0.01 ? UV2.x : 1.0;
}

void fragment() {
	if (rain_alpha_multiplier <= 0.001) {
		discard;
	}

	vec2 layer_scroll = uv_scroll_offset * v_layer_speed;
	vec2 scrolled_uv = (UV + layer_scroll) * uv_scale;
	vec4 tex = texture(rain_texture, scrolled_uv);
	if (tex.a < 0.02) {
		discard;
	}

	float dist = length(v_world_pos - CAMERA_POSITION_WORLD);
	float near_fade = smoothstep(near_fade_min, near_fade_max, dist);
	float far_fade = 1.0 - smoothstep(far_fade_min, far_fade_max, dist);

	// Vertical edge feathering: fade alpha to 0 smoothly at bottom (0.0..0.08) and top (0.92..1.0)
	float vertical_fade = smoothstep(0.0, 0.08, v_norm_y) * (1.0 - smoothstep(0.92, 1.0, v_norm_y));

	// Volumetric Solar & Axial Light Sampling
	float t_z = clamp((v_world_pos.z + cylinder_length * 0.5) / cylinder_length, 0.0, 1.0);
	vec3 axial_col = vec3(1.0);
	float axial_lum = 1.0;

	if (axial_light_enabled > 0.5) {
		vec4 axial_light = texture(axial_light_lut, vec2(t_z, 0.5));
		axial_col = axial_light.rgb;
		axial_lum = clamp(axial_light.a, 0.0, 1.5);
	}

	float master_scale = clamp(global_light_intensity / 3.5, 0.0, 1.5);
	float effective_solar = clamp(axial_lum * master_scale, 0.0, 1.5);
	float thick_norm = clamp((cloud_thickness - 100.0) / 700.0, 0.0, 1.0);
	float rain_darkening = mix(1.0, 0.38, thick_norm);
	vec3 dark_night = night_tint.rgb * (0.02 * master_scale);
	vec3 day_light = axial_col.rgb * effective_solar * rain_darkening;
	vec3 lit_color = day_light + dark_night;

	float total_alpha = tex.a * rain_tint.a * near_fade * far_fade * rain_alpha_multiplier * vertical_fade;

	ALBEDO = tex.rgb * rain_tint.rgb * lit_color;
	ALPHA = clamp(total_alpha, 0.0, 1.0);
}

