// Rarity item glow - Mythicus (pearl and opal): pearl metal whose edges play
// rose and cyan like opal, drifting slowly, and small points of light that
// take turns over a 5 s cycle. The item is never lit all at once.
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

const vec3 PEARL = vec3(0.910, 0.894, 1.000);
const vec3 ROSE = vec3(0.941, 0.722, 0.847);
const vec3 CYAN = vec3(0.663, 0.902, 0.875);
const vec3 SHADE = vec3(0.294, 0.275, 0.420);
void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;
    float lum = luma(c);
    float m = metal(c, lum);
    // screen space, not v_TexCoord: the texture coordinate is a place in the
    // sprite atlas and would jump on every animation frame
    vec2 p = gl_FragCoord.xy;
    vec3 tone = mix(SHADE, PEARL, smoothstep(0.08, 0.7, lum));
    float drift = 0.5 + 0.5 * sin((p.x + p.y) * 0.09 + lum * 6.0 - u_Time * 1.25);
    vec3 opal = mix(ROSE, CYAN, drift);
    // opal on the edges of the metal, pearl in its middle
    float edge = smoothstep(0.25, 0.55, lum) * (1.0 - smoothstep(0.75, 0.95, lum));
    tone = mix(tone, opal, edge * 0.55);
    vec3 result = mix(c, setLuma(tone, lum * 1.15), 0.85 * m);
    result = mix(result, setLuma(PEARL, lum), 0.10 * (1.0 - m));
    vec2 cell = floor(p / 3.0);
    float seed = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
    float star = step(0.97, seed) * pow(0.5 + 0.5 * sin(6.2832 * u_Time / 5.0 + seed * 60.0), 8.0);
    result = mix(result, mix(vec3(1.0), opal, 0.35), star * 0.9);
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
