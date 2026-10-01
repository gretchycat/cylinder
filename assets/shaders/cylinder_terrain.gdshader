shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx, fog_disabled;

// --- Terrain Textures with 3 Variations per Type ---
// Grass variations: 0 = Lush Meadow, 1 = Wildflower/Dry Meadow, 2 = Alpine Turf
uniform sampler2D tex_grass_0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_grass_1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_grass_2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// Sand variations: 0 = Shoreline Beach, 1 = Rippled Dune, 2 = Coarse Coastal
uniform sampler2D tex_sand_0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_sand_1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_sand_2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// Dirt variations: 0 = Rich Loam, 1 = Red Clay Earth, 2 = Cracked Pebbled Earth
uniform sampler2D tex_dirt_0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_dirt_1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_dirt_2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// Farmland variations: 0 = Tilled Furrows, 1 = Golden Wheat Rows, 2 = Green Sprout Rows
uniform sampler2D tex_farmland_0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_farmland_1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_farmland_2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// Rocks variations: 0 = Fractured Slate, 1 = Weathered Granite, 2 = Scree Gravel
uniform sampler2D tex_rocks_0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rocks_1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rocks_2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// Concrete variations: 0 = Foundation Slabs, 1 = Modular Pavement, 2 = Weathered Concrete
uniform sampler2D tex_concrete_0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_concrete_1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_concrete_2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// Road variations: 0 = Highway Asphalt, 1 = Weathered Road, 2 = Urban Street
uniform sampler2D tex_road_0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_road_1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_road_2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// Hemispherical End Cap Structure
uniform sampler2D tex_end_cap_ribs : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// One cached, map-owned atlas supplies low-cost ground cover by terrain type:
// grass, crop seedlings, dirt weeds, rocky fragments, and sand pebbles.
uniform sampler2D tex_clutter_cover_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool clutter_cover_enabled = false;
uniform float clutter_cover_strength : hint_range(0.0, 1.0) = 0.82;
uniform vec2 clutter_cover_atlas_size = vec2(768.0, 512.0);
uniform float clutter_cover_cell_size = 256.0;
uniform float clutter_cover_gutter = 16.0;
uniform float clutter_cover_uv_scale = 1.0;

// 2D RPG Terrain Tilemap texture (stores pure terrain IDs: 0..7)
uniform sampler2D terrain_map : hint_default_black, filter_nearest, repeat_enable;
uniform vec2 terrain_map_size = vec2(512.0, 256.0);

uniform float uv_scale = 0.5;
uniform float cylinder_radius = 4000.0;
uniform float water_level = 20.0;
uniform float max_elevation = 100.0;

uniform vec4 air_color : source_color = vec4(0.52, 0.72, 0.88, 1.0);
uniform float air_density : hint_range(0.0, 3.0) = 1.25;
uniform float air_distance_min = 200.0;
uniform float air_distance_max = 18000.0;
uniform float endcap_emission_factor : hint_range(0.0, 1.0) = 1.0;

uniform sampler2D axial_light_lut : hint_default_white, filter_linear, repeat_disable;
uniform float cylinder_length = 18000.0;
uniform float axial_light_enabled = 1.0;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_thickness : hint_range(50.0, 800.0) = 250.0;

varying vec3 world_pos;
varying vec4 vert_attr; // r: elevation_ratio (0..1), g: terrain_type_id (0..7 normalized), b: is_end_cap (0..1)
varying vec2 v_uv;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vert_attr = COLOR;
	v_uv = UV;
}

// Fast 2D to 2D pseudo-random hash
vec2 hash2D(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453123);
}

// 2D rotation matrix
mat2 rot2D(float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return mat2(vec2(c, -s), vec2(s, c));
}

// Continuous multi-frequency non-repeating spatial cross-fading
vec3 sample_seamless_organic(sampler2D s0, sampler2D s1, sampler2D s2, vec2 uv, vec3 var_w) {
	vec3 c0 = texture(s0, uv).rgb;
	vec3 c1 = texture(s1, uv * 0.91 + vec2(17.3, 31.7)).rgb;
	vec3 c2 = texture(s2, uv * 1.13 + vec2(43.1, 11.9)).rgb;
	return c0 * var_w.x + c1 * var_w.y + c2 * var_w.z;
}

