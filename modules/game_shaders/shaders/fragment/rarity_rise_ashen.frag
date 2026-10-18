// Rarity revive - Ashen, rising: the ash catches. The cracks flare wide and
// the whole body flickers between hot ember and grey ash.
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
    float lum = luma(col.rgb);
    vec3 ash = mix(col.rgb, vec3(0.45, 0.45, 0.47) * (0.5 + lum), 0.75);
    float n = noise(fc * 0.045 + vec2(0.0, -u_Time * 1.5));
    float crack = 1.0 - smoothstep(0.0, 0.16, abs(n - 0.5));
    float flicker = 0.5 + 0.5 * sin(u_Time * 22.0 + n * 10.0);
    vec3 ember = mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.85, 0.45), flicker);
    vec3 result = mix(ash, ember, max(crack, 0.25 * flicker) * step(0.01, col.a));
    float rim = step(0.01, col.a) * (1.0 - smoothstep(0.0, 0.7, col.a));
    result += vec3(1.0, 0.5, 0.1) * rim;
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
