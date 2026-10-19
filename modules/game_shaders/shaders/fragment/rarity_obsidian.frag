// Baiak Rarity System - Obsidian tier, alive (the fractured crown): dark
// indigo glass with cold edges, the face, wings and body still apart. Light
// travels through the glass instead of pulsing on the whole body. Keyed by
// the pixel's own colour, not by v_TexCoord, so it does not jump while the
// monster walks.
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
    vec3 shadow = vec3(0.090, 0.090, 0.176);
    vec3 mid = vec3(0.561, 0.455, 0.847);
    vec3 light = vec3(0.612, 0.737, 0.922);
    float t = clamp(l * 1.2, 0.0, 1.0);
    vec3 result = ramp(t, shadow, mid * 0.75, light);
    result = mix(result, ramp(floor(t * 5.0) / 5.0, shadow, mid * 0.75, light), 0.35);
    float travel = smoothstep(0.9, 1.0, sin(t * 12.0 - u_Time * 1.2));
    result = mix(result, light, travel * 0.4 * smoothstep(0.25, 0.7, t));
    result = mix(result, c, face(c) * 0.7);
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
