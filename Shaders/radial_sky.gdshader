shader_type sky;

uniform vec3 local_up = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);

group_uniforms SkyGradients;
uniform vec3 day_zenith_color : source_color = vec3(0.18, 0.52, 0.88);
uniform vec3 day_horizon_color : source_color = vec3(0.72, 0.88, 0.98);
uniform vec3 sunset_horizon_color : source_color = vec3(0.95, 0.42, 0.18);
uniform vec3 night_zenith_color : source_color = vec3(0.01, 0.02, 0.08);
uniform vec3 night_horizon_color : source_color = vec3(0.06, 0.09, 0.20);

group_uniforms SunParameters;
uniform float sun_disk_size : hint_range(0.005, 0.1) = 0.025;
uniform float sun_bloom : hint_range(0.01, 0.5) = 0.15;
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);

group_uniforms StarsAndClouds;
uniform float star_density : hint_range(50.0, 600.0) = 280.0;
uniform float star_twinkle_speed : hint_range(0.5, 8.0) = 3.2;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform vec3 cloud_day_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_night_color : source_color = vec3(0.12, 0.15, 0.28);

// Hash pseudo-aleatório para geração de estrelas pontuais
float hash3(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Ruído simples para nuvens estilizadas
float noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(i + vec3(0,0,0)), hash3(i + vec3(1,0,0)), f.x),
            mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
        mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
            mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z
    );
}

void sky() {
    vec3 dir = EYEDIR;
    vec3 sun_dir = normalize(sun_direction);
    
    // Fator Dia / Pôr do Sol / Noite baseado na altura do Sol
    vec3 horizon_up = normalize(local_up);
    float sun_height = dot(sun_dir, horizon_up);
    float day_factor = smoothstep(-0.15, 0.25, sun_height);
    float sunset_factor = (1.0 - abs(sun_height * 4.0)) * (1.0 - day_factor);
    sunset_factor = clamp(sunset_factor, 0.0, 1.0);
    
    // Gradiente da abóbada (Zenith até o Horizonte)
    float horizon_gradient = clamp(dot(dir, horizon_up), 0.0, 1.0);
    
    vec3 day_sky = mix(day_horizon_color, day_zenith_color, pow(horizon_gradient, 0.7));
    vec3 night_sky = mix(night_horizon_color, night_zenith_color, pow(horizon_gradient, 0.7));
    day_sky = mix(day_sky, sunset_horizon_color, sunset_factor * (1.0 - horizon_gradient));
    
    vec3 base_color = mix(night_sky, day_sky, day_factor);
    
    // Disco Solar e Brilho
    float sun_dot = max(dot(dir, sun_dir), 0.0);
    float sun_disk = smoothstep(1.0 - sun_disk_size, 1.0 - sun_disk_size * 0.5, sun_dot);
    float sun_glow = pow(sun_dot, 16.0) * sun_bloom * day_factor;
    vec3 final_sun = (sun_disk * 4.0 + sun_glow) * sun_color;
    
    // Céu Estrelado (Ativo apenas à noite e longe do horizonte)
    float night_visibility = (1.0 - day_factor)
        * smoothstep(0.05, 0.35, dot(dir, horizon_up));
    vec3 star_color = vec3(0.0);
    if (night_visibility > 0.01) {
        vec3 star_grid = floor(dir * star_density);
        float star_val = hash3(star_grid);
        if (star_val > 0.985) {
            float twinkle = sin(TIME * star_twinkle_speed + star_val * 45.0) * 0.5 + 0.5;
            float star_intensity = pow((star_val - 0.985) / 0.015, 2.0) * twinkle;
            star_color = vec3(star_intensity * night_visibility * 1.8);
        }
    }
    
    // Nuvens estilizadas Wind Waker / One Piece
    vec3 cloud_p = dir * 4.0 + vec3(TIME * 0.015, 0.0, TIME * 0.01);
    float cloud_val = noise(cloud_p) * 0.6 + noise(cloud_p * 2.1) * 0.4;
    float cloud_alpha = smoothstep(1.0 - cloud_coverage, 1.0, cloud_val)
        * smoothstep(0.0, 0.25, dot(dir, horizon_up));
    vec3 cloud_col = mix(cloud_night_color, cloud_day_color, day_factor);
    
    // Composição Final da Radiância do Céu
    COLOR = mix(base_color + star_color + final_sun, cloud_col, cloud_alpha * 0.85);
}
