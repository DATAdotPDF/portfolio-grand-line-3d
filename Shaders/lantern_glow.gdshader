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
// Direção para onde a lâmpada aponta (espaço da malha): o lado do vidro virado para ela brilha mais e
// esse ponto quente gira junto com o facho (o topo do farol fica parado).
uniform vec3 beam_dir = vec3(0.0, 0.0, -1.0);

varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
}

void fragment() {
	vec3 base = texture(albedo_map, UV).rgb * tint.rgb;
	ALBEDO = base;
	float near = 1.0 - smoothstep(glow_radius * 0.7, glow_radius, distance(model_pos, glow_center));
	float bright = smoothstep(0.3, 0.6, max(base.r, max(base.g, base.b)));
	vec3 from_center = model_pos - glow_center;
	float facing = max(dot(normalize(vec3(from_center.x, 0.0, from_center.z) + vec3(0.0001)), normalize(vec3(beam_dir.x, 0.0, beam_dir.z) + vec3(0.0001))), 0.0);
	float sweep = 0.12 + 2.4 * pow(facing, 6.0);
	EMISSION = glow_color * near * bright * night * 2.2 * sweep;
	ROUGHNESS = 0.85;
}
