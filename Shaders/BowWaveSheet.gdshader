shader_type spatial;
render_mode world_vertex_coords, cull_disabled, blend_mix, depth_draw_opaque, unshaded;

// Folha de água da proa (referência Seagazer: grade 64×24 por lado, curvada no
// vertex shader). Corpo azul-água translúcido, crista branca grossa com borda
// recortada e uma segunda linha de espuma (ideia de water-wakes/wave.gdshader).
// A raiz fica sempre fora do casco, mesmo inclinado.

uniform float ocean_radius = 800.0;
uniform vec3 boat_position;
uniform vec3 boat_forward;
uniform vec3 boat_right;
uniform float water_height_front = 0.0;
uniform float water_height_back = 0.0;
uniform float side = 1.0;
uniform float boat_speed = 0.0;
uniform float turn = 0.0;
uniform float turn_bias = 0.0;
uniform float daylight = 1.0;
uniform float sheet_scale : hint_range(0.3, 2.5) = 0.72;
uniform sampler2D foam_pattern : repeat_enable, filter_linear_mipmap;
uniform vec3 water_body_color : source_color = vec3(0.1, 0.52, 0.72);
uniform vec3 water_deep_color : source_color = vec3(0.03, 0.3, 0.52);
uniform vec3 sheet_foam_color : source_color = vec3(0.94, 0.99, 1.0);

varying float top_edge;

float scallop(float u) {
	// Borda superior ondulada que corre para trás com a velocidade.
	return 0.5 + 0.5 * sin(u * 19.0 - TIME * (3.0 + boat_speed * 0.6));
}

vec3 curling_sheet(vec2 uv) {
	float u = clamp(uv.x, 0.0, 1.0);
	float v = clamp(uv.y, 0.0, 1.0);
	float moving = smoothstep(0.4, 5.0, boat_speed);
	float fast = smoothstep(5.0, 12.0, boat_speed);
	// Pico perto de 1/3 do comprimento, afinando para a popa.
	float envelope = pow(max(sin(pow(u, 0.75) * 3.14159265), 0.0), 0.8);
	float bank = clamp(1.0 + side * turn_bias * 0.3, 0.7, 1.3);
	float size = sheet_scale * (0.75 + 0.55 * fast);
	float hull_width = 0.24 + 0.62 * smoothstep(0.0, 0.6, u);
	float curl = envelope * moving * bank * size;
	float outward = curl * (0.28 * v + 0.85 * pow(v, 2.0));
	vec3 base = boat_position + boat_forward * (2.0 - u * 3.4)
		+ boat_right * side * (hull_width + outward);
	vec3 radial_up = normalize(base);
	float edge_wave = mix(0.82, 1.0, scallop(u)) ;
	float rise = -0.12 + curl * (0.3 * v + 0.85 * sin(v * 1.65)) * mix(1.0, edge_wave, v);
	float surface_height = mix(water_height_front, water_height_back, u);
	return radial_up * (ocean_radius + surface_height + rise);
}

void vertex() {
	top_edge = scallop(clamp(UV.x, 0.0, 1.0));
	VERTEX = curling_sheet(UV);
}

void fragment() {
	float moving = smoothstep(0.4, 4.0, boat_speed);
	float length_fade = smoothstep(0.0, 0.1, UV.x) * (1.0 - smoothstep(0.72, 1.0, UV.x));
	float height_fade = smoothstep(0.02, 0.25, UV.y);
	// Crista branca grossa no topo e uma segunda linha fina abaixo dela.
	float crest_line = 0.74 - 0.06 * top_edge;
	float crest = smoothstep(crest_line - 0.03, crest_line + 0.02, UV.y);
	float flow = UV.x * 2.8 - TIME * (0.22 + boat_speed * 0.17);
	float second = 0.5 + 0.08 * sin(UV.x * 14.0 - TIME * 4.0);
	float second_line = 1.0 - smoothstep(0.012, 0.03, abs(UV.y - second));
	float foam_tex = texture(foam_pattern, vec2(flow, UV.y * 1.65 + TIME * 0.11)).r;
	vec3 body = mix(water_deep_color, water_body_color, smoothstep(0.0, 0.7, UV.y));
	vec3 color = mix(body, sheet_foam_color, max(crest * (0.85 + 0.15 * foam_tex), second_line * 0.9));
	ALBEDO = color * mix(0.28, 1.0, daylight);
	ALPHA = clamp(moving * length_fade * height_fade, 0.0, 1.0);
}
