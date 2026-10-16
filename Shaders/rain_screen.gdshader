shader_type canvas_item;

// Véu da tempestade (Weather): um cinza-esverdeado quase invisível entre a câmera e as gotas
// quando o barco está dentro da chuva, mais o clarão do relâmpago. As gotas em si são partículas.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 veil_color : source_color = vec3(0.45, 0.5, 0.48);
uniform float veil = 0.09;

void fragment() {
	// Um pouco mais denso em cima e nas bordas (como água no ar), quase nada no centro de baixo.
	float edge = smoothstep(0.25, 0.75, length(UV - vec2(0.5, 0.65)));
	float a = intensity * veil * (0.6 + 0.4 * edge + 0.3 * (1.0 - UV.y));
	vec3 col = mix(veil_color, vec3(0.92, 0.95, 1.0), flash);
	COLOR = vec4(col, clamp(a + flash * 0.08, 0.0, 1.0));
}
