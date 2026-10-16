shader_type spatial;
render_mode cull_disabled;

// Tentáculo do kraken (KrakenEvent.gd): tubo afinando ao longo de Y (UV.y = 0 base .. 1 ponta),
// UV.x = volta. O vertex curva o tentáculo em ondas que sobem até a ponta (que enrola), com fase
// própria de cada um. Duas cores (dorso escuro, ventre claro com ventosas) em degraus, no estilo
// cartoon das ilhas.

uniform float phase = 0.0;
uniform float height = 16.0;
uniform float curl = 1.0;          // quanto a ponta enrola
uniform float sway = 1.0;
uniform vec3 back_color : source_color = vec3(0.26, 0.08, 0.16);
uniform vec3 belly_color : source_color = vec3(0.78, 0.42, 0.42);
uniform vec3 sucker_color : source_color = vec3(0.95, 0.75, 0.68);
uniform float night = 0.0;

varying float v_t;
varying float v_side;

void vertex() {
	float t = UV.y;
	v_t = t;
	// Ventosas (rosa) do lado -Z: o nó olha para o centro do redemoinho, então elas ficam viradas
	// para dentro do funil.
	v_side = cos((UV.x - 0.75) * 6.2831853);
	float tt = TIME * 1.2 + phase;
	// Curva principal: sobe ondulando; a ponta enrola para dentro.
	float bend = sin(tt + t * 3.2) * pow(t, 1.4) * 3.2 * sway;
	float lean = (cos(tt * 0.7 + t * 2.1) * 0.6 + 1.0) * pow(t, 1.8) * 2.0;
	float c = curl * smoothstep(0.55, 1.0, t);
	// Arqueia para dentro do redemoinho (-Z).
	vec3 offset = vec3(bend, 0.0, -lean);
	// Enrolar: gira o fim do tentáculo em volta do eixo X.
	float a = c * 2.4 * (0.8 + 0.2 * sin(tt * 1.3));
	float y = VERTEX.y;
	float pivot = height * 0.55;
	if (y > pivot) {
		float d = y - pivot;
		float ang = a * (d / (height - pivot));
		VERTEX.y = pivot + d * cos(ang);
		VERTEX.z -= d * sin(ang) * 1.1;
	}
	VERTEX += offset;
}

void fragment() {
	float light = smoothstep(-0.1, 0.35, dot(NORMAL, normalize(vec3(0.4, 0.9, 0.3))));
	vec3 col = mix(back_color * 0.7, back_color, step(0.5, light));
	float belly = step(0.35, v_side);
	col = mix(col, belly_color, belly);
	// Ventosas: duas fileiras de bolinhas no ventre, menores para a ponta.
	vec2 g = vec2(v_side * 3.0, v_t * 48.0);
	vec2 cell = fract(g) - 0.5;
	float size = mix(0.38, 0.12, v_t);
	float sucker = belly * step(length(cell * vec2(1.0, 1.4)), size) * step(0.55, v_side);
	col = mix(col, sucker_color, sucker);
	// Brilho úmido no dorso.
	col += vec3(0.25, 0.2, 0.3) * pow(clamp(1.0 - abs(dot(NORMAL, VIEW)), 0.0, 1.0), 4.0);
	ALBEDO = col * mix(1.0, 0.45, night);
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
}
