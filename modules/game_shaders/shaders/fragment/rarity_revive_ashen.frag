// Rarity revive - Ashen, waking: the corpse burns out into grey ash. Cracks
// of ember glow open across it and breathe, and sparks drift up from it like
// from a fire that is about to catch again.
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

    // ash: grey, with the light and shade of the body
    vec3 result = mix(col.rgb, vec3(0.42, 0.42, 0.44) * (0.5 + lum), 0.80);

    // ember cracks that breathe
    float n = noise(fc * 0.045);
    float crack = 1.0 - smoothstep(0.0, 0.11, abs(n - 0.5));
    float breath = 0.55 + 0.45 * sin(u_Time * 3.0 + n * 6.0);
    vec3 ember = mix(vec3(0.95, 0.30, 0.05), vec3(1.0, 0.75, 0.25), breath);
    result = mix(result, ember, crack * breath * step(0.01, col.a));
    float alpha = col.a;

    // sparks rising: tiny bright dots climbing through the tile
    vec2 p = vec2(fc.x * 0.07, fc.y * 0.07 - u_Time * 1.8);
    vec2 cell = floor(p);
    float h = hash(cell);
    vec2 inCell = fract(p) - vec2(0.5);
    float spark = step(0.86, h) * (1.0 - smoothstep(0.08, 0.30, length(inCell)));
    spark *= 0.5 + 0.5 * sin(u_Time * 8.0 + h * 40.0);
    result = mix(result, vec3(1.0, 0.65, 0.20), spark);
    alpha = max(alpha, spark);

    gl_FragColor = vec4(clamp(result, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
}
