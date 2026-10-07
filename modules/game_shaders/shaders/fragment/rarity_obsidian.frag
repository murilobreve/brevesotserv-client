// Baiak Rarity System - Obsidian Tier
// Purple and blue: a deep indigo body whose shading runs from violet in the
// shadows to electric blue in the light, with a slow wave of colour moving
// between the two. The wave is keyed by the pixel's own colour (not by
// v_TexCoord, which moves around the sprite atlas every animation frame),
// so the monster does not flicker while it walks.

uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    vec3 c = col.rgb;
    float lum = dot(c, vec3(0.299, 0.587, 0.114));

    vec3 deepIndigo = vec3(0.06, 0.02, 0.18);
    vec3 violet = vec3(0.46, 0.14, 0.78);
    vec3 electricBlue = vec3(0.18, 0.42, 1.00);
    vec3 paleGlow = vec3(0.70, 0.78, 1.00);

    // shadows violet, light blue
    vec3 result = mix(deepIndigo, violet, smoothstep(0.02, 0.45, lum));
    result = mix(result, electricBlue, smoothstep(0.40, 0.80, lum));
    result = mix(result, paleGlow, smoothstep(0.85, 1.00, lum) * 0.5);

    // slow wave swapping purple and blue over the body
    float wave = sin(lum * 9.0 + (c.r - c.b) * 6.0 + u_Time * 1.4) * 0.5 + 0.5;
    vec3 swapped = vec3(result.b * 0.55, result.g, result.r + result.b * 0.35);
    result = mix(result, swapped, wave * 0.35);

    // a little of the original detail
    result += (c - vec3(lum)) * 0.10;

    // soft pulse
    result *= 0.92 + 0.08 * sin(u_Time * 2.2);

    gl_FragColor = vec4(clamp(result, 0.0, 1.0), col.a);
}
