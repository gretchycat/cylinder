shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.18, 0.62, 0.88, 0.72);
uniform vec4 deep_color : source_color = vec4(0.06, 0.28, 0.58, 0.88);
uniform float wave_speed : hint_range(0.0, 5.0) = 0.75;
uniform float wave_frequency : hint_range(0.01, 1.0) = 0.08;
uniform float wave_height : hint_range(0.0, 0.5) = 0.06;
uniform float roughness : hint_range(0.0, 1.0) = 0.08;
uniform float specular : hint_range(0.0, 1.0) = 0.90;
uniform float cylinder_radius = 3996.0; // 4000m - 4m water level

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float angle = atan(world_pos.y, world_pos.x);
	float arc_dist = angle * cylinder_radius;

	// Animated rippling wave displacement along radial normal (inward toward axis)
	float w1 = sin(arc_dist * wave_frequency + TIME * wave_speed);
	float w2 = cos(world_pos.z * (wave_frequency * 1.2) + TIME * (wave_speed * 1.3));
	float displacement = (w1 * 0.6 + w2 * 0.4) * wave_height;

	vec3 inward_norm = normalize(vec3(-world_pos.x, -world_pos.y, 0.0));
	VERTEX += inward_norm * displacement;
}

void fragment() {
	float angle = atan(world_pos.y, world_pos.x);
	if (angle < 0.0) {
		angle += 6.28318530718;
	}
	float arc_dist = angle * cylinder_radius;

	// Dual scrolling wave textures for caustic micro-ripples
	vec2 uv1 = vec2(arc_dist, world_pos.z) * 0.12 + vec2(TIME * 0.04, TIME * 0.02);
	vec2 uv2 = vec2(arc_dist * 0.8 - world_pos.z * 0.4, world_pos.z * 0.8 + arc_dist * 0.3) * 0.15 - vec2(TIME * 0.03, TIME * 0.035);

	float r1 = sin(uv1.x * 10.0 + uv1.y * 6.0);
	float r2 = cos(uv2.x * 12.0 - uv2.y * 8.0);
	vec3 ripple_norm = normalize(vec3(r1 * 0.18, r2 * 0.18, 1.0));

	// Fresnel effect for realistic surface reflectivity at glancing angles
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, 0.35);
	col = mix(col, vec3(0.85, 0.95, 1.0), fresnel * 0.45);

	ALBEDO = col;
	NORMAL = ripple_norm;
	ALPHA = clamp(shallow_color.a + fresnel * 0.25, 0.65, 0.95);
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = 0.05;
}
