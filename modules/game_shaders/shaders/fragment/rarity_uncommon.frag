// Rarity item tint - Communis (jade)
// The item keeps its own colours: the grade's gem tone is laid over its
// midtones and highlights (30%), shadows stay its own, and a slow band of
// light crosses it now and then.
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

const vec3 GEM = vec3(0.388, 0.753, 0.541);

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;
    float lum = luma(c);

    float mask = smoothstep(0.08, 0.55, lum);
    vec3 result = mix(c, setLuma(GEM, lum), 0.3 * mask);

    // screen space, not v_TexCoord: the texture coordinate is a place in the
    // sprite atlas and would jump on every animation frame
    float band = sin((gl_FragCoord.x * 0.8 + gl_FragCoord.y) * 0.032 - u_Time * 1.0);
    float sheen = smoothstep(0.86, 1.0, band) * smoothstep(0.20, 0.70, lum);
    result = mix(result, mix(GEM, vec3(1.0), 0.65), sheen * 0.16);

    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