// Continuous spatial multi-frequency variation field for intra-terrain variation
vec3 get_variation_weights(vec2 uv) {
	vec2 p = uv * 0.045; // ~22m wavelength
	float n1 = sin(p.x * 1.3 + cos(p.y * 0.9)) * cos(p.y * 1.2 - sin(p.x * 0.8));
	float n2 = sin(p.x * 0.8 - p.y * 1.5 + 2.3) * cos(p.x * 1.4 + p.y * 0.7);

	float w0 = max(0.0, n1 * 0.75 + 0.35);
	float w1 = max(0.0, -n1 * 0.55 + n2 * 0.65 + 0.30);
	float w2 = max(0.0, -n2 * 0.75 + 0.35);

	float sum = w0 + w1 + w2 + 0.0001;
	return vec3(w0, w1, w2) / sum;
}

// 2D noise hash for edge perturbation
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Helper function to sample terrain texture with pseudo-randomized non-repeating distribution
void sample_terrain_surface(int type_id, vec2 uv, vec3 var_w, out vec3 albedo, out float rough, out float metal) {
	metal = 0.02;
	rough = 0.85;

	if (type_id == 0) {
		// Water seabed (sand and dirt blend)
		vec3 c_sand = sample_seamless_organic(tex_sand_0, tex_sand_1, tex_sand_2, uv, var_w);
		vec3 c_dirt = sample_seamless_organic(tex_dirt_0, tex_dirt_1, tex_dirt_2, uv, var_w);
		albedo = mix(c_sand * 0.70, c_dirt * 0.60, 0.40);
		rough = 0.95;
	} else if (type_id == 1) {
		// Sand Beach (rippled dunes and coarse sand)
		albedo = sample_seamless_organic(tex_sand_0, tex_sand_1, tex_sand_2, uv, var_w);
		rough = 0.90;
	} else if (type_id == 2) {
		// Dirt Highlands (rich loam, clay earth, and cracked soil)
		albedo = sample_seamless_organic(tex_dirt_0, tex_dirt_1, tex_dirt_2, uv, var_w);
		rough = 0.88;
	} else if (type_id == 3) {
		// Grass Plains (lush meadow, wildflowers, and alpine turf)
		albedo = sample_seamless_organic(tex_grass_0, tex_grass_1, tex_grass_2, uv, var_w);
		rough = 0.82;
	} else if (type_id == 4) {
		// Farmland Cultivated Plots (structured agricultural furrows & crop rows)
		vec3 c0 = texture(tex_farmland_0, uv).rgb;
		vec3 c1 = texture(tex_farmland_1, uv).rgb;
		vec3 c2 = texture(tex_farmland_2, uv).rgb;
		albedo = c0 * var_w.x + c1 * var_w.y + c2 * var_w.z;
		rough = 0.85;
	} else if (type_id == 5) {
		// Mountain Rocks & Cliffs (fractured slate, granite, and gravel scree)
		albedo = sample_seamless_organic(tex_rocks_0, tex_rocks_1, tex_rocks_2, uv, var_w);
		rough = 0.92;
		metal = 0.05;
	} else if (type_id == 6) {
		// Concrete Spaceport & Foundation (aligned foundation slabs, modular pavement, weathered concrete)
		vec3 c0 = texture(tex_concrete_0, uv).rgb;
		vec3 c1 = texture(tex_concrete_1, uv).rgb;
		vec3 c2 = texture(tex_concrete_2, uv).rgb;
		albedo = c0 * var_w.x + c1 * var_w.y + c2 * var_w.z;
		rough = 0.45;
		metal = 0.15;
	} else if (type_id == 7) {
		// Paved Road Network (aligned highway asphalt, weathered tar, and urban pavement markings)
		vec3 c0 = texture(tex_road_0, uv).rgb;
		vec3 c1 = texture(tex_road_1, uv).rgb;
		vec3 c2 = texture(tex_road_2, uv).rgb;
		albedo = c0 * var_w.x + c1 * var_w.y + c2 * var_w.z;
		rough = 0.38;
		metal = 0.10;
	} else {
		albedo = sample_seamless_organic(tex_grass_0, tex_grass_1, tex_grass_2, uv, var_w);
		rough = 0.82;
	}
}

