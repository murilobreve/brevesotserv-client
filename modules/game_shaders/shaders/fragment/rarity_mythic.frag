// Rarity item tint - Mythicus (pearl and opal)
// Pearl: the item turns a bright pearly white while its dark lines and a
// trace of its own colour stay, so it is still recognisable. Over it a band
// of opal light passes, shifting through soft pastel hues, with a quick
// glint and twinkling sparkles.
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

const vec3 PEARL = vec3(0.945, 0.937, 1.000);

// soft pastel of hue h (0..1), for the opal play of colour
vec3 opal(float h)
{
    vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return mix(vec3(1.0), k, 0.38);
}

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;
    float lum = luma(c);

    // pearl body: most of the colour drains, the light parts go white
    vec3 result = mix(c, vec3(lum), 0.55);
    float bright = smoothstep(0.10, 0.80, lum);
    result = mix(result, PEARL, bright * 0.72);
    // dark lines stay dark: the item's drawing
    float dark = 1.0 - smoothstep(0.06, 0.26, lum);
    result = mix(result, c * 0.80, dark * 0.75);

    // opal band, its hue drifting along the band and with time
    float pos = gl_FragCoord.x * 0.055 + gl_FragCoord.y * 0.040;
    float band = sin(pos - u_Time * 1.9);
    float sheen = smoothstep(0.55, 1.0, band) * smoothstep(0.08, 0.60, lum);
    vec3 play = opal(fract(pos * 0.07 + u_Time * 0.06));
    result = mix(result, play, sheen * 0.55);

    // a second, slower pearl reflection across it
    float band2 = sin(gl_FragCoord.x * 0.036 - gl_FragCoord.y * 0.054 - u_Time * 1.4);
    result = mix(result, vec3(1.0), smoothstep(0.86, 1.0, band2) * smoothstep(0.25, 0.80, lum) * 0.35);

    // quick thin glint every few seconds
    float glint = sin((gl_FragCoord.x + gl_FragCoord.y) * 0.090 - u_Time * 4.2);
    result = mix(result, vec3(1.0), smoothstep(0.985, 1.0, glint) * smoothstep(0.10, 0.50, lum) * 0.85);

    // twinkling sparkles, tinted by the opal
    vec2 cell = floor(gl_FragCoord.xy / 2.0);
    float seed = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
    float twinkle = step(0.965, seed) * pow(max(0.0, sin(u_Time * 3.1 + seed * 60.0)), 6.0) * smoothstep(0.10, 0.45, lum);
    result = mix(result, mix(vec3(1.0), opal(seed), 0.5), twinkle);

    // gentle breathing glow
    result += vec3(0.05) * (0.5 + 0.5 * sin(u_Time * 1.2)) * bright;

    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
