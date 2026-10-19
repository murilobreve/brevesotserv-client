// Rarity revive - Obsidian, rising: the glass is about to break; a blue
// reflection runs over one facet after another.
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
    float t = clamp(l * 1.1, 0.0, 1.0);
    float f = fract(t * 5.0);
    float joint = 1.0 - smoothstep(0.0, 0.12, min(f, 1.0 - f));
    float idx = floor(t * 5.0);
    vec3 result = ramp(idx / 5.0, shadow, mid * 0.6, light * 0.7);
    result = mix(result, mid, joint * 0.75);
    float lit = 1.0 - smoothstep(0.0, 0.6, abs(mod(u_Time * 2.5, 5.0) - idx));
    result = mix(result, light, lit * 0.5);
    result = mix(result, c, face(c) * 0.6);
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
