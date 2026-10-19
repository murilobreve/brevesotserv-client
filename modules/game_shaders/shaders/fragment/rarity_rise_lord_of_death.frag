// Rarity revive - Lord of Death, rising: the garnet veins take over, growing
// and settling without any abrupt flash; the body takes the shadow in.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
// the kit's three stops: shadow, material, light
vec3 ramp(float l, vec3 shadow, vec3 mid, vec3 light)
{
    return mix(mix(shadow, mid, smoothstep(0.0, 0.55, l)), light, smoothstep(0.55, 1.0, l));
}
// the red of eyes and mouth stays, so the monster keeps its face
float face(vec3 c) { return smoothstep(0.22, 0.45, c.r - max(c.g, c.b)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;
    float l = luma(c);
    vec3 shadow = vec3(0.067, 0.063, 0.090);
    vec3 mid = vec3(0.475, 0.176, 0.259);
    vec3 light = vec3(0.765, 0.361, 0.408);
    float t = clamp(l * 1.2, 0.0, 1.0);
    vec3 result = mix(shadow, vec3(0.22, 0.10, 0.13), smoothstep(0.05, 0.9, t));
    float v = abs(noise(gl_FragCoord.xy * 0.06) - 0.5);
    float vein = 1.0 - smoothstep(0.0, 0.08, v);
    float presence = 0.7 + 0.2 * sin(u_Time * 2.2);
    result = mix(result, mix(mid, light, 0.3), vein * presence * smoothstep(0.05, 0.25, l));
    result = mix(result, c, face(c) * 0.8);
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
