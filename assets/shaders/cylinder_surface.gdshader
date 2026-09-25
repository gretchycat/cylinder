shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.48, 0.50, 0.53, 1.0);
uniform vec4 line_color : source_color = vec4(0.32, 0.34, 0.37, 1.0);
uniform vec4 accent_line_color : source_color = vec4(0.22, 0.24, 0.27, 1.0);
uniform float major_grid_spacing = 20.0;
uniform float minor_grid_spacing = 4.0;
uniform float line_thickness = 0.04;
uniform float roughness : hint_range(0.0, 1.0) = 0.75;
uniform float metallic : hint_range(0.0, 1.0) = 0.15;

uniform vec4 air_color : source_color = vec4(0.52, 0.72, 0.88, 1.0);
uniform float air_density : hint_range(0.0, 1.0) = 0.65;
uniform float air_distance_min = 200.0;
uniform float air_distance_max = 18000.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Calculate circumference arc distance and Z distance
	// Cylinder axis is along Z
	float angle = atan(world_pos.y, world_pos.x);
	if (angle < 0.0) {
		angle += 6.28318530718;
	}
	float radius = length(world_pos.xy);
	float arc_dist = angle * radius;
	float z_dist = world_pos.z;

	vec2 minor_uv;
	vec2 major_uv;
	if (abs(NORMAL.z) > 0.5) {
		// Planar projection for end cap bulkheads
		minor_uv = world_pos.xy / minor_grid_spacing;
		major_uv = world_pos.xy / major_grid_spacing;
	} else {
		// Cylindrical projection for cylinder barrel
		minor_uv = vec2(arc_dist, z_dist) / minor_grid_spacing;
		major_uv = vec2(arc_dist, z_dist) / major_grid_spacing;
	}
	vec2 major_grid = abs(fract(major_uv - 0.5) - 0.5) / fwidth(major_uv);
	float major_line = 1.0 - min(min(major_grid.x, major_grid.y), 1.0);

	// Panel subtle variation
	vec2 panel_id = floor(major_uv);
	float panel_noise = fract(sin(dot(panel_id, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 surface_col = mix(base_color.rgb * 0.95, base_color.rgb * 1.05, panel_noise);

	// Composite grid lines onto gray surface
	surface_col = mix(surface_col, line_color.rgb, minor_line * 0.6);
	surface_col = mix(surface_col, accent_line_color.rgb, major_line * 0.9);

	// Atmospheric aerial perspective: tint distant views across the 8 km cylinder
	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	float air_factor = clamp((cam_dist - air_distance_min) / max(air_distance_max - air_distance_min, 1.0), 0.0, 1.0);
	float air_scatter = 1.0 - exp(-air_factor * 1.8);
	surface_col = mix(surface_col, air_color.rgb, air_scatter * air_density);

	ALBEDO = surface_col;
	ROUGHNESS = mix(roughness, 0.4, max(minor_line, major_line));
	METALLIC = metallic;
}
