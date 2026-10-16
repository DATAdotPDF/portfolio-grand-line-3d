shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

// Gaivota procedural (Seagulls.gd): malha de poucos triângulos em "V".
// UV.y = quanto o vértice acompanha a batida (0 no corpo, 1 na ponta da asa).
// UV.x = pintura: 0 branco (corpo), 0.5 cinza (asa), 1 preto (ponta).
// Cor da instância (Seagulls.gd): r = batendo asa (1) ou planando (0), g = fase.
// (Sem custom data do MultiMesh, que no Compatibility chegava corrompido.)

uniform vec3 body_color : source_color = vec3(0.96, 0.96, 0.94);
uniform vec3 wing_color : source_color = vec3(0.7, 0.74, 0.78);
uniform vec3 tip_color : source_color = vec3(0.12, 0.12, 0.14);
uniform float flap_amount = 0.5;
varying float paint;

void vertex() {
	float h1 = clamp(COLOR.g, 0.0, 1.0);
	float phase = h1 * 6.2831853;
	float rate = mix(5.5, 8.0, h1);
	float flapping = clamp(COLOR.r, 0.0, 1.0);
	// Batida: sobe rápido, desce com força; planando, asas levemente para cima.
	float beat = sin(TIME * rate + phase);
	float lift = mix(0.12, beat, flapping);
	float w = UV.y;
	VERTEX.y += abs(VERTEX.x) * lift * flap_amount * w;
	// A ponta dobra um pouco atrasada (asa não é uma tábua).
	VERTEX.y += abs(VERTEX.x) * sin(TIME * rate + phase - 0.9) * 0.15 * flapping * w * w;
	VERTEX.y = clamp(VERTEX.y, -1.0, 1.0);
	paint = UV.x;
}

void fragment() {
	vec3 c = mix(body_color, wing_color, smoothstep(0.25, 0.35, paint));
	c = mix(c, tip_color, smoothstep(0.75, 0.85, paint));
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
