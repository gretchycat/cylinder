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

	// Composite subtle underwater optical atmosphere (clean depth tint + soft edge falloff)
	vec3 tinted = mix(base_scene, underwater_tint.rgb, underwater_tint.a);
	tinted = mix(tinted, deep_vignette_color.rgb, vignette * 0.30);

	COLOR = vec4(tinted, 1.0);
}
