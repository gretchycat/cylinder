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

	// Minor grid
	vec2 minor_uv = vec2(arc_dist, z_dist) / minor_grid_spacing;
	vec2 minor_grid = abs(fract(minor_uv - 0.5) - 0.5) / fwidth(minor_uv);
	float minor_line = 1.0 - min(min(minor_grid.x, minor_grid.y), 1.0);

	// Major grid
	vec2 major_uv = vec2(arc_dist, z_dist) / major_grid_spacing;
	vec2 major_grid = abs(fract(major_uv - 0.5) - 0.5) / fwidth(major_uv);
	float major_line = 1.0 - min(min(major_grid.x, major_grid.y), 1.0);

	// Panel subtle variation
	vec2 panel_id = floor(major_uv);
	float panel_noise = fract(sin(dot(panel_id, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 surface_col = mix(base_color.rgb * 0.95, base_color.rgb * 1.05, panel_noise);

	// Composite grid lines onto gray surface
	surface_col = mix(surface_col, line_color.rgb, minor_line * 0.6);
	surface_col = mix(surface_col, accent_line_color.rgb, major_line * 0.9);

	ALBEDO = surface_col;
	ROUGHNESS = mix(roughness, 0.4, max(minor_line, major_line));
	METALLIC = metallic;
}
