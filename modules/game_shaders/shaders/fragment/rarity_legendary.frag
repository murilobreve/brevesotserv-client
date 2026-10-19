// Rarity item glow - Legendarius (old gold): golden metal on its light parts,
// the shadows keep their own colour, and a few grains of light come and go
// softly, each on its own 2.8 to 3.5 s.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// "Color" blend: a tone at the pixel's own brightness, so the drawing stays
vec3 setLuma(vec3 c, float l)
{
    c += l - luma(c);
    float L = luma(c);
    float n = min(min(c.r, c.g), c.b);
    float x = max(max(c.r, c.g), c.b);
    if (n < 0.0) c = L + (c - L) * L / max(L - n, 0.0001);
    if (x > 1.0) c = L + (c - L) * (1.0 - L) / max(x - L, 0.0001);
    return c;
}

// the item's metal and leather (its greys) take the grade's material; its
// own colours (a red dragon on a shield) stay as they are
float metal(vec3 c, float lum)
{
    float sat = max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
    return (1.0 - smoothstep(0.12, 0.38, sat)) * smoothstep(0.05, 0.22, lum);
}

const vec3 DEEP = vec3(0.424, 0.263, 0.125);
const vec3 GOLD = vec3(0.886, 0.643, 0.263);
const vec3 BRIGHT = vec3(1.000, 0.886, 0.631);
void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;
    float lum = luma(c);
    float m = metal(c, lum);
    // screen space, not v_TexCoord: the texture coordinate is a place in the
    // sprite atlas and would jump on every animation frame
    vec2 p = gl_FragCoord.xy;
    vec3 tone = mix(DEEP, GOLD, smoothstep(0.10, 0.6, lum));
    tone = mix(tone, BRIGHT, smoothstep(0.65, 0.95, lum));
    vec3 result = mix(c, setLuma(tone, lum * 1.12), 0.88 * m);
    result = mix(result, setLuma(GOLD, lum), 0.10 * (1.0 - m));
    vec2 cell = floor(p / 3.0);
    float seed = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
    float period = 2.8 + 0.7 * fract(seed * 7.0);
    float grain = step(0.965, seed) * pow(0.5 + 0.5 * sin(6.2832 * u_Time / period + seed * 40.0), 6.0);
    result = mix(result, vec3(1.0, 0.96, 0.82), grain * 0.85 * smoothstep(0.15, 0.5, lum));
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
