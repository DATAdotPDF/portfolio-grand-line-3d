shader_type spatial;
render_mode diffuse_toon, specular_disabled;

// Golfinhos e peixes (SeaLife.gd): malhas de poucos triângulos geradas no código.
// UV.y = posição ao longo do corpo (0 focinho .. 1 cauda): quanto o vértice ondula.
// COLOR = pintura da malha (dorso escuro, barriga clara).
// Golfinho ondula na vertical (cauda sobe e desce); peixe ondula de lado.
// A fase vem do número da instância (sem custom data do MultiMesh, que no Compatibility
// chegava corrompido).

uniform bool lateral = false;
uniform float amplitude = 0.08;
uniform float frequency = 7.0;
uniform float wave_length = 3.0;
uniform float shine = 0.0;          // brilho prateado (peixe)
uniform float night = 0.0;

void vertex() {
	float t = UV.y;
	float phase = TIME * frequency + float(INSTANCE_ID) * 1.7;
	float offset = sin(phase - t * wave_length) * amplitude * t * t;
	if (lateral) {
		VERTEX.x += offset;
	} else {
		VERTEX.y += offset;
	}
}

void fragment() {
	vec3 col = COLOR.rgb;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col += vec3(0.9, 0.95, 1.0) * rim * shine;
	ALBEDO = col * mix(1.0, 0.45, night);
	ROUGHNESS = 0.5;
}
