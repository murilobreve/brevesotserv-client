// Baiak Rarity System - Lord of Death tier, alive (the eclipse): black tinted
// with wine, discreet cold edges on its brightest parts and rare garnet veins.
// The brightness steps stay, so eyes and limbs remain apart, and it breathes
// slowly. Keyed by the pixel's own colour, not by v_TexCoord, so it does not
// jump while the monster walks.
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
void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;
    float l = luma(c);
    vec3 shadow = vec3(0.067, 0.063, 0.090);
    vec3 mid = vec3(0.475, 0.176, 0.259);
    vec3 light = vec3(0.765, 0.361, 0.408);
    float t = clamp(l * 1.2, 0.0, 1.0);
    vec3 result = mix(shadow, vec3(0.20, 0.09, 0.12), smoothstep(0.1, 0.9, t));
    result += vec3(0.10, 0.12, 0.16) * smoothstep(0.65, 0.95, t);
    float vein = smoothstep(0.94, 1.0, sin(t * 29.0 + (c.r - c.g) * 7.0 + u_Time * 0.5));
    result = mix(result, mid, vein * 0.55);
    result *= 0.92 + 0.08 * sin(u_Time * 1.0);
    result = mix(result, c, face(c) * 0.9);
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
