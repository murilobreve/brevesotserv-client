// Rarity item glow - Praeclarus (amethyst): saturated amethyst metal, further
// from Rarus's blue, and a light that visits three parts of the item one
// after the other.
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

const vec3 DEEP = vec3(0.255, 0.145, 0.376);
const vec3 GEM = vec3(0.686, 0.471, 0.918);
const vec3 LIGHT = vec3(0.867, 0.757, 1.000);
void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;
    float lum = luma(c);
    float m = metal(c, lum);
    // screen space, not v_TexCoord: the texture coordinate is a place in the
    // sprite atlas and would jump on every animation frame
    vec2 p = gl_FragCoord.xy;
    vec3 tone = mix(DEEP, GEM, smoothstep(0.10, 0.65, lum));
    vec3 result = mix(c, setLuma(tone, lum * 1.08), 0.82 * m);
    result = mix(result, setLuma(GEM, lum), 0.12 * (1.0 - m));
    // three bands down the item, lit in turn, 1.3 s each
    float region = mod(floor(p.y / 11.0), 3.0);
    float phase = u_Time / 1.3;
    float lit = 1.0 - smoothstep(0.0, 0.5, abs(mod(phase, 3.0) - region - 0.5));
    lit *= 0.5 + 0.5 * sin(fract(phase) * 3.14159);
    result = mix(result, LIGHT, lit * 0.32 * m);
    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
