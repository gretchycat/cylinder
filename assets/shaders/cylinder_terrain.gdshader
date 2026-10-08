shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx, fog_disabled;

uniform sampler2D terrain_map : filter_nearest, repeat_enable;
uniform vec2 terrain_map_size;
uniform sampler2DArray biome_textures : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D biome_tints : source_color, filter_nearest, repeat_disable;
// R = texture array layer, G = repeat size in metres, B = roughness, A = biome blending enabled.
uniform sampler2D biome_parameters : filter_nearest, repeat_disable;
uniform sampler2D tex_end_cap_ribs : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 end_cap_tint : source_color;
uniform float cylinder_radius;
uniform float cylinder_length;
uniform float water_level;
uniform float max_elevation;
uniform vec4 air_color : source_color;
uniform float air_density;
uniform float air_distance_min;
uniform float air_distance_max;
uniform vec4 deep_water_color : source_color;
uniform sampler2D axial_light_lut : hint_default_white, filter_linear, repeat_disable;
uniform float axial_light_enabled = 1.0;
uniform float endcap_emission_factor = 1.0;
uniform float cloud_coverage;
uniform float cloud_thickness;
uniform float biome_blend_width_m;
varying vec3 world_pos;
varying float end_cap;

float terrain_biome_id(vec2 cell) {
	vec2 wrapped_cell = vec2(mod(cell.x, terrain_map_size.x), clamp(cell.y, 0.0, terrain_map_size.y - 1.0));
	return round(texture(terrain_map, (wrapped_cell + 0.5) / terrain_map_size).r * 255.0);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec3 sample_tile_variant(sampler2DArray tex_array, float layer, vec2 tile_pos, vec2 local_f, float biome_id) {
	vec2 h = hash22(tile_pos + vec2(biome_id * 17.13, biome_id * 31.71));
	vec2 f = local_f;

	if (h.x > 0.5) f.x = -f.x;
	if (h.y > 0.5) f.y = -f.y;

	float r = floor(h.x * 4.0);
	if (r == 1.0) {
		f = vec2(f.y, -f.x);
	} else if (r == 2.0) {
		f = vec2(-f.x, -f.y);
	} else if (r == 3.0) {
		f = vec2(-f.y, f.x);
	}

	vec2 final_uv = tile_pos + f + h;
	return texture(tex_array, vec3(final_uv, layer)).rgb;
}

vec3 stochastic_biome_texture(sampler2DArray tex_array, float layer, vec2 uv, float biome_id) {
	vec2 p = floor(uv);
	vec2 f = fract(uv);
	vec2 w = smoothstep(0.2, 0.8, f);

	vec3 col00 = sample_tile_variant(tex_array, layer, p, f, biome_id);
	vec3 col10 = sample_tile_variant(tex_array, layer, p + vec2(1.0, 0.0), f - vec2(1.0, 0.0), biome_id);
	vec3 col01 = sample_tile_variant(tex_array, layer, p + vec2(0.0, 1.0), f - vec2(0.0, 1.0), biome_id);
	vec3 col11 = sample_tile_variant(tex_array, layer, p + vec2(1.0, 1.0), f - vec2(1.0, 1.0), biome_id);

	return mix(mix(col00, col10, w.x), mix(col01, col11, w.x), w.y);
}

vec4 terrain_biome_surface(float id, float u, float z) {
	vec2 table_uv = vec2((id + 0.5) / 256.0, 0.5);
	vec4 parameters = texture(biome_parameters, table_uv);
	vec4 tint = texture(biome_tints, table_uv);
	float repeats = max(round(TAU * cylinder_radius / parameters.g), 1.0);
	vec2 uv = vec2(u * repeats, z / parameters.g);

	vec3 tex;
	if (parameters.a > 0.75) {
		// Natural ground texture: stochastic pseudo-random rotation, flipping, and offset blending to eliminate tiling repetition and moiré
		tex = stochastic_biome_texture(biome_textures, parameters.r, uv, id);
	} else {
		// Structural / non-blending texture (concrete/farmland) or rotation disabled: standard linear UV mapping
		tex = texture(biome_textures, vec3(uv, parameters.r)).rgb;
	}

	return vec4(mix(tex, tex * tint.rgb, tint.a), parameters.b);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	end_cap = COLOR.b;
}

void fragment() {
	float u = fract(atan(world_pos.y, world_pos.x) / TAU + 1.0);
	float v = clamp(world_pos.z / cylinder_length + 0.5, 0.0, 1.0);
	vec3 albedo;
	float roughness_value;
	if (end_cap > 0.5) {
		vec2 uv = world_pos.xy / (2.0 * cylinder_radius) + 0.5;
		vec3 tex = texture(tex_end_cap_ribs, uv).rgb;
		albedo = mix(tex, tex * end_cap_tint.rgb, end_cap_tint.a);
		roughness_value = 0.9;
	} else {
		// Smooth continuous splat blending across adaptive cell diagonals
		vec2 grid = vec2(u * terrain_map_size.x, v * (terrain_map_size.y - 1.0));
		vec2 cell0 = floor(grid);
		vec2 f = grid - cell0;

		vec2 cell00 = cell0;
		vec2 cell10 = cell0 + vec2(1.0, 0.0);
		vec2 cell01 = cell0 + vec2(0.0, 1.0);
		vec2 cell11 = cell0 + vec2(1.0, 1.0);

		float id00 = terrain_biome_id(cell00);
		float id10 = terrain_biome_id(cell10);
		float id01 = terrain_biome_id(cell01);
		float id11 = terrain_biome_id(cell11);

		// Adaptive diagonal selection: align diagonal with biome boundary
		float match_main = (id00 == id11) ? 1.0 : 0.0;
		float match_anti = (id10 == id01) ? 1.0 : 0.0;
		bool use_main = (match_main >= match_anti);

		float w00 = 0.0, w10 = 0.0, w01 = 0.0, w11 = 0.0;
		if (use_main) {
			// Main diagonal split connecting (0,0) to (1,1) along line fx = fy
			if (f.x >= f.y) {
				float b00 = 1.0 - f.x;
				float b10 = f.x - f.y;
				float b11 = f.y;
				w00 = smoothstep(0.0, 1.0, b00);
				w10 = smoothstep(0.0, 1.0, b10);
				w11 = smoothstep(0.0, 1.0, b11);
			} else {
				float b00 = 1.0 - f.y;
				float b01 = f.y - f.x;
				float b11 = f.x;
				w00 = smoothstep(0.0, 1.0, b00);
				w01 = smoothstep(0.0, 1.0, b01);
				w11 = smoothstep(0.0, 1.0, b11);
			}
		} else {
			// Anti-diagonal split connecting (1,0) to (0,1) along line fx + fy = 1.0
			if ((f.x + f.y) <= 1.0) {
				float b00 = 1.0 - f.x - f.y;
				float b10 = f.x;
				float b01 = f.y;
				w00 = smoothstep(0.0, 1.0, b00);
				w10 = smoothstep(0.0, 1.0, b10);
				w01 = smoothstep(0.0, 1.0, b01);
			} else {
				float b11 = f.x + f.y - 1.0;
				float b10 = 1.0 - f.y;
				float b01 = 1.0 - f.x;
				w11 = smoothstep(0.0, 1.0, b11);
				w10 = smoothstep(0.0, 1.0, b10);
				w01 = smoothstep(0.0, 1.0, b01);
			}
		}

		float total_w = max(w00 + w10 + w01 + w11, 0.0001);
		w00 /= total_w;
		w10 /= total_w;
		w01 /= total_w;
		w11 /= total_w;

		vec4 surf00 = terrain_biome_surface(id00, u, world_pos.z);
		vec4 surf10 = terrain_biome_surface(id10, u, world_pos.z);
		vec4 surf01 = terrain_biome_surface(id01, u, world_pos.z);
		vec4 surf11 = terrain_biome_surface(id11, u, world_pos.z);

		vec4 surface = surf00 * w00 + surf10 * w10 + surf01 * w01 + surf11 * w11;
		albedo = surface.rgb;
		roughness_value = surface.a;
	}
	float distance_m = length(world_pos - CAMERA_POSITION_WORLD);
	vec3 fog_color = air_color.rgb;
	if (axial_light_enabled > 0.5) {
		vec4 light = texture(axial_light_lut, vec2(v, 0.5));
		fog_color *= light.rgb * clamp(light.a, 0.0, 1.5);
	}
	float fog = clamp((1.0 - exp(-max(distance_m - air_distance_min, 0.0) / max(air_distance_max - air_distance_min, 1.0) * 2.8)) * air_density, 0.0, 1.0);
	if (length(CAMERA_POSITION_WORLD.xy) > cylinder_radius - water_level) {
		fog_color = deep_water_color.rgb;
	}
	ALBEDO = mix(albedo, fog_color, fog);
	ROUGHNESS = roughness_value;
}
