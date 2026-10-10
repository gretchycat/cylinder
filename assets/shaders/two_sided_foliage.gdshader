shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.2;
uniform float roughness : hint_range(0.0, 1.0) = 0.75;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

varying vec4 foliage_vertex_color;

void vertex() {
	// Carry imported glTF COLOR_0 explicitly into the fragment stage.  Some
	// mobile shader paths otherwise leave the fragment COLOR input undefined.
	foliage_vertex_color = COLOR;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec4 surface = tex * albedo_color * foliage_vertex_color;
	if (surface.a < alpha_scissor) {
		discard;
	}

	ALBEDO = surface.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;

	// Alpha-masked foliage is intentionally double-sided. Face the normal
	// toward the camera so reversed leaf triangles receive ambient and point
	// lighting instead of rendering as a dark backface.
	NORMAL = normalize(NORMAL);
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
}
