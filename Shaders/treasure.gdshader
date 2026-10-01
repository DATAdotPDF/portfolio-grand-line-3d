shader_type spatial;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform float night=0.0;
void fragment() {
 vec3 c=texture(albedo_map,UV).rgb;
 float gold=smoothstep(0.5,0.8,c.r)*smoothstep(0.40,0.68,c.g)*(1.0-smoothstep(0.15,0.38,c.b));
 ALBEDO=c;
 METALLIC=gold;
 ROUGHNESS=mix(0.8,0.1,gold);
 EMISSION=vec3(1.0,0.55,0.07)*gold*night*0.35;
}
