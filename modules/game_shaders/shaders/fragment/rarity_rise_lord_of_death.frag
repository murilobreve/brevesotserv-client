// Rarity revive - Lord of Death, rising: the heart races. The veins blaze
// red over a black body and a red rim burns around it.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec2 fc = gl_FragCoord.xy;
    vec3 result = mix(col.rgb, vec3(0.05, 0.02, 0.03), 0.80);
    float beat = 0.5 + 0.5 * sin(u_Time * 20.0);
    float n = noise(fc * 0.06) * 0.6 + noise(fc * 0.15) * 0.4;
    float vein = 1.0 - smoothstep(0.0, 0.07, abs(n - 0.5));
    result = mix(result, vec3(1.0, 0.10, 0.06), vein * (0.5 + 0.5 * beat) * step(0.01, col.a));
    result = mix(result, vec3(0.7, 0.0, 0.0), 0.25 * beat * step(0.01, col.a));
    float rim = step(0.01, col.a) * (1.0 - smoothstep(0.0, 0.7, col.a));
    result += vec3(1.0, 0.1, 0.05) * rim;
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
