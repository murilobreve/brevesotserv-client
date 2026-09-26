// Baiak Rarity System - Ashen Tier
// Strange Ash - dusty gray with cursed irregular tinting

uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;

    // Brightness
    float lum = dot(c, vec3(0.299, 0.587, 0.114));
    vec3 gray = vec3(lum);

    // Base ash look
    vec3 ashDark  = vec3(0.12, 0.13, 0.15);
    vec3 ashLight = vec3(0.58, 0.60, 0.64);

    vec3 result = mix(ashDark, ashLight, pow(lum, 0.95));

    // Keep a little bit of original structure
    vec3 base = mix(c, gray, 0.78);
    result = mix(result, base, 0.22);

    // --------------------------------------------------
    // Strange irregular tint
    // --------------------------------------------------

    // Stable pseudo-random fields from texture coordinates
    float n1 = hash(floor(v_TexCoord * 48.0));
    float n2 = hash(floor(v_TexCoord * 24.0) + 17.0);
    float n3 = hash(floor(v_TexCoord * 12.0) + 53.0);

    float strange = (n1 * 0.50 + n2 * 0.35 + n3 * 0.15);

    // Strange colors
    vec3 sickGreen = vec3(0.34, 0.40, 0.28);
    vec3 bruiseViolet = vec3(0.33, 0.28, 0.40);
    vec3 deadCyan = vec3(0.28, 0.38, 0.42);

    // Blend between strange tones
    vec3 weirdColor = mix(sickGreen, bruiseViolet, smoothstep(0.25, 0.75, strange));
    weirdColor = mix(weirdColor, deadCyan, smoothstep(0.68, 0.95, strange));

    // Affect mainly midtones, less the darkest and brightest parts
    float weirdMask =
        smoothstep(0.18, 0.45, lum) *
        (1.0 - smoothstep(0.68, 0.90, lum));

    // Subtle corruption
    result = mix(result, weirdColor, weirdMask * 0.26);

    // Preserve very dark outlines/details
    float darkMask = 1.0 - smoothstep(0.10, 0.28, lum);
    result = mix(result, c * 0.60, darkMask * 0.55);

    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}