// Rarity revive - Lord of Death, waking: the corpse goes black and red veins
// spread through it, pulsing with a heart that beats faster and faster, while
// dark smoke pours out of it.
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

    // the body sinks into black
    vec3 result = mix(col.rgb, vec3(0.05, 0.02, 0.03) + col.rgb * 0.15, 0.85);

    // a heart that quickens over a 6 s cycle
    float speed = 1.5 + 2.5 * fract(u_Time / 6.0);
    float t = fract(u_Time * speed * 0.5);
    float beat = exp(-pow((t - 0.10) * 12.0, 2.0)) + 0.6 * exp(-pow((t - 0.35) * 12.0, 2.0));

    // veins: thin lines of a noise field, lit by the beat
    float n = noise(fc * 0.06) * 0.6 + noise(fc * 0.15) * 0.4;
    float vein = 1.0 - smoothstep(0.0, 0.035, abs(n - 0.5));
    result = mix(result, vec3(0.95, 0.06, 0.05), vein * (0.35 + 0.65 * beat) * step(0.01, col.a));
    float alpha = col.a;

    // dark smoke pouring up, over the empty pixels too
    float smoke = noise(vec2(fc.x * 0.04, fc.y * 0.03 - u_Time * 1.2)) * noise(vec2(fc.x * 0.08 + 7.0, fc.y * 0.05 - u_Time * 1.8));
    float s = smoothstep(0.25, 0.55, smoke);
    result = mix(result, vec3(0.08, 0.0, 0.02), s * (1.0 - col.a));
    alpha = max(alpha, s * 0.55);

    gl_FragColor = vec4(clamp(result, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
}
