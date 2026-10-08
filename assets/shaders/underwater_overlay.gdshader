shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 underwater_tint : source_color = vec4(0.06, 0.38, 0.62, 0.22);
uniform vec4 deep_vignette_color : source_color = vec4(0.01, 0.12, 0.28, 0.35);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 base_scene = texture(screen_texture, uv).rgb;

	// Soft peripheral depth vignette
	vec2 center_d = (uv - vec2(0.5)) * 2.0;
	float vignette = smoothstep(0.6, 1.6, length(center_d));

	// Allow bright light sources (lamps, fires, light bar, specular glints) to shine through water
	float scene_brightness = max(base_scene.r, max(base_scene.g, base_scene.b));
	float light_punch = smoothstep(0.50, 1.20, scene_brightness);
	float effective_tint_alpha = underwater_tint.a * (1.0 - light_punch * 0.90);

	// Composite subtle underwater optical atmosphere (clean depth tint + soft edge falloff)
	vec3 tinted = mix(base_scene, underwater_tint.rgb, effective_tint_alpha);
	tinted = mix(tinted, deep_vignette_color.rgb, vignette * 0.30 * (1.0 - light_punch * 0.70));

	COLOR = vec4(tinted, 1.0);
}
