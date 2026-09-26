shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, unshaded;

// Rain Sheet Shader for O'Neill Cylinder Atmospheric Weather
// Renders scrolling pre-rendered raindrop streaks on layered cylindrical / curtain sheets around the player
uniform sampler2D rain_texture : filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(3.0, 2.0);
uniform vec2 uv_scroll_speed = vec2(0.0, 6.0);
uniform vec4 rain_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rain_alpha_multiplier : hint_range(0.0, 2.0) = 1.0;

// Distance fading to avoid camera near-clip popping and blend with horizon depth
uniform float near_fade_min = 1.2;
uniform float near_fade_max = 3.5;
uniform float far_fade_min = 35.0;
uniform float far_fade_max = 55.0;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 scrolled_uv = UV * uv_scale + uv_scroll_speed * TIME;
	vec4 tex = texture(rain_texture, scrolled_uv);

	float dist = length(v_world_pos - CAMERA_POSITION_WORLD);
	float near_fade = smoothstep(near_fade_min, near_fade_max, dist);
	float far_fade = 1.0 - smoothstep(far_fade_min, far_fade_max, dist);
	float total_alpha = tex.a * rain_tint.a * near_fade * far_fade * rain_alpha_multiplier;

	ALBEDO = tex.rgb * rain_tint.rgb;
	ALPHA = total_alpha;
}
