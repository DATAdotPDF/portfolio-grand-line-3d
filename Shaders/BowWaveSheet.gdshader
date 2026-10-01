shader_type spatial;
render_mode world_vertex_coords, cull_disabled, blend_mix, depth_draw_never, unshaded;
uniform float ocean_radius = 90.0;
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
uniform sampler2D foam_pattern : repeat_enable, filter_linear_mipmap;
uniform vec3 water_edge_color : source_color = vec3(0.07, 0.32, 0.44);
uniform vec3 sheet_foam_color : source_color = vec3(0.88, 0.98, 0.98);

vec3 curling_sheet(vec2 uv) {
	float u = clamp(uv.x, 0.0, 1.0);
	float v = clamp(uv.y, 0.0, 1.0);
	float moving = smoothstep(0.4, 4.0, boat_speed);
	float envelope = pow(max(sin(u * 3.14159265), 0.0), 0.85);
	float bank = clamp(1.0 + side * turn_bias * 0.22, 0.75, 1.25);
	float hull_width = 0.17 + 0.43 * smoothstep(0.0, 0.68, u);
	float curl = envelope * moving * bank;
	float outward = curl * (0.20 * v + 0.67 * pow(v, 2.2));
	vec3 base = boat_position + boat_forward * (1.75 - u * 2.85)
		+ boat_right * side * (hull_width + outward);
	vec3 radial_up = normalize(base);
	float rise = -0.08 + curl * (0.20 * v + 0.66 * sin(v * 1.7));
	float surface_height = mix(water_height_front,water_height_back,u);
	return radial_up * (ocean_radius + surface_height + rise);
}

void vertex() {
	VERTEX = curling_sheet(UV);
}

void fragment() {
	float moving = smoothstep(0.4, 4.0, boat_speed);
	float length_fade = smoothstep(0.0, 0.13, UV.x)
		* (1.0 - smoothstep(0.67, 1.0, UV.x));
	float height_fade = smoothstep(0.05, 0.43, UV.y);
	float crest = smoothstep(0.47, 0.94, UV.y);
	float flow = UV.x * 2.8 - TIME * (0.22 + boat_speed * 0.17);
	float foam_tex = texture(foam_pattern, vec2(flow, UV.y * 1.65 + TIME * 0.11)).r;
	float foam_mix = crest * (0.58 + 0.42 * foam_tex);
	ALBEDO = mix(water_edge_color, sheet_foam_color, foam_mix)*mix(0.23,1.0,daylight);
	ALPHA = clamp(moving * length_fade * height_fade * (0.52 + 0.46 * crest), 0.0, 0.96);
}
