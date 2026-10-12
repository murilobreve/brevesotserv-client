// Rarity item tint - Legendarius (old gold)
// Gilded: the highlights turn to warm gold while the shadows keep the item's
// own colours, a broad golden sheen crosses it and a few sparks catch the
// light.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// "Color" blend: the gem's hue and saturation at the pixel's own brightness,
// so the item keeps its light, shade and drawing and only takes the tone
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

const vec3 GOLD = vec3(0.886, 0.643, 0.263);
const vec3 BRIGHT = vec3(1.000, 0.902, 0.690);

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;
    float lum = luma(c);

    // gilding grows with brightness: dark lines stay, metal turns gold
    float gild = smoothstep(0.10, 0.75, lum);
    vec3 result = mix(c, setLuma(GOLD, lum), 0.50 * gild);
    result = mix(result, BRIGHT, 0.18 * smoothstep(0.60, 0.95, lum));

    float band = sin((gl_FragCoord.x * 0.8 + gl_FragCoord.y) * 0.030 - u_Time * 1.3);
    float sheen = smoothstep(0.80, 1.0, band) * smoothstep(0.18, 0.70, lum);
    result = mix(result, BRIGHT, sheen * 0.38);

    // sparks: a few pixels flare up and fade, each at its own pace
    vec2 cell = floor(gl_FragCoord.xy / 2.0);
    float seed = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
    float spark = step(0.985, seed) * pow(max(0.0, sin(u_Time * 2.4 + seed * 50.0)), 8.0) * smoothstep(0.20, 0.55, lum);
    result = mix(result, vec3(1.0, 0.97, 0.88), spark * 0.9);

    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
