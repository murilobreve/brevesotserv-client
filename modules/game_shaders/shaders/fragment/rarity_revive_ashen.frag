// Rarity revive - Ashen, waking: the corpse turns to charcoal, with a few
// warm cracks that breathe slowly, like a fire about to catch again.
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
// the heart waking in the corpse: a double beat (lub-dub) a little faster
// than one a second
float heartbeat(float t)
{
    float f = fract(t * 1.25);
    float lub = (f - 0.08) / 0.08;
    float dub = (f - 0.32) / 0.09;
    return min(1.0, exp(-lub * lub) + 0.6 * exp(-dub * dub));
}
void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;
    float l = luma(c);
    vec3 shadow = vec3(0.161, 0.133, 0.141);
    vec3 mid = vec3(0.788, 0.443, 0.208);
    vec3 light = vec3(0.953, 0.741, 0.451);
    vec3 result = mix(shadow, vec3(0.36, 0.33, 0.33), smoothstep(0.05, 0.8, l));
    float n = noise(gl_FragCoord.xy * 0.08);
    float crack = smoothstep(0.60, 0.66, n) * (1.0 - smoothstep(0.66, 0.72, n));
    crack *= 0.45 + 0.35 * (0.5 + 0.5 * sin(u_Time * 1.6));
    result = mix(result, mid, crack * smoothstep(0.08, 0.3, l));
    // each beat the embers flare: the cracks go amber, the coal glows copper
    float beat = heartbeat(u_Time);
    result = mix(result, light, beat * crack * 0.8);
    result = mix(result, mid, beat * 0.3 * smoothstep(0.1, 0.6, l));
    result = mix(result, c, face(c) * 0.5);
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
