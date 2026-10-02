shader_type spatial;

// Material da ilha Contato: igual ao original, mas à noite os vidros claros da
// lanterna do farol (perto de glow_center, em espaço do modelo) viram branco
// fluorescente — a luz do farol parece sair de dentro.

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 glow_center;
uniform float glow_radius = 0.075;
uniform float night = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.96, 0.78);

varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
}

void fragment() {
	vec3 base = texture(albedo_map, UV).rgb * tint.rgb;
	ALBEDO = base;
	float near = 1.0 - smoothstep(glow_radius * 0.7, glow_radius, distance(model_pos, glow_center));
	float bright = smoothstep(0.3, 0.6, max(base.r, max(base.g, base.b)));
	EMISSION = glow_color * near * bright * night * 2.2;
	ROUGHNESS = 0.85;
}
