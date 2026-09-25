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
uniform float water_level = 20.0;
uniform float max_elevation = 100.0;

uniform vec4 air_color : source_color = vec4(0.52, 0.72, 0.88, 1.0);
uniform float air_density : hint_range(0.0, 1.0) = 0.65;
uniform float air_distance_min = 200.0;
uniform float air_distance_max = 18000.0;

varying vec3 world_pos;
varying vec4 vert_attr; // r: elevation_ratio (0..1), g: terrain_type_id (0..8), b: is_end_cap (0..1)

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vert_attr = COLOR;
}

void fragment() {
	float is_end_cap = vert_attr.b;
	vec2 terrain_uv;
	float angle = atan(world_pos.y, world_pos.x);
	if (angle < 0.0) {
		angle += 6.28318530718;
	}

	if (is_end_cap > 0.5) {
		// Planar UV projection on end caps: no stretching or radial smearing
		terrain_uv = world_pos.xy * uv_scale;
	} else {
		// Circumference arc distance and Z distance on cylinder barrel
		float arc_dist = angle * cylinder_radius;
		float z_dist = world_pos.z;
		terrain_uv = vec2(arc_dist, z_dist) * uv_scale;
	}

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

	// Structural detailing on end cap bulkheads
	if (is_end_cap > 0.5) {
		float r_axis = length(world_pos.xy);
		// Concentric structural bulkhead rings (every 250 m)
		float ring_dist = abs(fract(r_axis / 250.0 + 0.5) - 0.5) * 250.0;
		float ring_line = smoothstep(10.0, 0.0, ring_dist);

		// 16 radial structural compression ribs
		float spoke_val = abs(fract(angle / (6.28318530718 / 16.0) + 0.5) - 0.5);
		float spoke_line = smoothstep(0.015, 0.0, spoke_val);

		// Central Zero-G spaceport docking ring (radius <= 250 m)
		if (r_axis < 250.0) {
			float dock_circle = abs(r_axis - 180.0);
			if (dock_circle < 10.0) {
				final_color = vec3(0.95, 0.78, 0.25); // Golden aerospace guidance ring
				roughness_val = 0.25;
				metallic_val = 0.85;
			}
		}

		// Darker structural accent grooves on the bulkhead rings and ribs
		final_color = mix(final_color, col_concrete * 0.45, ring_line * 0.4 + spoke_line * 0.35);
	}

	// Prominently tint the terrain under the water level (submerged seabed, lake, and river beds)
	if (elev < water_level && is_end_cap < 0.5) {
		float water_depth = water_level - elev;
		float depth_norm = clamp(water_depth / 16.0, 0.0, 1.0);

		// Rich aquatic gradient: translucent coastal cyan -> deep oceanic blue -> abyssal indigo
		vec3 shallow_seabed_tint = vec3(0.08, 0.48, 0.68);
		vec3 deep_seabed_tint = vec3(0.01, 0.12, 0.32);
		vec3 aquatic_tint = mix(shallow_seabed_tint, deep_seabed_tint, depth_norm);

		// Strong tint blend (72% at shoreline, reaching 96% in deep trenches)
		final_color = mix(final_color, aquatic_tint, 0.72 + 0.24 * depth_norm);

		// Animated underwater sunlight caustics flickering across submerged seabed
		float c_uv1 = sin(terrain_uv.x * 1.5 + TIME * 1.4) * cos(terrain_uv.y * 1.5 - TIME * 1.1);
		float c_uv2 = cos(terrain_uv.x * 2.4 - TIME * 1.7) * sin(terrain_uv.y * 2.4 + TIME * 1.3);
		float caustics = clamp((c_uv1 + c_uv2) * 0.5 + 0.5, 0.0, 1.0);
		vec3 caustic_color = vec3(0.25, 0.75, 0.95);
		final_color += caustic_color * (pow(caustics, 3.2) * 0.38 * (1.0 - depth_norm * 0.75));

		roughness_val = mix(roughness_val, 0.25, depth_norm * 0.5);
	}

	// Distance perspective: Check if camera itself is submerged underwater
	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	float cam_r = length(CAMERA_POSITION_WORLD.xy);
	bool is_camera_underwater = cam_r > (cylinder_radius - water_level);

	if (is_camera_underwater) {
		// When camera moves underwater, aquatic volumetric extinction replaces air haze
		float water_visibility = 220.0;
		float water_fog = 1.0 - exp(-cam_dist / water_visibility);
		vec3 deep_water_fog = vec3(0.02, 0.22, 0.44);
		final_color = mix(final_color, deep_water_fog, water_fog * 0.92);

		// Additional ambient underwater color wash on nearby surfaces
		final_color = mix(final_color, vec3(0.04, 0.35, 0.55), 0.30);
	} else {
		// In air: atmospheric aerial perspective across the 18 km cylinder
		float air_factor = clamp((cam_dist - air_distance_min) / max(air_distance_max - air_distance_min, 1.0), 0.0, 1.0);
		float air_scatter = 1.0 - exp(-air_factor * 1.8);
		final_color = mix(final_color, air_color.rgb, air_scatter * air_density);
	}

	ALBEDO = final_color;
	ROUGHNESS = roughness_val;
	METALLIC = metallic_val;
}
