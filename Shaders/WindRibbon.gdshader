shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform float phase_offset = 0.0;
uniform float loop_style = 1.0;
uniform float cycle_seconds = 4.0;
uniform float age = 0.0;
uniform vec4 ribbon_color : source_color = vec4(0.75, 0.85, 0.91, 0.26);
varying float ribbon_opacity;

vec2 wind_path(float t) {
	float loop_window = smoothstep(0.25, 0.32, t) * (1.0 - smoothstep(0.64, 0.70, t));
	float turn = 6.2831853 * (t - 0.30) / 0.36;
	vec2 looping = vec2(
		16.0 * t + 3.0 * sin(turn) * loop_window,
		1.6 * (1.0 - cos(turn)) * loop_window + 0.18 * sin(t * 18.0)
	);
	vec2 streaming = vec2(20.0 * t, 0.34 * sin(t * 17.0 + phase_offset * 6.2831853));
	return mix(streaming, looping, loop_style);
}

void vertex() {
	float tail_age = age - (1.0 - UV.x) * 0.23;
	float sample_age = max(tail_age, 0.0);
	vec2 point = wind_path(sample_age);
	vec2 tangent = normalize(wind_path(min(sample_age + 0.003, 1.0)) - wind_path(max(sample_age - 0.003, 0.0)) + vec2(0.0001, 0.0));
	vec2 cross_axis = vec2(-tangent.y, tangent.x);
	float taper = pow(max(sin(UV.x * 3.14159265), 0.0), 0.72);
	float width = 0.065 * taper;
	vec2 vertex_position = point + cross_axis * ((UV.y - 0.5) * width);
	VERTEX = vec3(vertex_position.x - 8.0, vertex_position.y, 0.05 * sin(sample_age * 12.0));
	ribbon_opacity = step(0.0, tail_age) * taper * smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.72, 1.0, age));
}

void fragment() {
	ALBEDO = ribbon_color.rgb;
	ALPHA = ribbon_color.a * ribbon_opacity;
}
