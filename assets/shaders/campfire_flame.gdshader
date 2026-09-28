shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 color_core : source_color = vec4(1.0, 0.96, 0.72, 1.0);
uniform vec4 color_flame : source_color = vec4(1.0, 0.48, 0.06, 1.0);
uniform vec4 color_tip : source_color = vec4(0.85, 0.12, 0.01, 0.8);
uniform float speed : hint_range(0.5, 6.0) = 2.8;
uniform float turbulence : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_world_pos;
varying vec2 v_uv;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.55;
	float freq = 1.0;
	for (int i = 0; i < 4; i++) {
		total += amp * noise(p * freq);
		freq *= 2.05;
		amp *= 0.48;
	}
	return total;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = UV;

	// In Godot QuadMesh, UV.y = 1.0 is bottom (ground), UV.y = 0.0 is top
	float height = clamp(1.0 - UV.y, 0.0, 1.0);

	// Fluid flame billow sway
	float sway_x = sin(TIME * speed * 2.8 + VERTEX.y * 3.5) * (height * 0.14 * turbulence);
	float sway_z = cos(TIME * speed * 2.3 + VERTEX.y * 3.0) * (height * 0.14 * turbulence);
	VERTEX.x += sway_x;
	VERTEX.z += sway_z;
}

void fragment() {
	// In Godot QuadMesh: v_uv.y = 1.0 is ground/coals, v_uv.y = 0.0 is top tip
	float height = clamp(1.0 - v_uv.y, 0.0, 1.0);

	// Multi-frequency upward advection
	float t = TIME * speed;
	vec2 base_p = vec2(v_uv.x * 2.2, height * 2.0);

	// Domain warping for turbulent fluid licking tongues
	vec2 warp1 = vec2(
		noise(base_p * 1.5 + vec2(0.0, -t * 0.8)),
		noise(base_p * 1.5 + vec2(5.2, -t * 0.9))
	) * 0.45;

	vec2 warp2 = vec2(
		noise((base_p + warp1) * 3.0 + vec2(1.7, -t * 1.4)),
		noise((base_p + warp1) * 3.0 + vec2(8.3, -t * 1.6))
	) * 0.30;

	vec2 fire_uv = base_p + warp1 + warp2;
	float fire_noise = fbm(vec2(fire_uv.x, fire_uv.y - t * 1.2));

	// Natural multi-tongue flame envelope (broad organic shape with dancing lateral waves, NOT a cone)
	float lateral_wave = sin(height * 7.0 - t * 3.0) * 0.08 * height
	                   + sin(height * 14.0 + t * 4.5) * 0.04 * height;
	float dist_from_axis = abs(v_uv.x - 0.5 + lateral_wave);

	// Organic envelope width: broad at coal bed, bulging in middle, organic wisping towards top
	float envelope_width = mix(0.42, 0.22, smoothstep(0.0, 0.70, height));
	float lateral_mask = 1.0 - smoothstep(envelope_width * 0.25, envelope_width, dist_from_axis);

	// Vertical dissipation: full intensity at base, smoothly dissolving into sparks before top
	float vertical_dissipation = 1.0 - smoothstep(0.50, 0.90, height);

	// Combine fluid noise and organic envelope
	float flame_field = (lateral_mask * vertical_dissipation) * (fire_noise * 1.6 + 0.35);

	// Dynamic erosion threshold
	float threshold = height * 0.58;
	float alpha_val = smoothstep(threshold, threshold + 0.24, flame_field);

	// Solid burning coal/log base reinforcement
	float coal_base = (1.0 - smoothstep(0.0, 0.20, height)) * (1.0 - smoothstep(0.1, 0.40, dist_from_axis));
	alpha_val = max(alpha_val, coal_base * 0.92);

	if (alpha_val < 0.015) {
		discard;
	}

	// 3-tier dynamic thermodynamic heat coloring
	float heat = clamp((flame_field - threshold) / 0.52, 0.0, 1.0);
	heat = max(heat, coal_base * 0.85);

	vec3 fire_color = mix(color_tip.rgb, color_flame.rgb, smoothstep(0.05, 0.40, heat));
	fire_color = mix(fire_color, color_core.rgb, smoothstep(0.58, 0.92, heat));

	ALBEDO = fire_color * 3.0;
	ALPHA = clamp(alpha_val * 0.96, 0.0, 1.0);
}
