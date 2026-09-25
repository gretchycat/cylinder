shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_sand : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_concrete : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_road : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_sand_to_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt_to_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_road_edge : source_color, filter_linear_mipmap, repeat_enable;

uniform float uv_scale = 0.08;
uniform float cylinder_radius = 4000.0;
uniform float water_level = 4.0;
uniform float max_elevation = 10.0;

varying vec3 world_pos;
varying vec4 vert_attr; // r: elevation_ratio (0..1), g: terrain_type_id (0..8)

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vert_attr = COLOR;
}

void fragment() {
	// Circumference arc distance and Z distance on cylinder
	float angle = atan(world_pos.y, world_pos.x);
	if (angle < 0.0) {
		angle += 6.28318530718;
	}
	float arc_dist = angle * cylinder_radius;
	float z_dist = world_pos.z;

	vec2 terrain_uv = vec2(arc_dist, z_dist) * uv_scale;

	// Sample terrain textures
	vec3 col_sand = texture(tex_sand, terrain_uv).rgb;
	vec3 col_dirt = texture(tex_dirt, terrain_uv).rgb;
	vec3 col_grass = texture(tex_grass, terrain_uv).rgb;
	vec3 col_concrete = texture(tex_concrete, terrain_uv).rgb;
	vec3 col_road = texture(tex_road, terrain_uv).rgb;
	vec3 col_sand_grass = texture(tex_sand_to_grass, terrain_uv).rgb;
	vec3 col_dirt_grass = texture(tex_dirt_to_grass, terrain_uv).rgb;
	vec3 col_road_edge = texture(tex_road_edge, terrain_uv).rgb;

	int type_id = int(round(vert_attr.g * 8.0));
	float elev = vert_attr.r * max_elevation;

	vec3 final_color = col_grass;
	float roughness_val = 0.85;
	float metallic_val = 0.05;

	// Select or blend base color from tile type
	if (type_id == 0) {
		// Water basin seabed (submerged sand and silt)
		final_color = mix(col_sand * 0.75, col_dirt * 0.65, 0.4);
		roughness_val = 0.95;
	} else if (type_id == 1) {
		// Coastal Sand Beach
		final_color = col_sand;
		roughness_val = 0.9;
	} else if (type_id == 2) {
		// Earth / Dirt
		final_color = col_dirt;
		roughness_val = 0.88;
	} else if (type_id == 3) {
		// Lush Grass Meadow
		final_color = col_grass;
		roughness_val = 0.82;
	} else if (type_id == 4) {
		// Concrete Plazas / Launch pads
		final_color = col_concrete;
		roughness_val = 0.45;
		metallic_val = 0.15;
	} else if (type_id == 5) {
		// Paved Roads
		final_color = col_road;
		roughness_val = 0.4;
		metallic_val = 0.1;
	} else if (type_id == 6) {
		// Sand to Grass convergence tile
		final_color = col_sand_grass;
		roughness_val = 0.86;
	} else if (type_id == 7) {
		// Dirt to Grass convergence tile
		final_color = col_dirt_grass;
		roughness_val = 0.85;
	} else if (type_id == 8) {
		// Road Edge convergence tile
		final_color = col_road_edge;
		roughness_val = 0.55;
	}

	// Micro-shading based on elevation contours
	float contour = sin(elev * 3.14159265);
	final_color = mix(final_color * 0.95, final_color * 1.05, (contour + 1.0) * 0.5);

	ALBEDO = final_color;
	ROUGHNESS = roughness_val;
	METALLIC = metallic_val;
}
