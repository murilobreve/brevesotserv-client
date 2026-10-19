// Baiak Rarity System - Pale tier, alive (kit "Renascimento, quatro presencas":
// the veil). Strongly drained, cold light: grey-blue shadows, sea-glass
// tones, pearl on the lit parts. It never turns back to its own green and
// stays opaque while it fights. A slow cold sheen is keyed by brightness, not
// by v_TexCoord (a place in the sprite atlas that changes every animation
// frame), so it does not jump while the monster walks.
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
    vec3 shadow = vec3(0.161, 0.220, 0.267);
    vec3 mid = vec3(0.471, 0.671, 0.722);
    vec3 light = vec3(0.898, 0.957, 0.945);
    vec3 result = ramp(clamp(l * 1.25, 0.0, 1.0), shadow, mid, light);
    result = mix(result, vec3(l) * vec3(0.92, 1.0, 1.04), 0.12);
    float sheen = smoothstep(0.85, 1.0, sin(l * 14.0 + u_Time * 0.9)) * smoothstep(0.35, 0.8, l);
    result = mix(result, light, sheen * 0.35);
    result = mix(result, c, face(c) * 0.8);
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
