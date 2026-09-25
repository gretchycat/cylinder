shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, fog_disabled;

uniform sampler2D tex_sand : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_concrete : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_road : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_sand_to_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt_to_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_road_edge : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_end_cap_ribs : source_color, filter_linear_mipmap, repeat_enable;

uniform float uv_scale = 0.08;
uniform float cylinder_radius = 4000.0;
uniform float water_level = 20.0;
uniform float max_elevation = 100.0;

uniform vec4 air_color : source_color = vec4(0.52, 0.72, 0.88, 1.0);
uniform float air_density : hint_range(0.0, 1.0) = 0.65;
uniform float air_distance_min = 200.0;
uniform float air_distance_max = 18000.0;
uniform float endcap_emission_factor : hint_range(0.0,1.0) = 1.0;

uniform sampler2D axial_light_lut : hint_default_white, filter_linear, repeat_disable;
uniform float cylinder_length = 18000.0;
uniform float axial_light_enabled = 1.0;

varying vec3 world_pos;
varying vec4 vert_attr; // r: elevation_ratio (0..1), g: terrain_type_id (0..8), b: is_end_cap (0..1)
varying vec2 v_uv;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vert_attr = COLOR;
	v_uv = UV;
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

	// Structural detailing on hemispherical end cap bulkheads
	vec3 emission_color = vec3(0.0);
	if (is_end_cap > 0.5) {
		float r_axis = length(world_pos.xy);
		float alpha = vert_attr.r; // Latitude parameter: 0.0 at apex pole to 1.0 at cylinder rim

		// Polar UV projection: maps circular radial rib texture across the hemisphere
		vec2 polar_uv = vec2(0.5, 0.5);
		if (r_axis > 0.01) {
			vec2 dir = world_pos.xy / r_axis;
			polar_uv = vec2(0.5, 0.5) + dir * (0.49 * alpha);
		}

		// Sample the dedicated circular radial rib texture
		vec3 col_ribs = texture(tex_end_cap_ribs, polar_uv).rgb;
		vec3 col_alloy_grain = texture(tex_concrete, world_pos.xy * 0.015).rgb;
		vec3 bulkhead_base = mix(col_concrete * 0.9, col_ribs * 1.5, 0.75);

		// Structural concentric hoop rings (every 250 m) and radial compression ribs
		float ring_dist = abs(fract(r_axis / 250.0 + 0.5) - 0.5) * 250.0;
		float ring_line = smoothstep(10.0, 0.0, ring_dist);
		float spoke_val = abs(fract(angle / (6.28318530718 / 32.0) + 0.5) - 0.5);
		float spoke_line = smoothstep(0.010, 0.0, spoke_val);

		// Subtle girder structure overlay
		bulkhead_base = mix(bulkhead_base, bulkhead_base * 0.85, ring_line * 0.25 + spoke_line * 0.25);

		final_color = bulkhead_base;
		roughness_val = 0.75;
		metallic_val = 0.05;

		// Central Zero-G spaceport active docking ring and guidance lighting
		if (r_axis < 350.0) {
			float dock_circle = abs(r_axis - 220.0);
			if (dock_circle < 16.0) {
				final_color = vec3(0.98, 0.78, 0.22); // Golden aerospace guidance ring
				emission_color += vec3(1.0, 0.82, 0.25) * 3.0;
				roughness_val = 0.20;
				metallic_val = 0.20;
			}
			float inner_ring = abs(r_axis - 100.0);
			if (inner_ring < 12.0) {
				final_color = vec3(0.20, 0.85, 0.95); // Cyan active docking beacon ring
				emission_color += vec3(0.20, 0.88, 1.0) * 4.0;
				roughness_val = 0.15;
				metallic_val = 0.20;
			}
		}

		// Architectural foundation transition into the cylinder floor perimeter apron
		if (alpha > 0.90) {
			float apron_blend = smoothstep(0.90, 1.0, alpha);
			final_color = mix(final_color, col_concrete, apron_blend * 0.50);
		}
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

	// Axial lighting spectrum & time-of-day gradient along the 18 km cylinder
	if (axial_light_enabled > 0.5) {
		float t_z = clamp((world_pos.z + cylinder_length * 0.5) / cylinder_length, 0.0, 1.0);
		vec4 axial_light = texture(axial_light_lut, vec2(t_z, 0.5));
		vec3 axial_col = axial_light.rgb;
		float axial_lum = axial_light.a;
		final_color *= axial_col * mix(0.35, 1.15, clamp(axial_lum, 0.0, 1.0));
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
		// For end caps, attenuate air scatter so structural radial ribs remain crisp and distinct
		float air_factor = clamp((cam_dist - air_distance_min) / max(air_distance_max - air_distance_min, 1.0), 0.0, 1.0);
		// No shader fog on end caps — engine fog suppressed via FOG output; axial LUT handles depth tinting
		float endcap_fog_mult = (is_end_cap > 0.5) ? 0.0 : 1.0;
		float air_scatter = (1.0 - exp(-air_factor * 1.1)) * endcap_fog_mult;

		// Atmospheric haze reflects the current light level and color along the cylinder
		vec3 target_air_color = air_color.rgb;
		float light_lum = 1.0;
		if (axial_light_enabled > 0.5) {
			float t_z = clamp((world_pos.z + cylinder_length * 0.5) / cylinder_length, 0.0, 1.0);
			vec4 axial_light = texture(axial_light_lut, vec2(t_z, 0.5));
			vec3 axial_col = axial_light.rgb;
			float axial_lum = clamp(axial_light.a, 0.0, 1.5);
			light_lum = clamp(axial_lum, 0.0, 1.0);
			target_air_color = air_color.rgb * mix(vec3(1.0), axial_col, 0.65) * mix(0.10, 1.00, light_lum);
		}

		// The fog is more transparent as the light is darker (clearing the night air for surface lights)
		float dark_transparency_mult = mix(0.12, 1.0, light_lum);
		final_color = mix(final_color, target_air_color, air_scatter * air_density * dark_transparency_mult);
	}

	ALBEDO = final_color;
	ROUGHNESS = roughness_val;
	METALLIC = metallic_val;
	EMISSION = emission_color;
}