// True if terrain type is artificial (sharp boundary, no bleeding)
bool is_terrain_artificial(int t) {
	return (t == 4 || t == 6 || t == 7); // Farmland, Concrete, Road
}

void fragment() {
	float is_end_cap = vert_attr.b;
	vec2 terrain_uv;
	float angle = atan(world_pos.y, world_pos.x);
	if (angle < 0.0) {
		angle += 6.28318530718;
	}

	if (is_end_cap > 0.5) {
		terrain_uv = world_pos.xy * uv_scale;
	} else {
		float arc_dist = angle * cylinder_radius;
		float z_dist = world_pos.z;
		terrain_uv = vec2(arc_dist, z_dist) * uv_scale;
	}

	float elev = vert_attr.r * max_elevation;
	vec3 final_color = vec3(0.3, 0.6, 0.2);
	float roughness_val = 0.85;
	float metallic_val = 0.05;
	vec3 emission_color = vec3(0.0);

	// Continuous seamless multi-variation weights for intra-terrain cross-fading
	vec3 var_w = get_variation_weights(terrain_uv);

	if (is_end_cap > 0.5) {
		// Hemispherical end cap bulkhead structures
		float r_axis = length(world_pos.xy);
		float alpha = vert_attr.r;

		vec2 polar_uv = vec2(0.5, 0.5);
		if (r_axis > 0.01) {
			vec2 dir = world_pos.xy / r_axis;
			polar_uv = vec2(0.5, 0.5) + dir * (0.49 * alpha);
		}

		vec3 col_ribs = texture(tex_end_cap_ribs, polar_uv).rgb;
		vec3 col_concrete; float r_tmp, m_tmp;
		sample_terrain_surface(6, terrain_uv, var_w, col_concrete, r_tmp, m_tmp);
		vec3 bulkhead_base = mix(col_concrete * 0.9, col_ribs * 1.5, 0.75);

		float ring_dist = abs(fract(r_axis / 250.0 + 0.5) - 0.5) * 250.0;
		float ring_line = smoothstep(10.0, 0.0, ring_dist);
		float spoke_val = abs(fract(angle / (6.28318530718 / 32.0) + 0.5) - 0.5);
		float spoke_line = smoothstep(0.010, 0.0, spoke_val);

		bulkhead_base = mix(bulkhead_base, bulkhead_base * 0.85, ring_line * 0.25 + spoke_line * 0.25);
		final_color = bulkhead_base;
		roughness_val = 0.75;
		metallic_val = 0.05;

		if (alpha > 0.90) {
			float apron_blend = smoothstep(0.90, 1.0, alpha);
			final_color = mix(final_color, col_concrete, apron_blend * 0.50);
		}
	} else {
		// --- Automatic Intelligent Edge Fading & Blending on Cylinder Surface ---
		// Exact continuous cylinder map coordinates derived from world_pos
		float u_cyl = angle / 6.28318530718;
		float v_cyl = clamp((world_pos.z + cylinder_length * 0.5) / cylinder_length, 0.0, 1.0);
		vec2 texel_size = vec2(1.0) / terrain_map_size;
		vec2 grid_pos = vec2(u_cyl, v_cyl) * terrain_map_size - vec2(0.5);
		vec2 f = fract(grid_pos);
		vec2 uv_base = (floor(grid_pos) + vec2(0.5)) * texel_size;

		int t00 = int(round(texture(terrain_map, uv_base).r * 255.0));
		int t10 = int(round(texture(terrain_map, uv_base + vec2(texel_size.x, 0.0)).r * 255.0));
		int t01 = int(round(texture(terrain_map, uv_base + vec2(0.0, texel_size.y)).r * 255.0));
		int t11 = int(round(texture(terrain_map, uv_base + texel_size).r * 255.0));

		// Bilinear weights across the 4 surrounding map cells
		float w00 = (1.0 - f.x) * (1.0 - f.y);
		float w10 = f.x * (1.0 - f.y);
		float w01 = (1.0 - f.x) * f.y;
		float w11 = f.x * f.y;

		float weights[8];
		for (int k = 0; k < 8; k++) {
			weights[k] = 0.0;
		}
		weights[t00] += w00;
		weights[t10] += w10;
		weights[t01] += w01;
		weights[t11] += w11;

		// Micro-terrain slope and elevation natural splatting for organic terrain
		vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 cyl_inward = normalize(vec3(-world_pos.x, -world_pos.y, 0.0));
		float slope = 1.0 - clamp(dot(world_normal, cyl_inward), 0.0, 1.0);

		// Natural slope rock/dirt scree and shoreline sand modulations
		if (weights[3] > 0.10) { // Grass present
			float rock_slope = smoothstep(0.12, 0.38, slope) * 0.65;
			float sand_shore = smoothstep(26.0, 20.5, elev) * 0.70;
			float dirt_high = smoothstep(52.0, 72.0, elev) * 0.55;

			float displace_w = weights[3] * max(rock_slope, max(sand_shore, dirt_high));
			weights[3] -= displace_w;
			if (rock_slope >= sand_shore && rock_slope >= dirt_high) {
				weights[5] += displace_w; // Rocks on slopes
			} else if (sand_shore >= dirt_high) {
				weights[1] += displace_w; // Sand on shores
			} else {
				weights[2] += displace_w; // Dirt on heights
			}
		}

		// Directly blend all contributing terrain types
		vec3 blended_col = vec3(0.0);
		float blended_rough = 0.0;
		float blended_metal = 0.0;
		float total_w = 0.0;
		float cover_weight = 0.0;
		int cover_type = -1;

		float edge_noise = (hash21(terrain_uv * 1.5) - 0.5) * 0.14;

		for (int k = 0; k < 8; k++) {
			if (weights[k] > 0.001) {
				float effective_w = weights[k];
				if (is_terrain_artificial(k)) {
					// Sharpen road / concrete boundaries
					effective_w = smoothstep(0.40, 0.60, effective_w);
				} else {
					// Smooth organic noise-modulated transition
					effective_w = clamp(effective_w + edge_noise * (1.0 - abs(effective_w - 0.5) * 2.0), 0.0, 1.0);
				}

				if (effective_w > 0.001) {
					vec3 c_k; float r_k, m_k;
					sample_terrain_surface(k, terrain_uv, var_w, c_k, r_k, m_k);
					blended_col += c_k * effective_w;
					blended_rough += r_k * effective_w;
					blended_metal += m_k * effective_w;
					total_w += effective_w;
					if ((k == 1 || k == 2 || k == 3 || k == 4 || k == 5) && effective_w > cover_weight) {
						cover_weight = effective_w;
						cover_type = k;
					}
				}
			}
		}

		if (total_w > 0.0001) {
			final_color = blended_col / total_w;
			roughness_val = blended_rough / total_w;
			metallic_val = blended_metal / total_w;
		} else {
			sample_terrain_surface(t00, terrain_uv, var_w, final_color, roughness_val, metallic_val);
		}

		// Sample one cached cover layer for the dominant natural ground type.
		// Explicit gradients keep atlas mip selection stable across the fract wrap.
		if (clutter_cover_enabled && cover_type >= 1) {
			vec2 cell = vec2(0.0);
			if (cover_type == 4) {
				cell = vec2(1.0, 0.0); // Farmland seedlings
			} else if (cover_type == 2) {
				cell = vec2(2.0, 0.0); // Dirt sprouts and pebbles
			} else if (cover_type == 5) {
				cell = vec2(0.0, 1.0); // Rock fragments
			} else if (cover_type == 1) {
				cell = vec2(1.0, 1.0); // Sand pebbles
			}
			vec2 repeated_uv = terrain_uv * clutter_cover_uv_scale;
			vec2 content_size = vec2(clutter_cover_cell_size - 2.0 * clutter_cover_gutter);
			vec2 atlas_uv = (cell * clutter_cover_cell_size + vec2(clutter_cover_gutter) + fract(repeated_uv) * content_size) / clutter_cover_atlas_size;
			vec2 atlas_dx = dFdx(repeated_uv) * content_size / clutter_cover_atlas_size;
			vec2 atlas_dy = dFdy(repeated_uv) * content_size / clutter_cover_atlas_size;
			vec4 ground_cover = textureGrad(tex_clutter_cover_atlas, atlas_uv, atlas_dx, atlas_dy);
			final_color = mix(final_color, ground_cover.rgb, ground_cover.a * cover_weight * clutter_cover_strength);
		}

		// Elevation micro-contour shading
		float contour = sin(elev * 3.14159265);
		final_color = mix(final_color * 0.96, final_color * 1.04, (contour + 1.0) * 0.5);
	}

	// Submerged seabed aquatic gradient & animated caustics
	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	float cam_r = length(CAMERA_POSITION_WORLD.xy);
	bool is_camera_underwater = cam_r > (cylinder_radius - water_level);

	if (elev < water_level && is_end_cap < 0.5) {
		float water_depth = water_level - elev;
		float depth_norm = clamp(water_depth / 16.0, 0.0, 1.0);

		vec3 shallow_seabed_tint = vec3(0.08, 0.48, 0.68);
		vec3 deep_seabed_tint = vec3(0.01, 0.12, 0.32);
		vec3 aquatic_tint = mix(shallow_seabed_tint, deep_seabed_tint, depth_norm);

		final_color = mix(final_color, aquatic_tint, 0.25 + 0.20 * depth_norm);

		if (cam_dist < 220.0) {
			float c_uv1 = sin(terrain_uv.x * 1.8 + TIME * 1.5) * cos(terrain_uv.y * 1.6 - TIME * 1.2);
			float c_uv2 = cos(terrain_uv.x * 2.8 - TIME * 1.8) * sin(terrain_uv.y * 2.6 + TIME * 1.4);
			float c_uv3 = sin((terrain_uv.x + terrain_uv.y) * 3.5 + TIME * 2.2);
			float caustics = clamp((c_uv1 + c_uv2 + c_uv3 * 0.5) * 0.4 + 0.5, 0.0, 1.0);
			vec3 caustic_color = vec3(0.35, 0.85, 1.0);
			float dist_falloff = clamp(1.0 - cam_dist / 220.0, 0.0, 1.0);
			final_color += caustic_color * (pow(caustics, 2.8) * 0.45 * (1.0 - depth_norm * 0.60) * dist_falloff);
		}
		roughness_val = mix(roughness_val, 0.20, depth_norm * 0.6);
	}

	if (is_camera_underwater) {
		float water_visibility = 180.0;
		float water_fog = 1.0 - exp(-cam_dist / water_visibility);
		vec3 deep_water_fog = vec3(0.015, 0.18, 0.38);
		final_color = mix(final_color, deep_water_fog, water_fog * 0.94);
		final_color = mix(final_color, vec3(0.03, 0.28, 0.48), 0.25);
	} else {
		float air_factor = clamp((cam_dist - air_distance_min) / max(air_distance_max - air_distance_min, 1.0), 0.0, 1.0);
		float air_scatter = 1.0 - exp(-air_factor * 2.8);

		vec3 target_air_color = air_color.rgb;
		if (axial_light_enabled > 0.5) {
			float t_z = clamp((world_pos.z + cylinder_length * 0.5) / cylinder_length, 0.0, 1.0);
			vec4 axial_light = texture(axial_light_lut, vec2(t_z, 0.5));
			vec3 axial_col = axial_light.rgb;
			float axial_lum = clamp(axial_light.a, 0.0, 1.5);
			target_air_color = air_color.rgb * axial_col * axial_lum;
		}

		float fog_blend = clamp(air_scatter * air_density, 0.0, 1.0);
		final_color = mix(final_color, target_air_color, fog_blend);
	}

	// Cloud overcast and thickness lighting attenuation
	float c_norm = clamp(cloud_coverage, 0.0, 1.0);
	float cov_dim = (c_norm <= 0.50) ? mix(1.0, 0.95, c_norm / 0.50) : mix(0.95, 0.35, (c_norm - 0.50) / 0.50);
	float thick_norm = clamp((cloud_thickness - 100.0) / 700.0, 0.0, 1.0);
	float thick_dim = mix(1.0, 0.40, thick_norm);
	float weather_dim = cov_dim * thick_dim;

	vec3 cool_overcast_tint = vec3(0.78, 0.88, 1.15);
	float blue_shift = smoothstep(0.35, 1.0, c_norm) * 0.75;
	vec3 weather_modulation = mix(vec3(1.0), cool_overcast_tint, blue_shift) * weather_dim;

	final_color *= weather_modulation;

	ALBEDO = final_color;
	ROUGHNESS = roughness_val;
	METALLIC = metallic_val;
	EMISSION = emission_color;
}
