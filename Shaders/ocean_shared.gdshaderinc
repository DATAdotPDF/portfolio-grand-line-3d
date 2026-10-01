// ocean_shared.gdshaderinc
const float PLANET_RADIUS = 280.0;
const float PI_CONST = 3.14159265359;

struct WaveComponent {
    vec2 dir;        // Direção no espaço tangente
    float amplitude; // Altura da onda (a)
    float wavelength;// Comprimento (lambda)
    float speed;     // Velocidade de fase (c)
    float steepness; // Nitidez da crista trocoidal (Q)
};

// Calcula a elevação e deslocamento tangencial trocoidal sobre a esfera
void evaluate_spherical_gerstner(
    vec3 sphere_pos, 
    float time, 
    out vec3 displaced_pos, 
    out vec3 normal, 
    out float crest_factor
) {
    vec3 N = normalize(sphere_pos);
    
    // Base ortonormal tangente na esfera
    vec3 tangent = normalize(cross(N, abs(N.y) > 0.99 ? vec3(0, 0, 1) : vec3(0, 1, 0)));
    vec3 bitangent = cross(N, tangent);
    
    vec2 uv_sphere = vec2(dot(sphere_pos, tangent), dot(sphere_pos, bitangent));
    
    // 4 Componentes trocoidais em direções sobrepostas (Wind Waker style)
    WaveComponent waves[4];
    waves[0] = WaveComponent(vec2(1.0, 0.2),  0.90, 22.0, 1.8, 0.45);
    waves[1] = WaveComponent(vec2(-0.4, 0.9), 0.60, 14.0, 2.2, 0.40);
    waves[2] = WaveComponent(vec2(0.7, -0.7), 0.35,  8.0, 3.1, 0.35);
    waves[3] = WaveComponent(vec2(-0.8, -0.5),0.20,  4.5, 4.0, 0.30);
    
    vec3 d_tangent = vec3(0.0);
    float radial_disp = 0.0;
    crest_factor = 0.0;
    
    for (int i = 0; i < 4; i++) {
        float k = 2.0 * PI_CONST / waves[i].wavelength;
        float w = sqrt(9.81 * k); // Relação de dispersão em águas profundas: w^2 = g*k
        vec2 d = normalize(waves[i].dir);
        
        float theta = k * dot(d, uv_sphere) - w * time * waves[i].speed;
        float sin_t = sin(theta);
        float cos_t = cos(theta);
        
        // Deslocamento trocoidal (Trochoid / Gerstner):
        // Puxa lateralmente para criar cristas finas
        vec2 lateral = d * (waves[i].steepness * waves[i].amplitude * sin_t);
        d_tangent += (tangent * lateral.x + bitangent * lateral.y);
        
        // Elevação radial ao longo de N
        radial_disp += waves[i].amplitude * cos_t;
        
        // Fator de crista para a espuma do topo da onda
        crest_factor += waves[i].steepness * cos_t;
    }
    
    // Posição final na superfície do globo
    displaced_pos = N * (PLANET_RADIUS + radial_disp) - d_tangent;
    
    // Recalcula a normal perturbada
    normal = normalize(N - (d_tangent * 0.15) + N * (radial_disp * 0.05));
    crest_factor = clamp(crest_factor, 0.0, 1.0);
}
