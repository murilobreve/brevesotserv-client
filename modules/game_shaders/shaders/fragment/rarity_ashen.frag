// Baiak Rarity System - Ashen tier, alive (the flower of ash): mostly dark
// charcoal grey, copper in its fissures and a few amber glints, never the
// whole body orange. Fissures and glints are keyed by the pixel's own colour,
// not by v_TexCoord, so they do not jump while it walks.
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
    vec3 shadow = vec3(0.161, 0.133, 0.141);
    vec3 mid = vec3(0.788, 0.443, 0.208);
    vec3 light = vec3(0.953, 0.741, 0.451);
    vec3 result = mix(shadow, vec3(0.42, 0.39, 0.39), smoothstep(0.05, 0.8, l));
    float fissure = smoothstep(0.82, 0.98, sin(l * 38.0 + (c.g - c.r) * 9.0)) * smoothstep(0.15, 0.5, l);
    result = mix(result, mid, fissure * 0.75);
    float glint = smoothstep(0.96, 1.0, sin(l * 61.0 + u_Time * 0.7)) * smoothstep(0.4, 0.8, l);
    result = mix(result, light, glint * 0.6);
    result = mix(result, c, face(c) * 0.6);
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
