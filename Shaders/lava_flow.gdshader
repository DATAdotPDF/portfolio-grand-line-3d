shader_type spatial;
render_mode unshaded, cull_disabled;

// Rio de lava do vulcão (WorldDecor.gd): fita que desce da cratera até o mar.
// UV.x = através da fita (0..1), UV.y = metros ao longo dela (0 = cratera).
// Miolo amarelo-laranja correndo morro abaixo, crosta escura que racha e borda recortada.

uniform float flow_speed = 0.55;
uniform vec3 hot_color : source_color = vec3(1.0, 0.82, 0.32);
uniform vec3 warm_color : source_color = vec3(1.0, 0.32, 0.04);
uniform vec3 crust_color : source_color = vec3(0.13, 0.05, 0.04);

float h2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float along = UV.y;
	float t = TIME * flow_speed;
	// Borda recortada (a lava não escorre em linha reta).
	float ragged = 0.78 + 0.22 * n2(vec2(along * 0.9, 3.7));
	if (across > ragged) {
		discard;
	}
	float flow = n2(vec2(UV.x * 3.0, along * 0.45 - t)) * 0.65 + n2(vec2(UV.x * 7.0, along * 1.3 - t * 1.6)) * 0.35;
	// Crosta: placas escuras que vão para a borda e racham por cima do miolo.
	float plates = n2(vec2(UV.x * 5.0 + 11.0, along * 0.7 - t * 0.7));
	float crust = smoothstep(0.5, 0.72, plates + across * 0.55 - 0.18);
	vec3 molten = mix(warm_color, hot_color, smoothstep(0.35, 0.85, flow) * (1.0 - across * 0.6));
	ALBEDO = mix(molten * 1.5, crust_color, crust * 0.9);
}
