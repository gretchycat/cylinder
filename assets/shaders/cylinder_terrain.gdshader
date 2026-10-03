shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx, fog_disabled;

uniform sampler2D terrain_map : filter_nearest, repeat_enable;
uniform vec2 terrain_map_size;
uniform sampler2DArray biome_textures : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D biome_tints : source_color, filter_nearest, repeat_disable;
// R = texture array layer, G = repeat size in metres, B = roughness.
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
varying vec3 world_pos;
varying float end_cap;

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
		// Same nearest-sample convention as TerrainManager, clamp axial edges.
		vec2 cell = vec2(mod(floor(u * terrain_map_size.x + 0.5), terrain_map_size.x), floor(v * (terrain_map_size.y - 1.0) + 0.5));
		float id = round(texture(terrain_map, (cell + 0.5) / terrain_map_size).r * 255.0);
		vec2 table_uv = vec2((id + 0.5) / 256.0, 0.5);
		vec4 parameters = texture(biome_parameters, table_uv);
		vec4 tint = texture(biome_tints, table_uv);
		float repeats = max(round(TAU * cylinder_radius / parameters.g), 1.0);
		vec2 uv = vec2(u * repeats, world_pos.z / parameters.g);
		vec3 tex = texture(biome_textures, vec3(uv, parameters.r)).rgb;
		albedo = mix(tex, tex * tint.rgb, tint.a);
		roughness_value = parameters.b;
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
