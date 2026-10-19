// Rarity revive - Pale, waking: the corpse goes from its own colour to a
// grey blue, eyes, mouth and outlines still readable, and breathes slowly.
// No fading in and out: the body stays whole.
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
    vec3 result = ramp(clamp(l * 1.15, 0.0, 1.0), shadow, mid * 0.85, light * 0.85);
    result = mix(result, vec3(l), 0.15);
    result *= 0.94 + 0.06 * (0.5 + 0.5 * sin(u_Time * 2.5));
    result = mix(result, c, face(c) * 0.7);
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
